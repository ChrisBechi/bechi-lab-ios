import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bechi_player_prototype/bechi_api.dart';

class BrokenConnection extends Fake implements HttpClient {
  BrokenConnection(this.error);
  final Object error;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      throw error;
  @override
  void close({bool force = false}) {}
}

void main() {
  for (final failure in <String, Object>{
    'NETWORK': const SocketException('simulated DNS connection failure'),
    'NETWORK_TLS': const HandshakeException('simulated TLS rejection'),
  }.entries) {
    test(
      'initial ${failure.key} failure is mapped before a response exists',
      () async {
        await HttpOverrides.runZoned(() async {
          final api = BechiApi();
          try {
            await expectLater(
              api.request('me/preferences'),
              throwsA(
                isA<ApiFailure>().having((e) => e.code, 'code', failure.key),
              ),
            );
          } finally {
            api.dispose();
          }
        }, createHttpClient: (_) => BrokenConnection(failure.value));
      },
    );
  }
}
