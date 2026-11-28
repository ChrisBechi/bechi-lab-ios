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
import 'package:bechi_player_prototype/native_engine.dart'
    show selectNativeSubtitle;

// The official libmpv 0.6.0 simulator slice has no AudioUnit driver. Exercise
// actual decoding through a virtual sink only in CI, never in device builds.
const simulatorDecoderOnly = bool.fromEnvironment(
  'BECHI_SIMULATOR_DECODER_ONLY',
);
const simulatorTestChannel = MethodChannel('app.bechiflix.native/test');
const expectedCodecs = {
  'codec-avi': ('mpeg4', 'mp3'),
  'codec-hevc': ('hevc', 'eac3'),
  'codec-mp4': ('h264', 'aac'),
  'codec-mkv': ('h264', 'ac3'),
  'codec-webm': ('vp9', 'opus'),
  'codec-mov': ('h264', 'pcm_s16le'),
  'codec-ts': ('h264', 'aac'),
  'codec-flv': ('flv1', 'mp3'),
  'codec-wmv': ('wmv2', 'wmav2'),
  'codec-mpeg': ('mpeg2video', 'mp2'),
  'codec-dts': ('h264', 'dts'),
};
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
  final diagnosticRunId = DateTime.now().microsecondsSinceEpoch.toString();
  debugPrint('NATIVE_CODEC_BEGIN $diagnosticRunId');
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
        final outcome = <String, dynamic>{
          'source': source.id,
          'passed': false,
          'run_id': diagnosticRunId,
        };
        var playerOwnedByPage = false;
        try {
          final configured = await tester.runAsync(() async {
            await prepareDiagnosticPlayer(player);
            return true;
          });
          expect(
            configured,
            true,
            reason: 'The native test environment must initialize.',
          );
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
          await until(tester, () {
            final displaySize = binding.platformDispatcher.implicitView!.physicalSize;
            return displaySize.width > displaySize.height;
          });
          outcome['player_landscape'] = true;
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
          // Current mpv versions expose codec names on track-list. The old
          // video-codec property can be absent even while decoding correctly.
          final videoCodec = player.state.tracks.video
              .where((t) => t.id != 'no' && t.id != 'auto')
              .first
              .codec;
          final audioCodec = player.state.tracks.audio
              .where((t) => t.id != 'no' && t.id != 'auto')
              .first
              .codec;
          final expected = expectedCodecs[source.id]!;
          expect(videoCodec, expected.$1);
          expect(audioCodec, expected.$2);
          await tester.runAsync(
            () => key.currentState!.controller.waitUntilFirstFrameRendered
                .timeout(const Duration(seconds: 5)),
          );
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
            await selectNativeSubtitle(player, subtitle);
            await until(
              tester,
              () => player.state.subtitle.any(
                (v) => v.contains('Teste de legenda'),
              ),
            );
            await key.currentState!.seek(const Duration(seconds: 9));
            await until(
              tester,
              () => player.state.subtitle.any(
                (v) => v.contains('A legenda continuou'),
              ),
            );
            await key.currentState!.seek(const Duration(seconds: 1));
            await until(
              tester,
              () => player.state.subtitle.any(
                (v) => v.contains('Teste de legenda'),
              ),
            );
            await selectNativeSubtitle(player, SubtitleTrack.no());
            await until(
              tester,
              () => player.state.subtitle.every((v) => v.isEmpty),
            );
            outcome['subtitle_select_seek_disable'] = true;
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
          if (!key.currentState!.controls) {
            await tester.tap(find.byKey(const Key('native-video')));
            await tester.pump();
          }
          await tester.tap(find.byKey(const Key('player-back')));
          await until(tester, () => key.currentState == null);
          await tester.pumpAndSettle();
          expect(find.text('Abrir teste'), findsOneWidget);
          await until(tester, () {
            final displaySize = binding.platformDispatcher.implicitView!.physicalSize;
            return displaySize.height > displaySize.width;
          });
          outcome['catalog_portrait'] = true;
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
              'subtitle_text': player.state.subtitle,
              'subtitle_track': player.state.track.subtitle.id,
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
          if (source.id == codecCases.last.id) {
            final passed = codecCases
                .where(
                  (s) => (binding.reportData?[s.id] as Map?)?['passed'] == true,
                )
                .length;
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData.dark(),
                home: Scaffold(
                  body: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            passed == codecCases.length
                                ? Icons.check_circle
                                : Icons.info,
                            color: passed == codecCases.length
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            size: 64,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Testes concluídos',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '$passed de ${codecCases.length} formatos aprovados',
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'A rodada terminou. Esta tela permanece aberta para você conferir o resultado.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
          }
        }
      },
    );
  }
}
