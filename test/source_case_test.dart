import 'package:flutter_test/flutter_test.dart';
import 'package:bechi_player_prototype/source_case.dart';

void main() {
  test('navigation permits known source and challenge pages only', () {
    for (final url in [
      bechiOrigin,
      'https://superflixapi.boats/serie/71225/1/1',
      'https://challenges.cloudflare.com/cdn-cgi/',
      'about:blank',
      'about:srcdoc',
      'https://current.ebtv.lat/premiere',
      'https://abyssplayer.com/ValidPlayer12',
      'https://\u30b3\u30b3\u30fb\u30ec\u30b9\u30c8\u30e9\u30f3\u4e88\u7d04\u30bb\u30f3\u30bf\u30fc.best/video/0123456789abcdef0123456789abcdef',
      'https://\u0441\u043e\u0432\u0435\u0442\u0441\u043a\u043e\u0435\u0441\u043e\u0435\u0432\u043e\u0435\u043c\u0430\u0441\u043b\u043e.delivery/video/0123456789abcdef0123456789abcdef',
    ]) {
      expect(allowedNavigation(Uri.parse(url)), isTrue, reason: url);
    }
    for (final url in [
      'https://ads.invalid/',
      'https://superflixapi.boats.evil.invalid/',
      'https://user:pass@superflixapi.boats/',
      'http://superflixapi.boats/',
      'https://superflixapi.boats:444/',
      'file:///private/',
      'tel:123',
      'javascript:alert(1)',
      'https://abyssplayer.com/ads',
      'https://abyssplayer.com/ValidPlayer12?next=https://ads.invalid',
      'https://abyssplayer.com.evil.invalid/ValidPlayer12',
      'https://%25/',
    ]) {
      expect(allowedNavigation(Uri.parse(url)), isFalse, reason: url);
    }
  });
  test('verification keeps the selected official title and episode', () {
    expect(sourceCases.first.verificationUrl?.path, '/serie/71225/1/1');
    expect(sourceCases[1].verificationUrl?.path, '/serie/246992/1/1');
    expect(sourceCases.where((item) => item.verificationUrl != null).length, 2);
    expect(
      sourceCases
          .where((item) => item.liveId != null)
          .every((item) => item.verificationUrl == null),
      isTrue,
    );
  });
  test(
    'each source has an independent case using the authenticated app origin',
    () {
      expect(
        sourceCases.map((source) => source.id).toSet().length,
        sourceCases.length,
      );
      expect(
        sourceCases.map((source) => source.sourceType).toSet(),
        containsAll([
          'google_drive',
          'mediafire',
          'terabox',
          'torrent',
          'redecanais',
          'web_video',
          'hosted_video',
          'live',
        ]),
      );
      for (final source in sourceCases) {
        expect(source.initialUrl.origin, bechiOrigin);
        expect(source.initialUrl.userInfo, isEmpty);
      }
    },
  );
}
