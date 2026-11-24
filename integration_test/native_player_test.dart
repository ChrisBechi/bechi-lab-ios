import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:bechi_player_prototype/bechi_api.dart';
import 'package:bechi_player_prototype/player_view.dart';
import 'package:bechi_player_prototype/source_case.dart';

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
  for (final source in codecCases) {
    testWidgets(
      '${source.id}: native texture, audio, pause, seek, menus and route cleanup',
      (tester) async {
        final api = BechiApi(store: EmptyStore()),
            player = Player(
              configuration: const PlayerConfiguration(
                bufferSize: 16 * 1024 * 1024,
              ),
            );
        final errors = <String>[];
        final sub = player.stream.error.listen(
          (e) => errors.add(e.replaceAll(RegExp(r'https?://\S+'), '[media]')),
        );
        final key = GlobalKey<NativePlayerPageState>();
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
        await until(
          tester,
          () =>
              player.state.width == 320 &&
              player.state.position.inMilliseconds > 200,
        );
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
        await until(tester, () => player.state.position.inMilliseconds >= 2500);
        await key.currentState!.seek(const Duration(seconds: 1));
        await until(tester, () => player.state.position.inMilliseconds < 2000);
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
        binding.reportData ??= {};
        binding.reportData![source.id] = {
          'video': '320x180',
          'audio': true,
          'pause': true,
          'seek_forward': true,
          'seek_back': true,
          'menus': true,
          'engine': 'native libmpv',
        };
        await sub.cancel();
        await key.currentState!.leave();
        await tester.pumpAndSettle();
        expect(find.text('Abrir teste'), findsOneWidget);
        api.dispose();
      },
    );
  }
}
