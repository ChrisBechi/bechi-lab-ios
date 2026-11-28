import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'hosted_source.dart';
import 'bechi_api.dart';
import 'source_case.dart';

class NativePlayback {
  NativePlayback({
    required this.url,
    required this.name,
    required this.sourceType,
    this.headers = const {},
    this.position = Duration.zero,
    this.metadata = const {},
    this.variants = const [],
    this.isLive = false,
  });
  final String url, name, sourceType;
  final Map<String, String> headers;
  final Duration position;
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> variants;
  final bool isLive;
}

class NativeSourceSession {
  NativeSourceSession(
    this.api,
    this.source, {
    required this.onStatus,
    this.lookupFailed = _lookupFailed,
    this.pollInterval = const Duration(seconds: 2),
    this.preparationTimeout = const Duration(minutes: 4),
  });
  final BechiApi api;
  final SourceCase source;
  final void Function(String) onStatus;
  final Future<bool> Function(String host) lookupFailed;
  final Duration pollInterval, preparationTimeout;
  final scope = CancelScope();
  String? _torrent, _stream, _titleId, _superflixPath, _superflixSession;
  Timer? _heartbeat, _deadline;
  String? _cacheLease;
  HostedSource? _hosted;
  Uri? _original;
  final _leaseId = _uuid();
  bool _timedOut = false;
  bool _closed = false, _heartbeatBusy = false;
  Duration position = Duration.zero, duration = Duration.zero;
  List<Map<String, dynamic>> seasons = [];
  Map<String, dynamic> title = {};
  NativePlayback? current;
  String? get activeStreamId => _stream;
  bool get canShowSource => _hosted?.canShowSource == true;
  Future<void> showSource() async => _hosted?.showSource();

  static Future<bool> _lookupFailed(String host) async {
    try {
      final addresses = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 5));
      return addresses.isEmpty;
    } on SocketException {
      return true;
    } on TimeoutException {
      // A slow lookup alone does not establish that the name failed to resolve.
      return false;
    }
  }

  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) => api.request(path, method: method, body: body, scope: scope);
  Future<NativePlayback> open({String? streamId}) async {
    scope.check();
    _heartbeat?.cancel();
    await _releaseOwned();
    _deadline?.cancel();
    _timedOut = false;
    _deadline = Timer(preparationTimeout, () {
      _timedOut = true;
    });
    if (source.asset != null) {
      _deadline?.cancel();
      return current = NativePlayback(
        url: 'asset:///${source.asset}',
        name: source.name,
        sourceType: 'fixture',
      );
    }
    if (source.isLive) {
      onStatus('Conectando à transmissão…');
      final p = jsonMap(
        await _request(
          'live/resolve',
          method: 'POST',
          body: {
            'kind': source.isEvent ? 'event' : 'channel',
            'id': source.liveId,
            'source_index': 0,
            'relay': true,
          },
        ),
      );
      if (p['mode'] == 'iframe') {
        throw const ApiFailure(
          'NATIVE_SOURCE',
          'Esta fonte ainda precisa fornecer uma URL de vídeo ao player nativo.',
        );
      }
      _deadline?.cancel();
      return current = _playback(p, live: true);
    }
    onStatus('Consultando o catálogo…');
    if (title.isEmpty) {
      title = jsonMap(await _request('titles/${source.slug}'));
      _titleId = '${title['id']}';
      if (title['kind'] == 'series') {
        seasons = jsonRows(await _request('titles/$_titleId/seasons'));
      }
    }
    if (source.sourceType == 'torrent') return _openTorrent();
    Map<String, dynamic>? stream;
    if (streamId != null) {
      final allowed = seasons
          .expand((s) => jsonRows(s['episodes']))
          .map((e) => selectSource(source, jsonRows(e['streams'])))
          .whereType<Map<String, dynamic>>();
      stream = allowed.where((s) => s['id'] == streamId).firstOrNull;
    } else if (title['kind'] == 'series') {
      final season = seasons
          .where((v) => v['season_number'] == source.season)
          .firstOrNull;
      final episode = jsonRows(
        season?['episodes'],
      ).where((v) => v['episode_number'] == source.episode).firstOrNull;
      stream = selectSource(source, jsonRows(episode?['streams']));
    } else {
      stream = selectSource(source, jsonRows(title['streams']));
    }
    if (stream == null) {
      throw const ApiFailure(
        'SOURCE',
        'A fonte selecionada não está disponível neste título.',
      );
    }
    _stream = '${stream['id']}';
    onStatus('Preparando o vídeo…');
    Map<String, dynamic> p;
    for (;;) {
      try {
        _checkDeadline();
        p = jsonMap(await _request('playback/$_stream?delivery=native'));
        break;
      } on ApiFailure catch (e) {
        if (e.code != 'MEDIA_PREPARING') rethrow;
        onStatus('Preparando o arquivo no servidor…');
        await scope.delay(pollInterval);
      }
    }
    var url = Uri.parse('${p['url']}');
    if (url.host == 'abyssplayer.com' || url.host == 'superflixapi.boats') {
      onStatus(
        source.id == 'c7'
            ? 'Preparando o vídeo da C7…'
            : 'Abrindo a SuperFlix pela rede deste aparelho…',
      );
      _hosted ??= HostedSource(onStatus: onStatus);
      try {
        final local = await _hosted!.prepare(
          url: url.toString(),
          kind: source.id == 'c7' ? 'c7' : 'superflix',
          title: '${p['title_name'] ?? source.example}',
          season: (p['season_number'] as num?)?.toInt() ?? source.season,
          episode: (p['episode_number'] as num?)?.toInt() ?? source.episode,
        );
        p = {
          ...p,
          'url': local.url.toString(),
          'variants': local.variants,
          'source_height': local.height,
        };
      } on ApiFailure catch (error) {
        scope.check();
        if (url.host != 'superflixapi.boats' ||
            !source.id.startsWith('superflix-')) {
          rethrow;
        }
        if (error.code != 'SOURCE_DNS') {
          if (!const {
            'SOURCE_NO_RESPONSE',
            'SOURCE_CONNECTION',
            'SOURCE_TIMEOUT',
          }.contains(error.code)) {
            rethrow;
          }
          onStatus(
            'Conferindo o endereço da SuperFlix na rede deste aparelho…',
          );
          final failed = await lookupFailed(url.host);
          scope.check();
          if (!failed) rethrow;
        }
        await _hosted!.close();
        _hosted = null;
        scope.check();
        onStatus('Esta rede não localizou a SuperFlix. Conectando pelo Bechi…');
        p = jsonMap(await _request('playback/$_stream'));
        final raw = Uri.tryParse('${p['url']}');
        final origin = Uri.parse(bechiOrigin);
        final delivery = raw == null ? null : origin.resolveUri(raw);
        if (delivery == null ||
            delivery.scheme != origin.scheme ||
            delivery.host != origin.host ||
            delivery.port != origin.port ||
            delivery.userInfo.isNotEmpty ||
            delivery.hasFragment ||
            delivery.path != '/api/v1/superflix/start/$_stream/index.m3u8') {
          throw const ApiFailure(
            'SOURCE_DELIVERY',
            'O servidor não disponibilizou o vídeo da SuperFlix.',
          );
        }
        p = {...p, 'url': delivery.toString()};
      }
      url = Uri.parse('${p['url']}');
    }
    if (source.id.startsWith('superflix-') &&
        url.path.startsWith('/api/v1/superflix/start/')) {
      try {
        await _prepareSuperflix(url);
      } catch (_) {
        unawaited(_releaseSuperflix());
        rethrow;
      }
    }
    if (seasons.isNotEmpty) {
      p = {...p, 'next_stream_id': nextStreamId(_stream!)};
    }
    if (source.id == 'nflix') {
      onStatus('Preparando o vídeo na origem…');
      await api.prepareMedia(Uri.parse('${p['url']}'), scope: scope);
    }
    current = _playback(p);
    _deadline?.cancel();
    if (p['cache_managed'] == true) {
      _cacheLease = _stream;
      await _request(
        'playback/$_stream/lease',
        method: 'POST',
        body: {'session_id': _leaseId, 'release': false},
      );
    }
    // The ready response just refreshed this lease. Waiting for a second POST
    // here would delay opening the player even though the video is ready.
    if (_superflixPath == null || _cacheLease != null) await heartbeat();
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
      const Duration(seconds: 12),
      (_) => unawaited(heartbeat()),
    );
    return current!;
  }

  NativePlayback _playback(Map<String, dynamic> p, {bool live = false}) {
    final raw = '${p['url'] ?? ''}';
    final url = Uri.tryParse(raw.startsWith('/') ? '$bechiOrigin$raw' : raw);
    if (url == null ||
        !acceptsMediaUri(url) ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        url.host == 'abyssplayer.com' ||
        url.host == 'superflixapi.boats' ||
        p['mode'] == 'iframe') {
      throw const ApiFailure(
        'NATIVE_SOURCE',
        'O servidor não forneceu uma mídia compatível com o player nativo.',
      );
    }
    return NativePlayback(
      url: url.toString(),
      headers: api.mediaHeaders(url),
      name: '${p['title_name'] ?? p['name'] ?? source.example}',
      sourceType: source.sourceType,
      position: Duration(
        milliseconds: (p['position_ms'] as num?)?.toInt() ?? 0,
      ),
      metadata: p,
      variants: jsonRows(p['variants']),
      isLive: live,
    );
  }

  Future<void> _prepareSuperflix(Uri media) async {
    final parts = media.path.split('/');
    _superflixPath =
        'superflix/connection/${parts[parts.length - 2]}?${media.query}';
    _superflixSession = _uuid();
    String? previousStatus;
    var retries = 0;
    var verificationPending = false;
    for (;;) {
      if (_timedOut && verificationPending) {
        scope.check();
        throw const ApiFailure(
          'VERIFICATION_FAILED',
          'A verificação da SuperFlix no servidor não terminou a tempo.',
        );
      }
      _checkDeadline();
      Map<String, dynamic> state;
      try {
        state = jsonMap(
          await _request(
            _superflixPath!,
            method: 'POST',
            body: {
              'session_id': _superflixSession,
              'release': false,
              'continueNext': false,
            },
          ),
        );
        retries = 0;
      } on ApiFailure catch (error) {
        _checkDeadline();
        if (![500, 502, 503, 504].contains(error.status)) rethrow;
        if (++retries > 2) {
          throw ApiFailure(
            error.code,
            'O servidor do Bechi falhou ao consultar a abertura da SuperFlix.',
            status: error.status,
          );
        }
        previousStatus = null;
        onStatus('O servidor do Bechi não respondeu. Repetindo a consulta…');
        await scope.delay(pollInterval);
        continue;
      }
      if (state['ready'] == true) break;
      if (state['needsAction'] == true ||
          jsonMap(state['mobile'])['needs_action'] == true) {
        throw const ApiFailure(
          'VERIFICATION',
          'A SuperFlix pediu confirmação para esta sessão de reprodução.',
        );
      }
      if ([
        'offline',
        'source_error',
        'disconnected',
      ].contains(state['state'])) {
        throw const ApiFailure(
          'SUPERFLIX_SERVER',
          'O servidor do Bechi não conseguiu abrir o vídeo da SuperFlix.',
        );
      }
      // A verification load failure can recover within the same session.
      // The server explicitly flags when the user needs to act.
      verificationPending =
          state['verificationFailed'] == true ||
          state['state'] == 'verification_required';
      final message = verificationPending
          ? 'Aguardando a verificação da SuperFlix no servidor do Bechi…'
          : switch (state['state']) {
              'busy' => 'Aguardando o servidor do Bechi ficar disponível…',
              'loading' =>
                'O servidor do Bechi está carregando a página da SuperFlix…',
              _ => 'Preparando a conexão com a SuperFlix no servidor do Bechi…',
            };
      if (message != previousStatus) {
        onStatus(message);
        previousStatus = message;
      }
      await scope.delay(pollInterval);
    }
  }

  Future<NativePlayback> _openTorrent() async {
    onStatus('Conectando à fonte 1080p…');
    final resume = title['completed'] == true
        ? 0
        : position.inMilliseconds > 0
        ? position.inMilliseconds
        : (title['position_ms'] as num?)?.toInt() ?? 0;
    final total = duration.inMilliseconds > 0
        ? duration.inMilliseconds
        : (title['duration_ms'] as num?)?.toInt() ?? 0;
    final option = selectMagnetOption(jsonRows(title['source_options']));
    if (option == null) {
      throw const ApiFailure(
        'SOURCE',
        'Não há uma opção online autorizada neste título.',
      );
    }
    final created = jsonMap(
      await _request(
        'titles/${source.slug}/torrent-session',
        method: 'POST',
        body: {
          'source_option_id': option['id'],
          'position_ms': resume,
          'duration_ms': total,
        },
      ),
    );
    _torrent = '${created['id']}';
    var selected = false;
    for (;;) {
      _checkDeadline();
      final state = jsonMap(await _request('torrent/sessions/$_torrent'));
      final files = jsonRows(state['files']);
      files.sort(
        (a, b) =>
            ((b['bytes'] as num?) ?? 0).compareTo((a['bytes'] as num?) ?? 0),
      );
      if (!selected && files.isNotEmpty && state['fileIndex'] == null) {
        await _request(
          'torrent/sessions/$_torrent/selection',
          method: 'POST',
          body: {
            'fileIndex': files.first['index'],
            'position_ms': resume,
            'duration_ms': total,
          },
        );
        selected = true;
      }
      onStatus('Preparando o primeiro trecho · ${state['peers'] ?? 0} fontes');
      if (['FAILED', 'ERROR', 'STOPPED', 'CLOSED'].contains(state['state'])) {
        throw const ApiFailure(
          'SOURCE_TORRENT',
          'A fonte online não disponibilizou o vídeo. Tente novamente.',
        );
      }
      if (state['state'] == 'READY') {
        try {
          final playback = jsonMap(
            await _request('torrent/sessions/$_torrent/playback'),
          );
          current = _playback({...playback, 'title_name': source.example});
          _deadline?.cancel();
          _heartbeat = Timer.periodic(
            const Duration(seconds: 10),
            (_) => unawaited(heartbeat()),
          );
          return current!;
        } on ApiFailure catch (e) {
          if (!['BUFFERING', 'NO_COMPLETE_PEER'].contains(e.code)) rethrow;
        }
      }
      await scope.delay(pollInterval);
    }
  }

  Future<void> heartbeat({bool seek = false}) async {
    if (_closed || _heartbeatBusy) return;
    _heartbeatBusy = true;
    try {
      if (_torrent != null) {
        await _request(
          'torrent/sessions/$_torrent/heartbeat',
          method: 'POST',
          body: {
            'position_ms': position.inMilliseconds,
            'preparing': false,
            'seek': seek,
          },
        );
      }
      if (_cacheLease != null) {
        await _request(
          'playback/$_cacheLease/lease',
          method: 'POST',
          body: {'session_id': _leaseId, 'release': false},
        );
      }
      if (_superflixPath != null) {
        await _request(
          _superflixPath!,
          method: 'POST',
          body: {
            'session_id': _superflixSession,
            'release': false,
            'continueNext': false,
          },
        );
      }
      if (_original != null) {
        await api.mediaState(
          _original!.replace(
            queryParameters: {
              ..._original!.queryParameters,
              'lease': '1',
              'lease_id': _leaseId,
            },
          ),
          scope: scope,
        );
      }
    } on ApiFailure {
      /* A later heartbeat retries transient network loss. */
    } finally {
      _heartbeatBusy = false;
    }
  }

  Future<void> saveProgress() async {
    if (duration.inMilliseconds <= 0 ||
        position.inMilliseconds < 0 ||
        source.isLive ||
        source.asset != null) {
      return;
    }
    final target = _torrent != null
        ? 'me/title-progress/$_titleId'
        : 'me/progress/$_stream';
    try {
      await api.request(
        target,
        method: 'PUT',
        body: {
          'position_ms': position.inMilliseconds.clamp(
            0,
            duration.inMilliseconds,
          ),
          'duration_ms': duration.inMilliseconds,
          'observed_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
      );
    } on ApiFailure {
      /* Playback remains usable if history cannot be saved. */
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    _deadline?.cancel();
    scope.cancel();
    await Future.wait([
      saveProgress(),
      _releaseOwned(),
      if (_hosted != null) _hosted!.close(),
    ]);
    _hosted = null;
  }

  void _checkDeadline() {
    scope.check();
    if (_timedOut) {
      throw const ApiFailure(
        'PREPARATION_TIMEOUT',
        'A fonte demorou a preparar o vídeo. Tente novamente.',
      );
    }
  }

  Future<void> _releaseSuperflix() async {
    final path = _superflixPath;
    final id = _superflixSession;
    if (path == null || id == null) return;
    _superflixPath = _superflixSession = null;
    try {
      await api.request(
        path,
        method: 'POST',
        body: {'session_id': id, 'release': true, 'continueNext': false},
      );
    } on ApiFailure {
      // The server expires a lease if the device is disconnected.
    }
  }

  Future<void> _releaseOwned() async {
    try {
      if (_torrent != null) {
        await api.request('torrent/sessions/$_torrent', method: 'DELETE');
      }
      if (_superflixPath != null) await _releaseSuperflix();
      if (_cacheLease != null) {
        await api.request(
          'playback/$_cacheLease/lease',
          method: 'POST',
          body: {'session_id': _leaseId, 'release': true},
        );
      }
      if (_original != null) {
        await api.mediaState(
          _original!.replace(
            queryParameters: {
              ..._original!.queryParameters,
              'lease': '0',
              'lease_id': _leaseId,
            },
          ),
        );
      }
    } on ApiFailure {
      /* The server also expires abandoned leases. */
    }
    _torrent = _cacheLease = null;
    _original = null;
  }

  Future<Uri> prepareQuality(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !acceptsMediaUri(uri) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const ApiFailure('NATIVE_SOURCE', 'Qualidade inválida.');
    }
    if (_original != null) {
      await api.mediaState(
        _original!.replace(
          queryParameters: {
            ..._original!.queryParameters,
            'lease': '0',
            'lease_id': _leaseId,
          },
        ),
      );
      _original = null;
    }
    if (uri.origin == bechiOrigin && uri.path.endsWith('/original.mkv')) {
      final deadline = DateTime.now().add(preparationTimeout);
      for (;;) {
        scope.check();
        if (DateTime.now().isAfter(deadline)) {
          throw const ApiFailure(
            'PREPARATION_TIMEOUT',
            'O arquivo original demorou a preparar.',
          );
        }
        final result = await api.mediaState(
          uri.replace(
            queryParameters: {
              ...uri.queryParameters,
              'status': '1',
              'position_ms': '${position.inMilliseconds}',
            },
          ),
          scope: scope,
        );
        if (result['ready'] == true) break;
        onStatus('Preparando a qualidade original…');
        await scope.delay(pollInterval);
      }
      _original = uri;
      await heartbeat();
    }
    return uri;
  }

  bool acceptsMediaUri(Uri uri) =>
      uri.scheme == 'https' || _hosted?.owns(uri) == true;
  String? nextStreamId(String streamId) {
    final available = seasons
        .expand((s) => jsonRows(s['episodes']))
        .map((e) => selectSource(source, jsonRows(e['streams'])))
        .whereType<Map<String, dynamic>>()
        .toList();
    final index = available.indexWhere((s) => s['id'] == streamId);
    return index >= 0 && index + 1 < available.length
        ? '${available[index + 1]['id']}'
        : null;
  }

  static String _uuid() {
    final random = Random.secure(),
        b = List<int>.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }
}
