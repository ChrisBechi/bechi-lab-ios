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
    ]) {
      expect(allowedNavigation(Uri.parse(url)), isFalse, reason: url);
    }
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
