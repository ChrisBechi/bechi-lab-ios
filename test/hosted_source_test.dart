import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bechi_player_prototype/hosted_source.dart';
import 'package:bechi_player_prototype/bechi_api.dart';

void main() {
  test(
    'owned MP4 supports native ranges, HEAD, suffix seek and private-session closing',
    () async {
      final bytes = await File('assets/fixtures/native-aac.mp4').readAsBytes();
      var closed = false;
      final source = HostedSource(
        publicAddress: (_) async => true,
        invoke: (method, args) async {
          if (method == 'close') {
            closed = true;
            return {};
          }
          expect(method, 'read');
          expect(args?['frame'], 'own-frame');
          final range = RegExp(
                r'bytes=(\d+)-(\d+)',
              ).firstMatch(args!['range'] as String)!,
              start = int.parse(range[1]!),
              end = min(bytes.length - 1, int.parse(range[2]!));
          return {
            'status': 206,
            'type': 'video/mp4',
            'range': 'bytes $start-$end/${bytes.length}',
            'data': base64Encode(bytes.sublist(start, end + 1)),
          };
        },
      );
      final client = HttpClient();
      try {
        final playback = await source.attach({
          'frame': 'own-frame',
          'format': 'mp4',
          'variants': [
            {
              'url': 'https://media.example/own.mp4',
              'height': 1080,
              'label': '1080p',
            },
          ],
        });
        expect(source.owns(playback.url), true);
        final request = await client.getUrl(playback.url);
        request.headers.set('Range', 'bytes=100-199');
        final response = await request.close();
        expect(response.statusCode, 206);
        expect(
          response.headers.value('content-range'),
          'bytes 100-199/${bytes.length}',
        );
        expect(
          await response.expand((b) => b).toList(),
          bytes.sublist(100, 200),
        );
        final suffix = await client.getUrl(playback.url);
        suffix.headers.set('Range', 'bytes=-20');
        expect(
          await (await suffix.close()).expand((b) => b).toList(),
          bytes.sublist(bytes.length - 20),
        );
        final head = await (await client.headUrl(playback.url)).close();
        expect(head.contentLength, bytes.length);
        await head.drain<void>();
        final wrong = playback.url.replace(
          path: playback.url.path.replaceFirst(
            playback.url.pathSegments.first,
            'wrong',
          ),
        );
        final forbidden = await (await client.getUrl(wrong)).close();
        expect(forbidden.statusCode, 403);
        await forbidden.drain<void>();
        final cross = await client.getUrl(playback.url);
        cross.headers.set('Origin', 'https://foreign.example');
        final denied = await cross.close();
        expect(denied.statusCode, 403);
        await denied.drain<void>();
      } finally {
        await source.close();
        client.close(force: true);
      }
      expect(closed, true);
    },
  );
  test(
    'HLS preserves audio and subtitle groups and registers only safe resources',
    () async {
      final ts = Uint8List(188 * 3);
      ts[0] = ts[188] = ts[376] = 0x47;
      final source = HostedSource(
        publicAddress: (_) async => true,
        invoke: (method, args) async {
          if (method == 'close') return {};
          final url = Uri.parse(args!['url'] as String);
          final text = url.path.endsWith('master.m3u8')
              ? '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",LANGUAGE="por",URI="audio.m3u8"\n#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="cc",URI="cc.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=3000000,AUDIO="audio",SUBTITLES="cc"\nhigh.m3u8\n'
              : url.path.endsWith('.m3u8')
              ? '#EXTM3U\n#EXTINF:2,\npart.ts\n#EXT-X-ENDLIST\n'
              : null;
          return {
            'status': 200,
            'type': text == null
                ? 'application/octet-stream'
                : 'application/vnd.apple.mpegurl',
            'data': base64Encode(text == null ? ts : utf8.encode(text)),
          };
        },
      );
      final client = HttpClient();
      try {
        final p = await source.attach({
          'frame': 'own',
          'format': 'hls',
          'variants': [
            {
              'url': 'https://media.example/master.m3u8',
              'height': 0,
              'label': 'Automática',
            },
          ],
        });
        final master = await (await (await client.getUrl(
          p.url,
        )).close()).transform(utf8.decoder).join();
        expect(master, contains('LANGUAGE="por"'));
        expect(master, contains('SUBTITLES="cc"'));
        expect(master, isNot(contains('https://media.example')));
        final high = Uri.parse(master.trim().split('\n').last),
            playlist = await (await (await client.getUrl(
              high,
            )).close()).transform(utf8.decoder).join();
        final part = Uri.parse(
              playlist
                  .split('\n')
                  .firstWhere((line) => line.startsWith('http')),
            ),
            response = await (await client.getUrl(part)).close();
        expect(response.headers.contentType?.mimeType, 'video/mp2t');
        expect((await response.expand((b) => b).toList()).length, ts.length);
        expect(
          () => source.rewritePlaylist(
            '#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd:license"\n',
            Uri.parse('https://media.example/master.m3u8'),
          ),
          throwsA(isA<ApiFailure>()),
        );
      } finally {
        await source.close();
        client.close(force: true);
      }
    },
  );
  test(
    'provider URLs reject private literals, credentials and non-HTTPS media',
    () {
      for (final url in [
        'http://media.example/video',
        'https://127.0.0.1/file',
        'https://[::1]/file',
        'https://user:pass@media.example/file',
        'https://router.local/file',
        'file:///secret',
      ]) {
        expect(() => HostedSource.mediaUrl(url), throwsA(isA<ApiFailure>()));
      }
    },
  );
}
