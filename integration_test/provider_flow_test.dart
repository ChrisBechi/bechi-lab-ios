import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:bechi_player_prototype/bechi_api.dart';
import 'package:bechi_player_prototype/player_view.dart';
import 'package:bechi_player_prototype/source_case.dart';
import 'native_player_test.dart'
    show
        until,
        simulatorDecoderOnly,
        simulatorTestChannel,
        prepareDiagnosticPlayer;

/// Passed to the simulator process at runtime, never compiled into an IPA.
class TemporaryStore implements SessionStore {
  @override
  Future<String?> read() async {
    final token = Platform.environment['BECHI_QA_TOKEN'];
    if (token != null) return token;
    if (!Platform.isIOS) return null;
    final context = await simulatorTestChannel.invokeMapMethod<String, dynamic>(
      'context',
    );
    final nativeToken = context?['qa_session'];
    return nativeToken is String && nativeToken.isNotEmpty ? nativeToken : null;
  }

  @override
  Future<void> write(String? value) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  for (final source in sourceCases) {
    testWidgets(
      '${source.id}: real provider and native playback',
      (tester) async {
        final api = BechiApi(store: TemporaryStore());
        final player = Player();
        final key = GlobalKey<NativePlayerPageState>();
        var playerOwnedByPage = false;
        var outcome = <String, dynamic>{
          'source': source.id,
          'passed': false,
          'stage': 'prepare',
        };
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
          expect(
            await tester.runAsync(api.restore),
            true,
            reason: 'The normal temporary QA session must be active.',
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
                    child: const Text('Abrir fonte'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Abrir fonte'));
          await tester.pump();
          playerOwnedByPage = key.currentState != null;
          await until(
            tester,
            () =>
                key.currentState?.error != null ||
                (key.currentState?.firstFrameMs != null &&
                    key.currentState!.player.state.playing),
            timeout: const Duration(minutes: 4),
          );
          final state = key.currentState!;
          expect(
            state.error,
            isNull,
            reason: 'The requested source must open.',
          );
          expect(state.playback!.sourceType, source.sourceType);
          expect(state.player, same(player));
          expect(player.platform, isA<NativePlayer>());
          expect(player.state.width, greaterThan(0));
          expect(player.state.height, greaterThan(0));
          expect(
            player.state.tracks.audio.where(
              (v) => v.id != 'auto' && v.id != 'no',
            ),
            isNotEmpty,
          );
          await until(
            tester,
            () => (player.state.audioParams.sampleRate ?? 0) > 0,
          );
          final native = player.platform as NativePlayer;
          final audioOutput = await native.getProperty('current-ao');
          expect(audioOutput, simulatorDecoderOnly ? 'null' : isNot('null'));
          outcome.addAll({
            'engine': 'native libmpv',
            'first_frame_ms': state.firstFrameMs,
            'width': player.state.width,
            'height': player.state.height,
            'audio_tracks': player.state.tracks.audio.length,
            'audio_decoded': true,
            'audio_sample_rate': player.state.audioParams.sampleRate,
            'audio_output': audioOutput,
            'system_audio_verified': !simulatorDecoderOnly,
            'stage': 'steady',
          });
          final first = player.state.position;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 12)),
          );
          await tester.pump();
          expect(state.error, isNull);
          expect(
            (player.state.position - first).inSeconds,
            greaterThanOrEqualTo(9),
          );
          await player.pause();
          final paused = player.state.position;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 500)),
          );
          expect(
            (player.state.position - paused).inMilliseconds.abs(),
            lessThan(300),
          );
          await player.play();
          outcome['stage'] = 'seek';
          if (!source.isLive) {
            await state.seek(const Duration(seconds: 30));
            await until(tester, () => player.state.position.inSeconds >= 28);
            await state.seek(const Duration(seconds: 10));
            await until(
              tester,
              () =>
                  player.state.position.inSeconds >= 8 &&
                  player.state.position.inSeconds < 18,
            );
            await state.session.saveProgress();
          }
          outcome['stage'] = 'menus';
          for (final menu in <String, Future<void> Function()>{
            'Áudio': state.chooseAudio,
            'Legendas': state.chooseSubtitle,
            if (state.playback!.variants.isNotEmpty)
              'Qualidade': state.chooseQuality,
            if (state.session.seasons.isNotEmpty)
              'Episódios': state.chooseEpisode,
          }.entries) {
            final showing = menu.value();
            await until(
              tester,
              () => find.text(menu.key).evaluate().isNotEmpty,
            );
            expect(tester.takeException(), isNull);
            Navigator.of(tester.element(find.text(menu.key).first)).pop();
            await tester.pump(const Duration(milliseconds: 400));
            await showing;
          }
          final next = state.playback!.metadata['next_stream_id'];
          if (next is String) {
            outcome['stage'] = 'next_episode';
            await tester.runAsync(state.openNext);
            await until(
              tester,
              () => state.error != null || state.firstFrameMs != null,
              timeout: const Duration(minutes: 4),
            );
            expect(state.error, isNull);
            expect(state.session.activeStreamId, next);
            expect(player.state.playing, true);
            outcome['next_episode_ms'] = state.firstFrameMs;
          }
          outcome.addAll({
            'passed': true,
            'stage': 'complete',
            'pause_resume': true,
            'seek': !source.isLive,
            'menus': true,
          });
        } catch (_) {
          // No media URLs, cookies, tokens or browser state in public diagnostics.
          outcome['error'] =
              key.currentState?.error?.replaceAll(
                RegExp(r'https?://\S+'),
                '[media]',
              ) ??
              'Native provider flow failed or timed out.';
          outcome['status'] = key.currentState?.status;
          rethrow;
        } finally {
          final state = key.currentState;
          if (state != null) {
            final leaving = state.leave();
            await until(
              tester,
              () => key.currentState == null,
              timeout: const Duration(seconds: 15),
            );
            await leaving;
            await tester.pumpAndSettle();
            await state.session.close();
          }
          if (!playerOwnedByPage) await player.dispose();
          api.dispose();
          binding.reportData ??= {};
          binding.reportData![source.id] = outcome;
          // The integration runner emits this structured, non-sensitive summary.
          debugPrint('NATIVE_PROVIDER_RESULT ${jsonEncode(outcome)}');
        }
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
