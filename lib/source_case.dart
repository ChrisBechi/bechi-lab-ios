const bechiOrigin = 'https://bechi-flix.137-131-229-110.sslip.io';

class SourceCase {
  const SourceCase(
    this.id,
    this.name,
    this.example,
    this.sourceType, {
    this.slug,
    this.season = 1,
    this.episode = 1,
    this.liveId,
    this.asset,
  });
  final String id, name, example, sourceType;
  final String? slug, liveId, asset;
  final int season, episode;
  bool get isLive => liveId != null;
}

const codecCases = [
  SourceCase(
    'codec-avi',
    'Teste nativo · AVI / Xvid / MP3',
    'Vídeo sintético local',
    'fixture',
    asset: 'assets/fixtures/native-xvid-mp3.avi',
  ),
  SourceCase(
    'codec-hevc',
    'Teste nativo · HEVC / EAC3 / legendas',
    'Vídeo sintético local com duas faixas de áudio',
    'fixture',
    asset: 'assets/fixtures/native-hevc-eac3.mkv',
  ),
  SourceCase(
    'codec-mp4',
    'Teste nativo · MP4 / AAC',
    'Vídeo sintético local',
    'fixture',
    asset: 'assets/fixtures/native-aac.mp4',
  ),
  SourceCase(
    'codec-mkv',
    'Teste nativo · MKV / AC3',
    'Vídeo sintético local',
    'fixture',
    asset: 'assets/fixtures/native-ac3.mkv',
  ),
];
const sourceCases = [
  SourceCase(
    'superflix-telefonistas',
    'SuperFlix · As Telefonistas',
    'As Telefonistas',
    'hosted_video',
    slug: 'cable-girls',
  ),
  SourceCase(
    'superflix-sereias',
    'SuperFlix · Sereias',
    'Sereias',
    'hosted_video',
    slug: 'sereias-2025',
  ),
  SourceCase(
    'drive',
    'Google Drive',
    'Cyberchase',
    'google_drive',
    slug: 'cyberchase',
  ),
  SourceCase(
    'drive-avi',
    'Google Drive · AVI / Xvid / MP3',
    'Super Shock · T1 EP10',
    'google_drive',
    slug: 'super-shock',
    episode: 10,
  ),
  SourceCase(
    'terabox',
    'TeraBox',
    'Berlim e a Dama com Arminho',
    'terabox',
    slug: 'berlim-e-a-dama-com-arminho',
  ),
  SourceCase(
    'rede-vod',
    'Rede Canais · séries',
    'Sereias',
    'redecanais',
    slug: 'sereias-2025',
  ),
  SourceCase(
    'mediafire',
    'MediaFire',
    'Meu Nome é Farah · T2 EP1',
    'mediafire',
    slug: 'meu-nome-e-farah',
    season: 2,
  ),
  SourceCase(
    'nflix',
    'NoveFlix',
    'Sol da Minha Vida',
    'web_video',
    slug: 'sol-da-minha-vida',
  ),
  SourceCase('c7', 'C7', 'Berlim', 'hosted_video', slug: 'berlim'),
  SourceCase(
    'magnet',
    'Magnet · 1080p',
    'Jogos Mortais 3',
    'torrent',
    slug: 'jogos-mortais-3-2006',
  ),
  SourceCase(
    'archive',
    'Internet Archive',
    'Scooby-Doo',
    'archive_org',
    slug: 'scooby-doo-2002',
  ),
  SourceCase(
    'animes',
    'Animes Digital',
    'Naruto Shippuden',
    'animesdigital',
    slug: 'naruto-shippuden',
  ),
  SourceCase(
    'southpark',
    'South Park oficial',
    'South Park',
    'southpark',
    slug: 'south-park-2006',
  ),
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
Map<String, dynamic> jsonMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<Map<String, dynamic>> jsonRows(dynamic value) => value is List
    ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];
Map<String, dynamic>? selectSource(
  SourceCase source,
  List<Map<String, dynamic>> streams,
) {
  for (final stream in streams) {
    if (stream['available'] == false ||
        stream['source_type'] != source.sourceType) {
      continue;
    }
    if (source.id == 'c7' && !'${stream['name']}'.startsWith('C7')) continue;
    if (source.id.startsWith('superflix-') &&
        stream['superflix_browser'] != true &&
        !'${stream['name']}'.startsWith('SuperFlix')) {
      continue;
    }
    if (stream['id'] is String) return stream;
  }
  return null;
}

Map<String, dynamic>? selectMagnetOption(List<Map<String, dynamic>> options) {
  final available = options.where((v) => v['available'] == true).toList();
  int height(Map<String, dynamic> v) =>
      int.tryParse(
        RegExp(r'(\d{3,4})p').firstMatch('${v['label']}')?.group(1) ?? '',
      ) ??
      0;
  available.sort((a, b) => height(b).compareTo(height(a)));
  return available.isEmpty ? null : available.first;
}
