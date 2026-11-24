const bechiOrigin = 'https://bechi-flix.137-131-229-110.sslip.io';

class SourceCase {
  const SourceCase(
    this.id,
    this.name,
    this.example,
    this.sourceType, {
    this.season = 1,
    this.episode = 1,
    this.year,
    this.liveId,
    this.slug,
  });
  final String id, name, example, sourceType;
  final int season, episode;
  final int? year;
  final String? liveId, slug;
  Uri? get verificationUrl => switch (id) {
    'superflix-telefonistas' => Uri.parse(
      'https://superflixapi.boats/serie/71225/$season/$episode',
    ),
    'superflix-sereias' => Uri.parse(
      'https://superflixapi.boats/serie/246992/$season/$episode',
    ),
    _ => null,
  };
  Uri get initialUrl => Uri.parse(
    liveId == null
        ? bechiOrigin
        : '$bechiOrigin/ao-vivo/canal/$liveId/assistir',
  );
  Map<String, Object?> get configuration => {
    'id': id,
    'name': name,
    'query': example,
    'sourceType': sourceType,
    'season': season,
    'episode': episode,
    'year': year,
    'liveId': liveId,
    'slug': slug,
    'origin': bechiOrigin,
  };
}

const sourceCases = [
  SourceCase(
    'superflix-telefonistas',
    'SuperFlix · As Telefonistas',
    'As Telefonistas',
    'hosted_video',
  ),
  SourceCase(
    'superflix-sereias',
    'SuperFlix · Sereias',
    'Sereias',
    'hosted_video',
    year: 2025,
  ),
  SourceCase('drive', 'Google Drive', 'Cyberchase', 'google_drive'),
  SourceCase('terabox', 'TeraBox', 'Berlim e a Dama com Arminho', 'terabox'),
  SourceCase(
    'rede-vod',
    'Rede Canais · séries',
    'Sereias',
    'redecanais',
    year: 2025,
  ),
  SourceCase(
    'mediafire',
    'MediaFire',
    'Meu Nome é Farah',
    'mediafire',
    season: 2,
  ),
  SourceCase('nflix', 'NoveFlix', 'Sol da Minha Vida', 'web_video'),
  SourceCase('c7', 'C7', 'Berlim', 'hosted_video', year: 2023),
  SourceCase(
    'magnet',
    'Magnet · 1080p',
    'Jogos Mortais',
    'torrent',
    year: 2006,
  ),
  SourceCase(
    'archive',
    'Internet Archive',
    'Scooby-Doo',
    'archive_org',
    year: 2002,
    slug: 'scooby-doo-2002',
  ),
  SourceCase('animes', 'Animes Digital', 'Naruto Shippuden', 'animesdigital'),
  SourceCase('southpark', 'South Park oficial', 'South Park', 'southpark'),
  SourceCase(
    'embed-live',
    'EmbedTV · ao vivo',
    'Premiere',
    'live',
    liveId: 'premiere',
  ),
  SourceCase(
    'rede-live',
    'Rede Canais · ao vivo',
    'SporTV',
    'live',
    liveId: 'rede-canais-rtv-229-2',
  ),
  SourceCase(
    'superflix-live',
    'SuperFlix · ao vivo',
    'SporTV',
    'live',
    liveId: 'superflix-sportv',
  ),
];

/// Applies to document navigation; normal WebKit media protections remain active.
bool allowedNavigation(Uri uri) {
  if (uri.toString() == 'about:blank' || uri.toString() == 'about:srcdoc') {
    return true;
  }
  if (uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return false;
  }
  if (uri.host == 'abyssplayer.com') {
    return RegExp(r'^/[A-Za-z0-9]{8,20}$').hasMatch(uri.path) &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }
  String decodedHost;
  try {
    decodedHost = Uri.decodeComponent(uri.host).toLowerCase();
  } on FormatException {
    return false;
  }
  final host = switch (decodedHost) {
    '\u30b3\u30b3\u30fb\u30ec\u30b9\u30c8\u30e9\u30f3\u4e88\u7d04\u30bb\u30f3\u30bf\u30fc.best' =>
      'xn--tckasiu6cvova0eb5fua2449g98vg.best',
    '\u0441\u043e\u0432\u0435\u0442\u0441\u043a\u043e\u0435\u0441\u043e\u0435\u0432\u043e\u0435\u043c\u0430\u0441\u043b\u043e.delivery' =>
      'xn--80adalaab0boiodbce7addhh.delivery',
    final value => value,
  };
  const hosts = {
    'bechi-flix.137-131-229-110.sslip.io',
    'superflixapi.boats',
    'challenges.cloudflare.com',
    'xn--tckasiu6cvova0eb5fua2449g98vg.best',
    'xn--80adalaab0boiodbce7addhh.delivery',
    'rdcanais.org',
    'caldodecana.fun',
    'mastruzcomleite.site',
    'embedcanaisdetv.xyz',
    'playerembedcanais.site',
    'embedtv.my',
    'embedtv.cc',
    'ebtv.lat',
  };
  return hosts.contains(host) ||
      [
        'embedtv.cc',
        'ebtv.lat',
        'playerembcanais.com',
      ].any((domain) => host.endsWith('.$domain'));
}
