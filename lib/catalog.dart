import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'bechi_api.dart';
import 'player_view.dart';
import 'source_case.dart';
part 'title_details.dart';
part 'live_guide.dart';

typedef Item = Map<String, dynamic>;
bool apple(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;
Future<T?> showPage<T>(BuildContext context, Widget page) => Navigator.push<T>(
  context,
  apple(context)
      ? CupertinoPageRoute<T>(builder: (_) => page)
      : MaterialPageRoute<T>(builder: (_) => page),
);

class AdaptivePage extends StatelessWidget {
  const AdaptivePage({
    super.key,
    required this.title,
    required this.body,
    this.action,
    this.bottom,
  });
  final Widget title, body;
  final Widget? action, bottom;
  @override
  Widget build(BuildContext context) {
    if (apple(context)) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: title, trailing: action),
        child: SafeArea(
          bottom: bottom == null,
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                Expanded(child: body),
                ?bottom,
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: title, actions: [?action]),
      body: SafeArea(top: false, child: body),
      bottomNavigationBar: bottom,
    );
  }
}

Widget actionButton(BuildContext context, String label, VoidCallback? action) =>
    apple(context)
    ? CupertinoButton.filled(onPressed: action, child: Text(label))
    : FilledButton(onPressed: action, child: Text(label));

class Art extends StatelessWidget {
  const Art(this.path, {super.key});
  final dynamic path;
  @override
  Widget build(BuildContext context) {
    const missing = ColoredBox(
      color: Color(0xff192635),
      child: Center(child: Icon(Icons.movie_outlined, color: Colors.white38)),
    );
    final uri = path is String && path.isNotEmpty
        ? Uri.tryParse(bechiOrigin)?.resolve(path)
        : null;
    if (uri == null || !['https', 'http'].contains(uri.scheme)) return missing;
    return Image.network(
      uri.toString(),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => missing,
    );
  }
}

class CatalogHome extends StatefulWidget {
  const CatalogHome({super.key, required this.api, required this.onLogout});
  final BechiApi api;
  final Future<void> Function() onLogout;
  @override
  State<CatalogHome> createState() => _CatalogHomeState();
}

class _CatalogHomeState extends State<CatalogHome> {
  int tab = 0;
  final visited = <int>{0};
  final views = List.generate(5, (_) => GlobalKey<_FeedState>());
  static const names = ['Início', 'Filmes', 'Séries', 'Ao vivo', 'Minha lista'];
  static const icons = [
    Icons.home_outlined,
    Icons.movie_outlined,
    Icons.tv,
    Icons.live_tv,
    Icons.bookmark_outline,
  ];
  void select(int index) {
    setState(() {
      tab = index;
      visited.add(index);
    });
  }

  void refreshPersonal() {
    views[0].currentState?.reload();
    views[4].currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    const appleIcons = [
      CupertinoIcons.house,
      CupertinoIcons.film,
      CupertinoIcons.tv,
      CupertinoIcons.antenna_radiowaves_left_right,
      CupertinoIcons.bookmark,
    ];
    final items = List.generate(
      names.length,
      (i) => BottomNavigationBarItem(
        icon: Icon(apple(context) ? appleIcons[i] : icons[i]),
        label: names[i],
      ),
    );
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final content = IndexedStack(
      index: tab,
      children: List.generate(
        5,
        (i) => visited.contains(i)
            ? Feed(
                key: views[i],
                api: widget.api,
                index: i,
                onChange: refreshPersonal,
              )
            : const SizedBox.shrink(),
      ),
    );
    final bottom = apple(context)
        ? CupertinoTabBar(items: items, currentIndex: tab, onTap: select)
        : NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: select,
            destinations: [
              for (final item in items)
                NavigationDestination(icon: item.icon, label: item.label!),
            ],
          );
    return AdaptivePage(
      title: Image.asset(
        'assets/bechi-flix.webp',
        height: 30,
        semanticLabel: 'Bechi Flix',
      ),
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search),
            onPressed: () => showPage(
              context,
              SearchPage(api: widget.api, onChange: refreshPersonal),
            ),
          ),
          if (tab == 4)
            IconButton(
              tooltip: 'Sair da conta',
              icon: const Icon(Icons.logout),
              onPressed: widget.onLogout,
            ),
        ],
      ),
      bottom: wide && !apple(context) ? null : bottom,
      body: wide && !apple(context)
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: tab,
                  onDestinationSelected: select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final item in items)
                      NavigationRailDestination(
                        icon: item.icon,
                        label: Text(item.label!),
                      ),
                  ],
                ),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.api, required this.onChange});
  final BechiApi api;
  final VoidCallback onChange;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String query = '';
  Timer? debounce;
  void change(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => query = value.trim());
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdaptivePage(
    title: const Text('Buscar'),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: apple(context)
              ? CupertinoSearchTextField(
                  placeholder: 'Filme ou série',
                  autofocus: true,
                  onChanged: change,
                )
              : TextField(
                  autofocus: true,
                  onChanged: change,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Filme ou série',
                  ),
                ),
        ),
        if (query.isNotEmpty)
          Expanded(
            child: Feed(
              key: ValueKey(query),
              api: widget.api,
              index: 5,
              query: query,
              onChange: widget.onChange,
            ),
          ),
      ],
    ),
  );
}

class Feed extends StatefulWidget {
  const Feed({
    super.key,
    required this.api,
    required this.index,
    required this.onChange,
    this.query = '',
  });
  final BechiApi api;
  final int index;
  final String query;
  final VoidCallback onChange;
  @override
  State<Feed> createState() => _FeedState();
}

class _FeedState extends State<Feed> {
  late Future<dynamic> result;
  final extra = <Item>[];
  String? cursor;
  bool paging = false;
  String? pageError;
  int generation = 0;
  String get path => [
    'home',
    'titles?kind=movie&limit=42',
    'titles?kind=series&limit=42',
    'live/catalog',
    'me/watchlist',
    'search?q=${Uri.encodeQueryComponent(widget.query)}&limit=42',
  ][widget.index];
  @override
  void initState() {
    super.initState();
    result = load();
  }

  Future<dynamic> load() async {
    final current = ++generation;
    if (widget.index == 0) {
      final responses = await Future.wait([
        widget.api.request(path),
        widget.api.request('me/library').catchError((_) => <String, dynamic>{}),
      ]);
      final home = jsonMap(responses.first);
      final continuing = jsonRows(jsonMap(responses.last)['continue_watching']);
      return {
        ...home,
        'rails': [
          if (continuing.isNotEmpty)
            {'name': 'Continuar assistindo', 'items': continuing},
          ...jsonRows(home['rails']),
        ],
      };
    }
    final data = await widget.api.request(path);
    if (current == generation) cursor = jsonMap(data)['next_cursor'] as String?;
    return data;
  }

  void reload() {
    setState(() {
      extra.clear();
      cursor = null;
      paging = false;
      pageError = null;
      result = load();
    });
  }

  Future<void> more() async {
    if (paging || cursor == null) return;
    final current = generation;
    setState(() {
      paging = true;
      pageError = null;
    });
    try {
      final data = jsonMap(
        await widget.api.request(
          '$path&cursor=${Uri.encodeQueryComponent(cursor!)}',
        ),
      );
      if (mounted && current == generation) {
        setState(() {
          extra.addAll(jsonRows(data['items']));
          cursor = data['next_cursor'] as String?;
        });
      }
    } catch (_) {
      if (mounted && current == generation) {
        setState(() => pageError = 'Falha ao carregar a próxima página.');
      }
    } finally {
      if (mounted && current == generation) setState(() => paging = false);
    }
  }

  Future<void> open(Item t) async {
    if (t['slug'] == null) return;
    await showPage(context, TitleDetails(api: widget.api, summary: t));
    if (mounted) widget.onChange();
  }

  Widget poster(Item t) => Semantics(
    button: true,
    label: t['name'],
    child: GestureDetector(
      onTap: () => open(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox.expand(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Art(t['poster'] ?? t['rail_cover']),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(t['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: result,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator.adaptive());
      }
      if (snap.hasError) {
        return Center(child: actionButton(context, 'Tentar novamente', reload));
      }
      final data = jsonMap(snap.data);
      final spacing = MediaQuery.sizeOf(context).width >= 700 ? 24.0 : 16.0;
      if (widget.index == 0) {
        final hero = jsonRows(data['hero']).firstOrNull;
        final rails = jsonRows(data['rails']);
        return ListView.builder(
          itemCount: rails.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return hero == null
                  ? const SizedBox.shrink()
                  : GestureDetector(
                      onTap: () => open(hero),
                      child: AspectRatio(
                        aspectRatio: 1.85,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Art(
                              hero['backdrop'] ??
                                  hero['landscape_cover'] ??
                                  hero['poster'],
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black87],
                                ),
                              ),
                            ),
                            Positioned(
                              left: spacing,
                              right: spacing,
                              bottom: 16,
                              child: Text(
                                hero['name'],
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
            }
            final rail = rails[i - 1];
            final rows = jsonRows(rail['items']);
            if (rows.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(spacing, 20, spacing, 10),
                  child: Text(
                    rail['name'],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SizedBox(
                  height: 178,
                  child: ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: spacing),
                    scrollDirection: Axis.horizontal,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) =>
                        SizedBox(width: 105, child: poster(rows[i])),
                  ),
                ),
              ],
            );
          },
        );
      }
      if (widget.index == 3) return LiveGuide(api: widget.api, data: data);
      final items = [
        ...jsonRows(widget.index == 4 ? snap.data : data['items']),
        ...extra,
      ];
      if (items.isEmpty) {
        return Center(
          child: Text(
            widget.index == 4
                ? 'Sua lista está vazia.'
                : 'Nenhum título encontrado.',
          ),
        );
      }
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.all(spacing),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 155,
                childAspectRatio: 0.60,
                crossAxisSpacing: 10,
                mainAxisSpacing: 14,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => poster(items[i]),
            ),
          ),
          if (cursor != null)
            SliverToBoxAdapter(
              child: Center(
                child: actionButton(
                  context,
                  pageError ?? (paging ? 'Carregando…' : 'Carregar mais'),
                  paging ? null : more,
                ),
              ),
            ),
        ],
      );
    },
  );
}
