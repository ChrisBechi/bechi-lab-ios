import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bechi_player_prototype/bechi_api.dart';
import 'package:bechi_player_prototype/catalog.dart';

class CatalogApi extends BechiApi {
  final title = {
    'id': '123',
    'slug': 'serie',
    'name': 'Uma série',
    'kind': 'series',
  };
  bool saved = false;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    CancelScope? scope,
  }) async {
    if (path == 'home?rankings=1') {
      return {
        'hero': [title],
        'rails': [
          {
            'id': 'ranking-netflix',
            'name': 'Em alta na Netflix',
            'items': [
              {
                'id': 'ranking-test',
                'slug': '',
                'name': 'Um lançamento',
                'ranking': {'position': 1, 'available': false},
              },
            ],
          },
        ],
      };
    }
    if (path == 'me/library') return {'continue_watching': []};
    if (path == 'titles/serie') return title;
    if (path == 'titles/123/seasons') {
      return [
        {
          'season_number': 1,
          'name': 'Temporada 1',
          'episodes': [
            {
              'id': 'ep',
              'name': 'Piloto',
              'episode_number': 1,
              'streams': [
                {
                  'id': 'abc',
                  'name': 'Principal',
                  'source_type': 'google_drive',
                },
              ],
            },
          ],
        },
      ];
    }
    if (path == 'me/watchlist') return saved ? [title] : [];
    if (path == 'me/watchlist/123') {
      saved = method == 'POST';
      return {};
    }
    throw StateError(path);
  }
}

void main() {
  for (final config in [
    (TargetPlatform.iOS, const Size(390, 844)),
    (TargetPlatform.iOS, const Size(820, 1180)),
    (TargetPlatform.android, const Size(360, 740)),
    (TargetPlatform.android, const Size(800, 1200)),
  ]) {
    testWidgets('Catálogo, episódio e favoritos em $config', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = config.$2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = CatalogApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(platform: config.$1),
          home: CatalogHome(api: api, onLogout: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(
          config.$1 == TargetPlatform.iOS
              ? CupertinoTabBar
              : config.$2.width >= 700
              ? NavigationRail
              : NavigationBar,
        ),
        findsOneWidget,
      );
      expect(find.text('Em alta na Netflix'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      await tester.tap(find.text('Uma série'));
      await tester.pumpAndSettle();
      expect(find.text('Assistir T1 EP1'), findsOneWidget);
      await tester.tap(find.byTooltip('Minha lista'));
      await tester.pumpAndSettle();
      expect(api.saved, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Minha lista'));
      await tester.pumpAndSettle();
      expect(find.text('Uma série'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
