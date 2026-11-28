import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'source_case.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.code, this.message, {this.status = 0});
  final String code, message;
  final int status;
  @override
  String toString() => message;
}

class CancelScope {
  bool cancelled = false;
  final Set<void Function()> _listeners = {};
  void check() {
    if (cancelled) throw const ApiFailure('CANCELLED', 'Reprodução encerrada.');
  }

  void Function() listen(void Function() callback) {
    if (cancelled) {
      callback();
      return () {};
    }
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    for (final callback in _listeners.toList()) {
      callback();
    }
    _listeners.clear();
  }

  Future<void> delay([Duration duration = const Duration(seconds: 2)]) async {
    check();
    final done = Completer<void>();
    final timer = Timer(duration, () => done.complete());
    final remove = listen(() {
      timer.cancel();
      if (!done.isCompleted) done.complete();
    });
    try {
      await done.future;
      check();
    } finally {
      remove();
      timer.cancel();
    }
  }
}

abstract class SessionStore {
  Future<String?> read();
  Future<void> write(String? cookie);
}

class NativeSessionStore implements SessionStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'bechi_native_session';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String? cookie) => cookie == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: cookie);
}

typedef ApiTransport =
    Future<Map<String, dynamic>> Function(
      String method,
      String path,
      Map<String, dynamic>? body,
      CancelScope? scope,
    );

class BechiApi {
  Map<String, dynamic> preferences = {};
  Future<Map<String, dynamic>> readPreferences() async =>
      preferences = jsonMap(await request('me/preferences'));
  BechiApi({SessionStore? store, this.transport})
    : store = store ?? NativeSessionStore();
  final SessionStore store;
  final ApiTransport? transport;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  String? _cookie;
  bool get authenticated => _cookie != null;
  Future<bool> restore() async {
    _cookie = await store.read();
    if (_cookie != null &&
        !RegExp(r'^[A-Za-z0-9_-]{40,100}$').hasMatch(_cookie!)) {
      await logout();
    }
    if (_cookie == null) return false;
    try {
      await request('me/preferences');
      return true;
    } on ApiFailure catch (e) {
      if (e.status == 401) {
        await logout();
        return false;
      }
      rethrow;
    }
  }

  Future<void> login(String email, String password) async {
    await request(
      'devices/register',
      method: 'POST',
      body: {
        'device_type': 'web',
        'access': {'email': email.trim(), 'password': password},
      },
    );
    if (_cookie == null) {
      throw const ApiFailure(
        'SESSION',
        'O servidor não criou a sessão do app.',
      );
    }
    await store.write(_cookie);
  }

  Future<void> logout() async {
    _cookie = null;
    await store.write(null);
  }

  Future<Map<String, dynamic>> envelope(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    CancelScope? scope,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    scope?.check();
    if (path.startsWith('/') || path.contains('://') || path.contains('..')) {
      throw const ApiFailure('PATH', 'Requisição inválida.');
    }
    if (transport != null) return transport!(method, path, body, scope);
    HttpClientRequest? active;
    void Function()? unbind;
    try {
      final request = await _http.openUrl(
        method,
        Uri.parse('$bechiOrigin/api/v1/$path'),
      );
      active = request;
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('Origin', bechiOrigin);
      if (_cookie != null) request.cookies.add(Cookie('cine_device', _cookie!));
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      unbind = scope?.listen(() => request.abort());
      scope?.check();
      final response = await request.close().timeout(timeout);
      for (final cookie in response.cookies) {
        if (cookie.name == 'cine_device' &&
            RegExp(r'^[A-Za-z0-9_-]{40,100}$').hasMatch(cookie.value)) {
          _cookie = cookie.value;
        }
      }
      if (method == 'HEAD') {
        await response.timeout(timeout).drain<void>();
        scope?.check();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw ApiFailure(
            'SOURCE_HEAD',
            'A origem não liberou o vídeo. Tente novamente.',
            status: response.statusCode,
          );
        }
        return {
          'data': {'ready': true},
        };
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > 16 * 1024 * 1024) {
          throw const ApiFailure('SIZE', 'A resposta excedeu o limite do app.');
        }
      }
      scope?.check();
      if (response.statusCode == 204) {
        return {
          'data': {'ok': true},
        };
      }
      final value = jsonMap(jsonDecode(utf8.decode(bytes)));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = jsonMap(value['error']);
        throw ApiFailure(
          '${error['code'] ?? 'HTTP'}',
          '${error['message'] ?? 'O servidor não respondeu.'}',
          status: response.statusCode,
        );
      }
      return value;
    } on TimeoutException {
      active?.abort();
      throw const ApiFailure(
        'TIMEOUT',
        'O servidor demorou a responder. Tente novamente.',
      );
    } on SocketException {
      scope?.check();
      throw const ApiFailure(
        'NETWORK',
        'Não foi possível conectar ao servidor.',
      );
    } on HandshakeException {
      throw const ApiFailure(
        'NETWORK_TLS',
        'Não foi possível validar a conexão segura com o servidor.',
      );
    } on HttpException {
      scope?.check();
      throw const ApiFailure('NETWORK', 'A conexão foi interrompida.');
    } on FormatException {
      throw const ApiFailure(
        'RESPONSE',
        'O servidor enviou uma resposta inválida. Tente novamente.',
      );
    } finally {
      unbind?.call();
    }
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    CancelScope? scope,
  }) async {
    final value = await envelope(
      path,
      method: method,
      body: body,
      scope: scope,
    );
    if (!value.containsKey('data') || value['data'] == null) {
      throw const ApiFailure(
        'RESPONSE',
        'O servidor enviou uma resposta incompleta.',
      );
    }
    return value['data'];
  }

  Map<String, String> mediaHeaders(Uri url) {
    if (url.origin == bechiOrigin &&
        _cookie != null &&
        (url.path.startsWith('/api/v1/torrent/') ||
            url.path.startsWith('/api/v1/superflix/'))) {
      return {'Cookie': 'cine_device=$_cookie'};
    }
    return {};
  }

  Future<Map<String, dynamic>> mediaState(Uri uri, {CancelScope? scope}) {
    if (uri.origin != bechiOrigin || !uri.path.startsWith('/api/v1/')) {
      throw const ApiFailure('PATH', 'Endereço de preparação inválido.');
    }
    return envelope(
      '${uri.path.substring('/api/v1/'.length)}?${uri.query}',
      scope: scope,
    );
  }

  Future<void> prepareMedia(Uri uri, {CancelScope? scope}) async {
    if (uri.origin != bechiOrigin || !uri.path.startsWith('/api/v1/')) {
      throw const ApiFailure('PATH', 'Endereço de preparação inválido.');
    }
    await envelope(
      '${uri.path.substring('/api/v1/'.length)}?${uri.query}',
      method: 'HEAD',
      scope: scope,
      timeout: const Duration(seconds: 150),
    );
  }

  void dispose() => _http.close(force: true);
}
