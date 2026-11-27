import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bechi_player_prototype/bechi_api.dart';
import 'package:bechi_player_prototype/native_source.dart';
import 'package:bechi_player_prototype/player_view.dart';
import 'package:bechi_player_prototype/source_case.dart';
import 'native_source_test.dart' show MemorySessionStore, seasonsFor, streamId;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.bechiflix.native/hosted');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final (code, dnsUnavailable) in [
    ('SOURCE_DNS', true),
    ('SOURCE_ACCESS', true),
    ('SOURCE_TLS', true),
    ('SOURCE_NO_RESPONSE', true),
    ('SOURCE_NO_RESPONSE', false),
    ('SOURCE_CONNECTION', true),
    ('SOURCE_TIMEOUT', false),
  ]) {
    test(
      'SuperFlix delivery after $code with DNS failure=$dnsUnavailable',
      () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'close') return null;
          throw PlatformException(code: code);
        });
        final source = sourceCases.first;
        var serverAttempts = 0;
        final api = BechiApi(
          store: MemorySessionStore(),
          transport: (m, path, body, scope) async {
            if (path == 'titles/${source.slug}') {
              return {
                'data': {'id': 'series', 'kind': 'series'},
              };
            }
            if (path.endsWith('/seasons')) return {'data': seasonsFor(source)};
            if (path == 'playback/$streamId?delivery=native') {
              return {
                'data': {'url': 'https://superflixapi.boats/serie/71225/1/1'},
              };
            }
            if (path == 'playback/$streamId') {
              serverAttempts++;
              return {
                'data': {
                  'url':
                      '/api/v1/superflix/start/$streamId/index.m3u8?exp=1&sig=test',
                },
              };
            }
            if (path.startsWith('superflix/connection/')) {
              return {
                'data': {'ready': true},
              };
            }
            throw StateError(path);
          },
        );
        var lookups = 0;
        final session = NativeSourceSession(
          api,
          source,
          onStatus: (_) {},
          lookupFailed: (host) async {
            expect(host, 'superflixapi.boats');
            lookups++;
            return dnsUnavailable;
          },
        );
        try {
          final ambiguous = [
            'SOURCE_NO_RESPONSE',
            'SOURCE_CONNECTION',
            'SOURCE_TIMEOUT',
          ].contains(code);
          if (code == 'SOURCE_DNS' || ambiguous && dnsUnavailable) {
            final playback = await session.open();
            expect(
              playback.url,
              startsWith('$bechiOrigin/api/v1/superflix/start/$streamId/'),
            );
            expect(serverAttempts, 1);
          } else {
            await expectLater(
              session.open(),
              throwsA(isA<ApiFailure>().having((e) => e.code, 'code', code)),
            );
            expect(serverAttempts, 0);
          }
          expect(lookups, ambiguous ? 1 : 0);
        } finally {
          await session.close();
          api.dispose();
        }
      },
    );
  }

  for (final scenario in [
    'transient',
    'persistent',
    'verification',
    'verification-recovers',
    'human',
    'denied',
  ]) {
    test('server preparation reports $scenario separately', () async {
      final source = sourceCases.first;
      var attempts = 0;
      var releases = 0;
      final sessionIds = <Object?>{};
      final statuses = <String>[];
      final api = BechiApi(
        store: MemorySessionStore(),
        transport: (m, path, body, scope) async {
          if (path == 'titles/${source.slug}') {
            return {
              'data': {'id': 'series', 'kind': 'series'},
            };
          }
          if (path.endsWith('/seasons')) return {'data': seasonsFor(source)};
          if (path.startsWith('playback/')) {
            return {
              'data': {
                'url':
                    '$bechiOrigin/api/v1/superflix/start/$streamId/index.m3u8',
              },
            };
          }
          if (!path.startsWith('superflix/connection/')) throw StateError(path);
          if (body?['release'] == true) {
            releases++;
            expect(sessionIds, contains(body?['session_id']));
            return {
              'data': {'ok': true},
            };
          }
          attempts++;
          sessionIds.add(body?['session_id']);
          if (scenario == 'denied') {
            throw const ApiFailure('ACCESS', 'Negado', status: 403);
          }
          if (scenario == 'persistent' ||
              scenario == 'transient' && attempts == 1) {
            throw const ApiFailure('INTERNAL', 'Erro', status: 500);
          }
          return {
            'data': switch (scenario) {
              'verification' => {'verificationFailed': true},
              'verification-recovers' =>
                attempts == 1
                    ? {
                        'state': 'verification_required',
                        'verificationFailed': true,
                      }
                    : {'ready': true},
              'human' => {
                'mobile': {'needs_action': true},
              },
              _ => attempts == 2 ? {'state': 'loading'} : {'ready': true},
            },
          };
        },
      );
      final session = NativeSourceSession(
        api,
        source,
        onStatus: statuses.add,
        pollInterval: scenario == 'verification'
            ? const Duration(milliseconds: 25)
            : Duration.zero,
        preparationTimeout: scenario == 'verification'
            ? const Duration(milliseconds: 10)
            : const Duration(minutes: 4),
      );
      try {
        if (scenario == 'transient') {
          final media = await session.open();
          expect(media.url, contains('/superflix/start/'));
          expect(statuses, contains(contains('carregando a página')));
          expect(sessionIds.length, 1);
          expect(attempts, 3);
        } else if (scenario == 'verification-recovers') {
          final media = await session.open();
          expect(media.url, contains('/superflix/start/'));
          expect(statuses, contains(contains('Aguardando a verificação')));
          expect(attempts, 2);
          expect(sessionIds.length, 1);
        } else {
          final expected = {
            'persistent': 'INTERNAL',
            'verification': 'VERIFICATION_FAILED',
            'human': 'VERIFICATION',
            'denied': 'ACCESS',
          };
          await expectLater(
            session.open(),
            throwsA(
              isA<ApiFailure>().having(
                (e) => e.code,
                'code',
                expected[scenario],
              ),
            ),
          );
          expect(attempts, scenario == 'persistent' ? 3 : 1);
          expect(releases, 1);
        }
      } finally {
        await session.close();
        expect(releases, 1);
        api.dispose();
      }
    });
  }

  test(
    'intro and credits follow the TV markers independently of control visibility',
    () {
      final data = {
        'episode_id': 'episode',
        'next_stream_id': 'next',
        'stream': {'kind': 'main'},
        'intro_start_seconds': 1,
        'intro_end_seconds': 103,
        'episode_end_seconds': 40,
      };
      String? at(int seconds) => episodeAction(
        data,
        Duration(seconds: seconds),
        const Duration(minutes: 10),
      );
      expect(at(0), isNull);
      expect(at(1), 'intro');
      expect(at(103), isNull);
      expect(at(559), isNull);
      expect(at(560), 'next');
      data.remove('next_stream_id');
      expect(at(560), isNull);
    },
  );
}
