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
  return hosts.contains(uri.host) ||
      [
        'embedtv.cc',
        'ebtv.lat',
        'playerembcanais.com',
      ].any((host) => uri.host.endsWith('.$host'));
}
