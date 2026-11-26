import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'bechi_api.dart';
import 'source_case.dart';

typedef HostedInvoke =
    Future<Map<String, dynamic>?> Function(
      String method,
      Map<String, dynamic>? arguments,
    );

class HostedPlayback {
  HostedPlayback(this.url, this.variants, this.height);
  final Uri url;
  final List<Map<String, dynamic>> variants;
  final int height;
}

class _Resource {
  _Resource(this.url, this.playlist);
  final Uri url;
  final bool playlist;
  int? size;
}

class _Bytes {
  _Bytes(this.status, this.body, this.type, this.range);
  final int status;
  final Uint8List body;
  final String type;
  final String? range;
}

/// Only the source session lives in WebKit. The loopback relay transfers its
/// normally authorized media buffers to libmpv; it never renders a site player.
class HostedSource {
  HostedSource({
    HostedInvoke? invoke,
    Future<bool> Function(Uri)? publicAddress,
    this.onStatus,
  }) : _invoke = invoke ?? _platform,
       _publicAddress = publicAddress ?? _resolvePublic;
  static const _channel = MethodChannel('app.bechiflix.native/hosted');
  static bool _callbacks = false;
  static final _listeners = <String, void Function(String)>{};
  final void Function(String)? onStatus;
  final HostedInvoke _invoke;
  final Future<bool> Function(Uri) _publicAddress;
  HttpServer? _server;
  String _nonce = '', _frame = '', _epoch = '';
  final _resources = <String, _Resource>{}, _ids = <String, String>{};
  final _cache = <String, _Bytes>{}, _pending = <String, Future<_Bytes>>{};
  int _cacheBytes = 0;
  final _verifiedHosts = <String, DateTime>{};
  bool _closed = false;

  static Future<Map<String, dynamic>?> _platform(
    String method,
    Map<String, dynamic>? arguments,
  ) async {
    try {
      return jsonMap(await _channel.invokeMethod<dynamic>(method, arguments));
    } on PlatformException catch (e) {
      throw ApiFailure(e.code, switch (e.code) {
        'SOURCE_DNS' => 'A rede não conseguiu localizar o endereço da fonte.',
        'SOURCE_CONNECTION' => 'Não foi possível conectar à fonte de vídeo.',
        'SOURCE_TLS' => 'A conexão segura com a fonte falhou.',
        'SOURCE_ACCESS' => 'A fonte recusou o acesso ao episódio.',
        'SOURCE_NOT_FOUND' => 'O episódio não está disponível nesta fonte.',
        'SOURCE_UNAVAILABLE' =>
          'A fonte está indisponível. Tente novamente em instantes.',
        'SOURCE_TIMEOUT' => 'A fonte demorou a responder. Tente novamente.',
        _ => 'A fonte não concluiu a preparação. Tente novamente.',
      });
    }
  }

  static String _random(int count) {
    final r = Random.secure();
    return List.generate(
      count,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String _uuid() {
    final s = _random(16);
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-4${s.substring(13, 16)}-8${s.substring(17, 20)}-${s.substring(20)}';
  }

  static Uri mediaUrl(String raw) {
    final u = Uri.tryParse(raw), host = u?.host.toLowerCase() ?? '';
    if (u == null ||
        u.scheme != 'https' ||
        u.userInfo.isNotEmpty ||
        u.hasFragment ||
        u.hasPort ||
        !host.contains('.') ||
        InternetAddress.tryParse(host) != null ||
        host.endsWith('.local') ||
        host.endsWith('.localhost') ||
        host.endsWith('.internal') ||
        host.endsWith('.home')) {
      throw const ApiFailure(
        'SOURCE_URL',
        'A origem retornou um endereço inválido.',
      );
    }
    return u;
  }

  static Future<bool> _resolvePublic(Uri url) async {
    final addresses = await InternetAddress.lookup(url.host);
    bool valid(InternetAddress a) {
      if (a.isLoopback || a.isLinkLocal || a.isMulticast) return false;
      final b = a.rawAddress;
      if (b.length == 4) {
        return b[0] != 0 &&
            b[0] != 10 &&
            b[0] != 127 &&
            b[0] < 224 &&
            !(b[0] == 169 && b[1] == 254) &&
            !(b[0] == 172 && b[1] >= 16 && b[1] <= 31) &&
            !(b[0] == 192 && b[1] == 168) &&
            !(b[0] == 100 && b[1] >= 64 && b[1] <= 127) &&
            !(b[0] == 198 && [18, 19].contains(b[1]));
      }
      return b.any((n) => n != 0) &&
          (b[0] & 0xfe) != 0xfc &&
          !(b.take(10).every((n) => n == 0) && b[10] == 255 && b[11] == 255);
    }

    return addresses.isNotEmpty && addresses.every(valid);
  }

  String _register(Uri url, bool playlist) {
    mediaUrl(url.toString());
    final key = '${playlist ? 'p' : 'b'}:$url';
    if (_ids.containsKey(key)) return _ids[key]!;
    if (_resources.length >= 10000) {
      throw const ApiFailure(
        'SOURCE_SIZE',
        'A lista de vídeo excedeu o limite.',
      );
    }
    final id = _random(12) + (playlist ? '.m3u8' : '.bin');
    _ids[key] = id;
    _resources[id] = _Resource(url, playlist);
    return id;
  }

  Uri _local(String id) =>
      Uri.parse('http://127.0.0.1:${_server!.port}/$_nonce/$id');
  bool owns(Uri uri) =>
      _server != null &&
      uri.scheme == 'http' &&
      uri.host == '127.0.0.1' &&
      uri.port == _server!.port &&
      uri.pathSegments.length == 2 &&
      uri.pathSegments.first == _nonce &&
      _resources.containsKey(uri.pathSegments.last) &&
      !uri.hasQuery &&
      !uri.hasFragment;

  Future<HostedPlayback> prepare({
    required String url,
    required String kind,
    required String title,
    required int season,
    required int episode,
  }) async {
    await _server?.close(force: true);
    _server = null;
    _closed = false;
    _listeners.remove(_epoch);
    _epoch = _uuid();
    if (!_callbacks) {
      _callbacks = true;
      _channel.setMethodCallHandler((call) async {
        final args = jsonMap(call.arguments);
        if (call.method == 'phase') {
          _listeners[args['epoch']]?.call(
            args['phase'] == 'human'
                ? 'Confirmação humana necessária na fonte.'
                : 'Preparando o episódio…',
          );
        } else if (call.method == 'diagnostic' && kDebugMode) {
          debugPrint('NATIVE_HOSTED_DIAGNOSTIC ${jsonEncode(args)}');
        }
      });
    }
    if (onStatus != null) _listeners[_epoch] = onStatus!;
    _resources.clear();
    _ids.clear();
    _cache.clear();
    _pending.clear();
    _cacheBytes = 0;
    final script = await rootBundle.loadString('assets/hosted_source.js');
    final result = await _invoke('prepare', {
      'script': script,
      if (Platform.isAndroid)
        'bridge': await rootBundle.loadString(
          'assets/android_hosted_bridge.js',
        ),
      'url': url,
      'kind': kind,
      'expectedTitle': title,
      'season': season,
      'episode': episode,
      'epoch': _epoch,
    });
    if (_closed) throw const ApiFailure('CANCELLED', 'Reprodução encerrada.');
    return attach(result ?? {});
  }

  /// A separate attachment entry makes the transport testable with owned media.
  Future<HostedPlayback> attach(Map<String, dynamic> result) async {
    if (result['frame'] is! String ||
        !['hls', 'mp4'].contains(result['format'])) {
      throw const ApiFailure(
        'SOURCE_MEDIA',
        'A fonte não disponibilizou o vídeo.',
      );
    }
    _frame = result['frame'] as String;
    _nonce = _random(24);
    if (_epoch.isEmpty) _epoch = _uuid();
    final playlist = result['format'] == 'hls',
        rows = jsonRows(result['variants']);
    if (rows.isEmpty || rows.length > 12) {
      throw const ApiFailure(
        'SOURCE_MEDIA',
        'A fonte não disponibilizou o vídeo.',
      );
    }
    final variants = <Map<String, dynamic>>[];
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.idleTimeout = const Duration(seconds: 60);
    _server!.listen((request) => unawaited(_handle(request)));
    for (final row in rows) {
      final uri = mediaUrl('${row['url']}');
      await _checkAddress(uri);
      final id = _register(uri, playlist);
      if (!playlist) {
        final sample = await _read(id, 'bytes=0-4095');
        final total = int.tryParse(sample.range?.split('/').last ?? '');
        if (sample.status != 206 || total == null || total < 4096) {
          throw const ApiFailure(
            'SOURCE_RANGE',
            'A fonte não entregou o arquivo.',
          );
        }
        _resources[id]!.size = total;
      }
      variants.add({...row, 'url': _local(id).toString()});
    }
    variants.sort(
      (a, b) =>
          ((b['height'] as num?) ?? 0).compareTo((a['height'] as num?) ?? 0),
    );
    return HostedPlayback(
      Uri.parse(variants.first['url'] as String),
      variants,
      (variants.first['height'] as num?)?.toInt() ?? 0,
    );
  }

  String rewritePlaylist(String text, Uri base) {
    if (utf8.encode(text).length > 1048576 ||
        text.trimLeft().split('\n').first.trim() != '#EXTM3U') {
      throw const ApiFailure(
        'SOURCE_PLAYLIST',
        'A fonte não retornou uma lista de vídeo válida.',
      );
    }
    var child = false;
    return text
        .split(RegExp(r'\r?\n'))
        .map((line) {
          if (line.startsWith('#EXT-X-KEY:') &&
              (!RegExp(r'METHOD=(NONE|AES-128)(,|$)').hasMatch(line) ||
                  line.contains('KEYFORMAT=') &&
                      !line.contains('KEYFORMAT="identity"'))) {
            throw const ApiFailure(
              'SOURCE_DRM',
              'Esta origem exige um sistema de proteção não disponível neste protótipo.',
            );
          }
          if (line.startsWith('#')) {
            if (line.startsWith('#EXT-X-STREAM-INF:')) child = true;
            final list =
                line.startsWith('#EXT-X-MEDIA:') ||
                line.startsWith('#EXT-X-I-FRAME-STREAM-INF:');
            return line.replaceAllMapped(
              RegExp(r'URI="([^"]+)"'),
              (m) =>
                  'URI="${_local(_register(base.resolve(m[1]!), list || base.resolve(m[1]!).path.endsWith('.m3u8')))}"',
            );
          }
          if (line.trim().isEmpty) return line;
          final u = base.resolve(line.trim()),
              id = _register(u, child || u.path.endsWith('.m3u8'));
          child = false;
          return _local(id).toString();
        })
        .join('\n');
  }

  Future<_Bytes> _read(String id, String? range) async {
    if (_closed) {
      throw const ApiFailure('SOURCE_CLOSED', 'Reprodução encerrada.');
    }
    final cacheKey = '$id:${range ?? ''}', cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }
    if (_pending.containsKey(cacheKey)) return _pending[cacheKey]!;
    if (_pending.length >= 4) {
      throw const ApiFailure('SOURCE_BUSY', 'Aguarde o carregamento.');
    }
    final epoch = _epoch, item = _resources[id]!;
    final work = () async {
      await _checkAddress(item.url);
      final value = await _invoke('read', {
        'epoch': epoch,
        'frame': _frame,
        'url': item.url.toString(),
        'range': ?range,
      });
      if (_closed || epoch != _epoch) {
        throw const ApiFailure('SOURCE_CLOSED', 'Reprodução encerrada.');
      }
      final raw = value?['data'];
      if (value == null ||
          ![200, 206, 416].contains(value['status']) ||
          range != null && ![206, 416].contains(value['status']) ||
          raw is! Uint8List && raw is! String ||
          raw is String && raw.length > 23000000) {
        throw const ApiFailure(
          'SOURCE_READ',
          'A origem não entregou o trecho de vídeo.',
        );
      }
      final bytes = raw is Uint8List ? raw : base64Decode(raw as String);
      if (bytes.length > 16777216) {
        throw const ApiFailure('SOURCE_SIZE', 'O trecho excedeu o limite.');
      }
      var data = bytes, type = '${value['type'] ?? 'application/octet-stream'}';
      if (item.playlist) {
        data = Uint8List.fromList(
          utf8.encode(rewritePlaylist(utf8.decode(bytes), item.url)),
        );
        type = 'application/vnd.apple.mpegurl';
      } else if (RegExp(
            r'^(text/html|application/(json|xml|xhtml))',
          ).hasMatch(type) ||
          utf8
              .decode(bytes.take(64).toList(), allowMalformed: true)
              .trimLeft()
              .startsWith('<')) {
        throw const ApiFailure(
          'SOURCE_READ',
          'A origem retornou uma página em vez de vídeo.',
        );
      } else if (bytes.length >= 377 &&
          bytes[0] == 0x47 &&
          bytes[188] == 0x47 &&
          bytes[376] == 0x47) {
        type = 'video/mp2t';
      }
      final result = _Bytes(
        (value['status'] as num).toInt(),
        data,
        type,
        value['range'] as String?,
      );
      while (_cacheBytes + data.length > 24 * 1024 * 1024 &&
          _cache.isNotEmpty) {
        _cacheBytes -= _cache.remove(_cache.keys.first)!.body.length;
      }
      if (data.length <= 8 * 1024 * 1024) {
        _cache[cacheKey] = result;
        _cacheBytes += data.length;
      }
      return result;
    }();
    _pending[cacheKey] = work;
    try {
      return await work;
    } finally {
      _pending.remove(cacheKey);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response, epoch = _epoch;
    try {
      if (request.headers.value('origin') != null ||
          !owns(request.requestedUri) ||
          !['GET', 'HEAD'].contains(request.method)) {
        response.statusCode = 403;
        await response.close();
        return;
      }
      final id = request.uri.pathSegments.last, item = _resources[id]!;
      response.headers.set('Cache-Control', 'private, no-store');
      response.headers.set('X-Content-Type-Options', 'nosniff');
      if (item.size != null) {
        final total = item.size!,
            range = request.headers.value('range'),
            m = range == null
                ? null
                : RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        final suffix = m != null && m[1]!.isEmpty;
        final start = m == null
            ? 0
            : suffix
            ? max(0, total - (int.tryParse(m[2]!) ?? 0))
            : int.tryParse(m[1]!) ?? -1;
        final end = m == null || suffix || m[2]!.isEmpty
            ? total - 1
            : min(total - 1, int.tryParse(m[2]!) ?? -1);
        if (range != null && m == null ||
            start < 0 ||
            start >= total ||
            end < start) {
          response.statusCode = 416;
          response.headers.set('Content-Range', 'bytes */$total');
          await response.close();
          return;
        }
        response.statusCode = range == null ? 200 : 206;
        response.headers.contentType = ContentType('video', 'mp4');
        response.contentLength = end - start + 1;
        response.headers.set('Accept-Ranges', 'bytes');
        if (range != null) {
          response.headers.set('Content-Range', 'bytes $start-$end/$total');
        }
        if (request.method == 'HEAD') {
          await response.close();
          return;
        }
        for (var position = start; position <= end;) {
          if (_closed || epoch != _epoch) break;
          final last = min(end, position + 2097151),
              part = await _read(id, 'bytes=$position-$last');
          if (part.range != 'bytes $position-$last/$total' ||
              part.body.length != last - position + 1) {
            throw const ApiFailure(
              'SOURCE_RANGE',
              'A origem perdeu a posição do vídeo.',
            );
          }
          response.add(part.body);
          await response.flush();
          position = last + 1;
        }
      } else {
        final data = await _read(id, request.headers.value('range'));
        response.statusCode = data.status;
        response.headers.set('Content-Type', data.type);
        response.contentLength = data.body.length;
        if (data.range != null) {
          response.headers.set('Content-Range', data.range!);
        }
        if (request.method != 'HEAD') response.add(data.body);
      }
      await response.close();
    } catch (_) {
      try {
        response.statusCode = 502;
        response.write('A fonte não entregou o vídeo.');
        await response.close();
      } catch (_) {
        response
            .detachSocket()
            .then((socket) => socket.destroy())
            .catchError((_) {});
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    final closingEpoch = _epoch;
    _listeners.remove(closingEpoch);
    _epoch = _uuid();
    await _server?.close(force: true);
    _server = null;
    _resources.clear();
    _ids.clear();
    _pending.clear();
    _cache.clear();
    _cacheBytes = 0;
    _verifiedHosts.clear();
    try {
      await _invoke('close', {'epoch': closingEpoch});
    } on PlatformException {
      /* A process shutdown also closes the private session. */
    }
  }

  Future<void> _checkAddress(Uri uri) async {
    if (_verifiedHosts[uri.host]?.isAfter(DateTime.now()) == true) return;
    if (!await _publicAddress(uri)) {
      throw const ApiFailure('SOURCE_ADDRESS', 'Endereço de mídia inválido.');
    }
    if (_verifiedHosts.length >= 64) _verifiedHosts.clear();
    _verifiedHosts[uri.host] = DateTime.now().add(const Duration(minutes: 1));
  }
}
