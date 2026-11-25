import 'package:flutter_test/flutter_test.dart';
import 'package:bechi_player_prototype/bechi_api.dart';
import 'package:bechi_player_prototype/native_source.dart';
import 'package:bechi_player_prototype/source_case.dart';

class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.value]);
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? cookie) async {
    value = cookie;
  }
}

const titleId = '40fbc9ee-a128-40cd-8838-b7214c395700';
const streamId = '40fbc9ee-a128-40cd-8838-b7214c395701';
const nextId = '40fbc9ee-a128-40cd-8838-b7214c395702';
const torrentId = '40fbc9ee-a128-40cd-8838-b7214c395703';

Map<String, dynamic> stream(SourceCase source, [String id = streamId]) => {
  'id': id,
  'name': source.id == 'c7'
      ? 'C7 · Berlim'
      : source.id.startsWith('superflix-')
      ? 'SuperFlix'
      : source.name,
  'source_type': source.sourceType,
  'available': true,
  'superflix_browser': source.id.startsWith('superflix-'),
};
List<Map<String, dynamic>> seasonsFor(SourceCase source) => [
  {
    'season_number': source.season,
    'episodes': [
      {
        'episode_number': source.episode,
        'name': 'Episódio 1',
        'streams': [stream(source)],
      },
      {
        'episode_number': source.episode + 1,
        'name': 'Episódio 2',
        'streams': [stream(source, nextId)],
      },
    ],
  },
];

void main() {
  test(
    'source selector keeps all providers separate and chooses the largest magnet',
    () {
      expect(sourceCases.map((s) => s.id).toSet(), hasLength(16));
      final c7 = sourceCases.firstWhere((s) => s.id == 'c7'),
          sf = sourceCases.first;
      expect(
        selectSource(c7, [stream(sf), stream(c7)])?['name'],
        'C7 · Berlim',
      );
      expect(selectSource(sf, [stream(c7)]), isNull);
      expect(
        selectSource(c7, [
          {...stream(c7), 'available': false},
        ]),
        isNull,
      );
      expect(
        selectMagnetOption([
          {'id': 'low', 'available': true, 'label': '720p'},
          {'id': 'high', 'available': true, 'label': '1080p'},
          {'id': 'offline', 'available': false, 'label': '2160p'},
        ])?['id'],
        'high',
      );
    },
  );

  for (final source in sourceCases.where(
    (s) => !s.isLive && s.sourceType != 'torrent',
  )) {
    test(
      '${source.id}: opens exact provider, resumes, changes episode and saves history',
      () async {
        final calls = <String>[], writes = <Map<String, dynamic>>[];
        final api = BechiApi(
          store: MemorySessionStore(),
          transport: (method, path, body, scope) async {
            calls.add('$method $path');
            if (method == 'HEAD') {
              return {
                'data': {'ready': true},
              };
            }
            if (path == 'titles/${source.slug}') {
              return {
                'data': {'id': titleId, 'kind': 'series'},
              };
            }
            if (path == 'titles/$titleId/seasons') {
              return {'data': seasonsFor(source)};
            }
            if (path.startsWith('playback/') && !path.endsWith('lease')) {
              return {
                'data': {
                  'url': '$bechiOrigin/api/v1/fixture/video.mp4',
                  'position_ms': 42000,
                  'title_name': source.example,
                  'next_stream_id': path.endsWith(nextId) ? null : nextId,
                  'variants': [
                    {
                      'label': '1080p',
                      'url': '$bechiOrigin/api/v1/fixture/original.mp4',
                    },
                  ],
                },
              };
            }
            if (path.startsWith('me/progress/')) {
              expect(method, 'PUT');
              writes.add(body!);
              return {
                'data': {'ok': true},
              };
            }
            throw StateError('Unexpected API: $method $path');
          },
        );
        final session = NativeSourceSession(api, source, onStatus: (_) {});
        try {
          final first = await session.open();
          expect(first.position, const Duration(seconds: 42));
          expect(first.variants, hasLength(1));
          session.position = const Duration(seconds: 60);
          session.duration = const Duration(minutes: 40);
          await session.saveProgress();
          expect(writes.single['position_ms'], 60000);
          await session.open(streamId: nextId);
          expect(calls, contains('GET playback/$nextId?delivery=native'));
          expect(calls.where((s) => s.startsWith('GET titles/')), hasLength(2));
        } finally {
          await session.close();
          api.dispose();
        }
      },
    );
  }

  for (final source in sourceCases.where((s) => s.isLive)) {
    test(
      '${source.id}: asks for exact live source and refuses an iframe',
      () async {
        var iframe = false;
        final api = BechiApi(
          store: MemorySessionStore(),
          transport: (m, p, b, s) async {
            expect(m, 'POST');
            expect(p, 'live/resolve');
            expect(b, {
              'kind': 'channel',
              'id': source.liveId,
              'source_index': 0,
              'relay': true,
            });
            return {
              'data': {
                'mode': iframe ? 'iframe' : 'hls',
                'url': '$bechiOrigin/api/v1/live/fixture/index.m3u8',
              },
            };
          },
        );
        final session = NativeSourceSession(api, source, onStatus: (_) {});
        try {
          expect((await session.open()).isLive, isTrue);
          iframe = true;
          await expectLater(
            session.open(),
            throwsA(
              isA<ApiFailure>().having((e) => e.code, 'code', 'NATIVE_SOURCE'),
            ),
          );
        } finally {
          await session.close();
          api.dispose();
        }
      },
    );
  }

  testWidgets(
    'preparation retries, cancellation and timeout never loop forever',
    (tester) async {
      final source = sourceCases.firstWhere((s) => s.id == 'drive');
      var attempts = 0;
      final api = BechiApi(
        store: MemorySessionStore(),
        transport: (m, p, b, s) async {
          if (p == 'titles/${source.slug}') {
            return {
              'data': {'id': titleId, 'kind': 'series'},
            };
          }
          if (p.endsWith('/seasons')) return {'data': seasonsFor(source)};
          attempts++;
          throw const ApiFailure('MEDIA_PREPARING', 'Preparando', status: 409);
        },
      );
      final session = NativeSourceSession(
        api,
        source,
        onStatus: (_) {},
        pollInterval: const Duration(milliseconds: 1),
        preparationTimeout: const Duration(milliseconds: 15),
      );
      try {
        final completion = expectLater(
          session.open(),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.code,
              'code',
              'PREPARATION_TIMEOUT',
            ),
          ),
        );
        await tester.pump();
        expect(attempts, 1);
        await tester.pump(const Duration(milliseconds: 1));
        expect(attempts, greaterThan(1));
        await tester.pump(const Duration(milliseconds: 20));
        await completion;
      } finally {
        await session.close();
        api.dispose();
      }
      final scope = CancelScope();
      final pending = scope.delay(const Duration(hours: 1));
      scope.cancel();
      await expectLater(
        pending,
        throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'CANCELLED')),
      );
    },
  );

  test(
    'magnet selects a real file, sends seek position and deletes only its own session',
    () async {
      final source = sourceCases.firstWhere((s) => s.id == 'magnet'),
          calls = <String>[],
          heartbeats = <Map<String, dynamic>>[];
      var selected = false;
      final api = BechiApi(
        store: MemorySessionStore(),
        transport: (m, p, b, s) async {
          calls.add('$m $p');
          if (p == 'titles/${source.slug}') {
            return {
              'data': {
                'id': titleId,
                'kind': 'movie',
                'source_options': [
                  {'id': 'option', 'label': '1080p', 'available': true},
                ],
              },
            };
          }
          if (p.endsWith('/torrent-session')) {
            return {
              'data': {'id': torrentId},
            };
          }
          if (p == 'torrent/sessions/$torrentId' && m == 'DELETE') {
            return {
              'data': {'ok': true},
            };
          }
          if (p.endsWith('/selection')) {
            expect(b?['fileIndex'], 7);
            selected = true;
            return {'data': {}};
          }
          if (p.endsWith('/heartbeat')) {
            heartbeats.add(b!);
            return {'data': {}};
          }
          if (p.endsWith('/playback')) {
            return {
              'data': {
                'url': '$bechiOrigin/api/v1/torrent/sessions/$torrentId/file',
              },
            };
          }
          if (p == 'torrent/sessions/$torrentId') {
            return {
              'data': {
                'state': selected ? 'READY' : 'SELECTING',
                'files': [
                  {'index': 7},
                ],
                'fileIndex': selected ? 7 : null,
              },
            };
          }
          if (p.startsWith('me/title-progress/')) return {'data': {}};
          throw StateError(p);
        },
      );
      final session = NativeSourceSession(
        api,
        source,
        onStatus: (_) {},
        pollInterval: Duration.zero,
      );
      try {
        await session.open();
        session.position = const Duration(seconds: 90);
        await session.heartbeat(seek: true);
        expect(heartbeats.last, containsPair('position_ms', 90000));
        expect(heartbeats.last['seek'], true);
      } finally {
        await session.close();
        api.dispose();
      }
      expect(calls.where((v) => v.startsWith('DELETE')), [
        'DELETE torrent/sessions/$torrentId',
      ]);
    },
  );

  test('SuperFlix waits for readiness and releases its own connection', () async {
    final source = sourceCases.first, calls = <Map<String, dynamic>>[];
    var polls = 0;
    final api = BechiApi(
      store: MemorySessionStore(),
      transport: (m, p, b, s) async {
        if (p == 'titles/${source.slug}') {
          return {
            'data': {'id': titleId, 'kind': 'series'},
          };
        }
        if (p.endsWith('/seasons')) return {'data': seasonsFor(source)};
        if (p.startsWith('playback/')) {
          return {
            'data': {
              'url':
                  '$bechiOrigin/api/v1/superflix/start/$streamId/index.m3u8?exp=1&sig=fixture',
            },
          };
        }
        if (p.startsWith('superflix/connection/')) {
          calls.add(b!);
          return {
            'data': {'ready': ++polls > 1, 'state': 'connected'},
          };
        }
        throw StateError(p);
      },
    );
    final session = NativeSourceSession(
      api,
      source,
      onStatus: (_) {},
      pollInterval: Duration.zero,
    );
    try {
      expect((await session.open()).url, contains('/superflix/start/'));
    } finally {
      await session.close();
      api.dispose();
    }
    expect(calls.last['release'], true);
    expect(calls.map((v) => v['session_id']).toSet(), hasLength(1));
  });

  test(
    'TeraBox original waits for reserve and releases the quality lease',
    () async {
      final source = sourceCases.firstWhere((s) => s.id == 'terabox');
      var polls = 0;
      final leases = <String>[];
      final api = BechiApi(
        store: MemorySessionStore(),
        transport: (m, p, b, s) async {
          final u = Uri.parse(p);
          if (u.queryParameters['status'] == '1') return {'ready': ++polls > 1};
          if (u.queryParameters.containsKey('lease')) {
            leases.add(u.queryParameters['lease']!);
            return {
              'data': {'ok': true},
            };
          }
          throw StateError(p);
        },
      );
      final session = NativeSourceSession(
        api,
        source,
        onStatus: (_) {},
        pollInterval: Duration.zero,
      );
      try {
        await session.prepareQuality(
          '$bechiOrigin/api/v1/terabox/media/$streamId/original.mkv?exp=1&sig=fixture',
        );
        expect(polls, 2);
        expect(leases, contains('1'));
      } finally {
        await session.close();
        api.dispose();
      }
      expect(leases.last, '0');
    },
  );

  test(
    'session cookie never leaves authenticated first-party media endpoints',
    () async {
      final cookie = 'a' * 43;
      final api = BechiApi(
        store: MemorySessionStore(cookie),
        transport: (m, p, b, s) async => {'data': {}},
      );
      try {
        expect(await api.restore(), true);
        expect(
          api.mediaHeaders(
            Uri.parse('$bechiOrigin/api/v1/torrent/sessions/$torrentId/file'),
          ),
          containsPair('Cookie', 'cine_device=$cookie'),
        );
        expect(
          api.mediaHeaders(Uri.parse('https://cdn.example/video.mp4')),
          isEmpty,
        );
        expect(api.mediaHeaders(Uri.parse('$bechiOrigin/other')), isEmpty);
        await expectLater(
          api.envelope('https://evil.example/steal'),
          throwsA(isA<ApiFailure>()),
        );
        await api.logout();
        expect(api.authenticated, false);
      } finally {
        api.dispose();
      }
    },
  );
}
