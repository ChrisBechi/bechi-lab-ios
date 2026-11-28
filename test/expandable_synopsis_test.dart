import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bechi_player_prototype/expandable_synopsis.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('Expande e recolhe apenas descrições cortadas em $platform', (
      tester,
    ) async {
      Future<void> render(String text) => tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: ListView(children: [ExpandableSynopsis(text)]),
              ),
            ),
          ),
        ),
      );
      await render('Descrição breve.');
      expect(find.text('Ver mais…'), findsNothing);
      final long = List.filled(20, 'Um episódio em Lisboa.').join(' ');
      await render(long);
      expect(tester.widget<Text>(find.text(long)).maxLines, 4);
      await tester.tap(find.text('Ver mais…'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(long)).maxLines, isNull);
      await tester.ensureVisible(find.text('Ver menos…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver menos…'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(long)).maxLines, 4);
    });
  }
}
