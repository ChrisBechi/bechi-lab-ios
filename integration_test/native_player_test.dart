import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:bechi_player_prototype/bechi_api.dart';
import 'package:bechi_player_prototype/player_view.dart';
import 'package:bechi_player_prototype/source_case.dart';

// The official libmpv 0.6.0 simulator slice has no AudioUnit driver. Exercise
// actual decoding through a virtual sink only in CI, never in device builds.
const simulatorDecoderOnly = bool.fromEnvironment(
  'BECHI_SIMULATOR_DECODER_ONLY',
);
const simulatorTestChannel = MethodChannel('app.bechiflix.native/test');
Future<void> prepareDiagnosticPlayer(Player player) async {
  if (!simulatorDecoderOnly) return;
  final context = await simulatorTestChannel.invokeMapMethod<String, dynamic>(
    'context',
  );
  if (!Platform.isIOS || context?['simulator'] != true) {
    throw StateError('Virtual audio is restricted to the iOS simulator test.');
  }
  await (player.platform as NativePlayer).setProperty('ao', 'null');
}

class EmptyStore implements SessionStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String? value) async {}
}

Future<void> until(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      fail('O motor nativo não atingiu o estado esperado.');
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  testWidgets('Keychain writes, restores and deletes the native session', (
    tester,
  ) async {
    final store = NativeSessionStore();
    try {
      await store.write('a' * 43);
      expect(await store.read(), 'a' * 43);
    } finally {
      await store.write(null);
    }
    expect(await store.read(), isNull);
  });
  for (final source in codecCases) {
    testWidgets(
      '${source.id}: native texture, audio, pause, seek, menus and route cleanup',
      (tester) async {
        final api = BechiApi(store: EmptyStore()),
            player = Player(
              configuration: const PlayerConfiguration(
                bufferSize: 16 * 1024 * 1024,
                logLevel: MPVLogLevel.debug,
              ),
            );
        final errors = <String>[];
        final audioLog = <String>[];
        final audioSub = player.stream.log.listen((event) {
          if (event.prefix.startsWith('ao') || event.prefix.startsWith('ad/')) {
            if (audioLog.length >= 30) audioLog.removeAt(0);
            audioLog.add(
              '${event.prefix}: ${event.text.replaceAll(RegExp(r'https?://\S+'), '[media]').trim()}',
            );
          }
        });
        final sub = player.stream.error.listen(
          (e) => errors.add(e.replaceAll(RegExp(r'https?://\S+'), '[media]')),
        );
        final key = GlobalKey<NativePlayerPageState>();
        final outcome = <String, dynamic>{'source': source.id, 'passed': false};
        var playerOwnedByPage = false;
        try {
          await tester.runAsync(() => prepareDiagnosticPlayer(player));
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(),
              home: Builder(
                builder: (context) => Scaffold(
                  body: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => NativePlayerPage(
                          key: key,
                          api: api,
                          source: source,
                          player: player,
                        ),
                      ),
                    ),
                    child: const Text('Abrir teste'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Abrir teste'));
          await tester.pump(const Duration(milliseconds: 500));
          playerOwnedByPage = key.currentState != null;
          await until(
            tester,
            () =>
                key.currentState?.error != null ||
                player.state.width == 320 &&
                    player.state.position.inMilliseconds > 200 &&
                    (player.state.audioParams.sampleRate ?? 0) > 0,
          );
          expect(key.currentState!.error, isNull);
          expect(player.state.height, 180);
          expect(
            player.state.tracks.audio.where(
              (t) => t.id != 'no' && t.id != 'auto',
            ),
            isNotEmpty,
          );
          final native = player.platform as NativePlayer;
          expect(await native.getProperty('tls-verify'), 'yes');
          expect(await native.getProperty('hls-bitrate'), 'max');
          final videoCodec = await native.getProperty('video-codec');
          final audioCodec = player.state.tracks.audio
              .where((t) => t.id != 'no' && t.id != 'auto')
              .first
              .codec;
          expect(videoCodec, isNotEmpty);
          expect(audioCodec, isNotEmpty);
          expect(player.state.audioParams.channelCount, greaterThan(0));
          final audioOutputRate = int.tryParse(
            await native.getProperty('audio-out-params/samplerate'),
          );
          expect(audioOutputRate, greaterThan(0));
          final audioOutput = await native.getProperty('current-ao');
          expect(audioOutput, simulatorDecoderOnly ? 'null' : isNot('null'));
          await key.currentState!.player.pause();
          await tester.pump();
          final paused = player.state.position;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 350)),
          );
          await tester.pump();
          expect(
            (player.state.position - paused).inMilliseconds.abs(),
            lessThan(250),
          );
          await key.currentState!.seek(const Duration(seconds: 3));
          await until(
            tester,
            () => player.state.position.inMilliseconds >= 2500,
          );
          await key.currentState!.seek(const Duration(seconds: 1));
          await until(
            tester,
            () => player.state.position.inMilliseconds < 2000,
          );
          await key.currentState!.player.play();
          await until(tester, () => player.state.playing);
          if (!key.currentState!.controls) {
            await tester.tap(find.byKey(const Key('native-video')));
            await tester.pump();
          }
          await tester.tap(find.byKey(const Key('player-audio')));
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('Áudio'), findsOneWidget);
          Navigator.of(tester.element(find.text('Áudio'))).pop();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.byKey(const Key('player-subtitles')));
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('Legendas'), findsOneWidget);
          expect(find.text('Desativadas'), findsOneWidget);
          if (source.id == 'codec-hevc') {
            final audio = player.state.tracks.audio
                .where((t) => t.language == 'por')
                .first;
            await player.setAudioTrack(audio);
            expect(player.state.track.audio.id, audio.id);
            final subtitle = player.state.tracks.subtitle
                .where((t) => t.language == 'por')
                .first;
            await player.setSubtitleTrack(subtitle);
            await until(
              tester,
              () => player.state.subtitle.any(
                (v) => v.contains('Teste de legenda'),
              ),
            );
          }
          Navigator.of(tester.element(find.text('Legendas'))).pop();
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          expect(errors, isEmpty);
          outcome.addAll({
            'video': '320x180',
            'video_codec': videoCodec,
            'audio_codec': audioCodec,
            'audio_sample_rate': player.state.audioParams.sampleRate,
            'audio_output_sample_rate': audioOutputRate,
            'audio_decoded': true,
            'audio_output': audioOutput,
            'system_audio_verified': !simulatorDecoderOnly,
            'pause': true,
            'seek_forward': true,
            'seek_back': true,
            'menus': true,
            'engine': 'native libmpv',
            'first_frame_ms': key.currentState!.firstFrameMs,
          });
          final leaving = key.currentState!.leave();
          await until(tester, () => key.currentState == null);
          await leaving;
          await tester.pumpAndSettle();
          expect(find.text('Abrir teste'), findsOneWidget);
          outcome['passed'] = true;
        } finally {
          if (outcome['passed'] != true) {
            outcome.addAll({
              'error': key.currentState?.error ?? 'Native codec check failed.',
              'width': player.state.width,
              'clock_ms': player.state.position.inMilliseconds,
              'audio_sample_rate': player.state.audioParams.sampleRate,
              'engine_errors': errors,
              'audio_log': audioLog,
            });
          }
          await sub.cancel();
          await audioSub.cancel();
          // Remove every route even after an assertion so a previous decoder
          // cannot keep rendering or hold audio resources in the next test.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          if (!playerOwnedByPage) await player.dispose();
          api.dispose();
          binding.reportData ??= {};
          binding.reportData![source.id] = outcome;
          debugPrint('NATIVE_CODEC_RESULT ${jsonEncode(outcome)}');
        }
      },
    );
  }
}
