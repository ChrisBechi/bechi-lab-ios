import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bechi_player_prototype/hosted_source.dart';
import 'package:bechi_player_prototype/bechi_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a late response cannot open a player after the episode closes',
    () async {
      final started = Completer<void>();
      final reply = Completer<Map<String, dynamic>?>();
      final source = HostedSource(
        invoke: (method, args) async {
          if (method == 'close') return null;
          expect(method, 'prepare');
          started.complete();
          return reply.future;
        },
      );
      final pending = source.prepare(
        url: 'https://media.example/episode',
        kind: 'c7',
        title: 'Teste',
        season: 1,
        episode: 1,
      );
      await started.future;
      await source.close();
      reply.complete({});
      await expectLater(
        pending,
        throwsA(isA<ApiFailure>().having((e) => e.code, 'code', 'CANCELLED')),
      );
      expect(source.canShowSource, isFalse);
    },
  );
}
