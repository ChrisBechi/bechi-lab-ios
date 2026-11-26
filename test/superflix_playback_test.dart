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

  for (final code in ['SOURCE_DNS', 'SOURCE_ACCESS', 'SOURCE_TLS']) {
    test('SuperFlix delivery after $code', () async {
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
      final session = NativeSourceSession(api, source, onStatus: (_) {});
      try {
        if (code == 'SOURCE_DNS') {
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
      } finally {
        await session.close();
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
