import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'bechi_api.dart';
import 'channel_preview.dart';
import 'ios_catalog_tabs.dart';
import 'web_mobile_style.dart';
import 'expandable_synopsis.dart';
import 'player_view.dart';
import 'source_case.dart';
part 'title_details.dart';
part 'live_guide.dart';
part 'catalog_highlights.dart';
part 'catalog_filters.dart';
part 'catalog_settings.dart';
part 'catalog_detail_panel.dart';

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
    this.overlayBottom = false,
  });
  final Widget title, body;
  final Widget? action, bottom;
  final bool overlayBottom;
  @override
  Widget build(BuildContext context) {
    if (apple(context)) {
      return CupertinoPageScaffold(
        backgroundColor: MobileLayout.background,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: MobileLayout.background,
          middle: title,
          trailing: action,
        ),
        child: SafeArea(
          bottom: bottom == null,
          child: Material(
            color: Colors.transparent,
            child: overlayBottom
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      body,
                      Positioned(left: 0, right: 0, bottom: 0, child: bottom!),
                    ],
                  )
                : Column(
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
  const Art(this.path, {super.key, this.alignment = Alignment.center});
  final Alignment alignment;
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
      alignment: alignment,
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
  @override
  void initState() {
    super.initState();
    widget.api.readPreferences().ignore();
  }

  bool nativeTabs = false;
  bool checkedTabs = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!checkedTabs && apple(context)) {
      checkedTabs = true;
      IosCatalogTabs.available().then((supported) {
        if (mounted && supported) setState(() => nativeTabs = true);
      });
    }
  }

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
        icon: Icon(apple(context) ? appleIcons[i] : icons[i], size: 19),
        label: names[i],
      ),
    );
    final wide = MediaQuery.sizeOf(context).width > 1000;
    final glass = apple(context) && nativeTabs;
    final inset = glass ? 74.0 + MediaQuery.viewPaddingOf(context).bottom : 0.0;
    final content = IndexedStack(
      index: tab,
      children: List.generate(
        5,
        (i) => visited.contains(i)
            ? Feed(
                key: views[i],
                api: widget.api,
                index: i,
                active: tab == i,
                bottomInset: inset,
                onChange: refreshPersonal,
              )
            : const SizedBox.shrink(),
      ),
    );
    final bottom = glass
        ? SizedBox(
            height: inset,
            child: IosCatalogTabs(
              index: tab,
              labels: names,
              onSelected: select,
            ),
          )
        : apple(context)
        ? CupertinoTabBar(items: items, currentIndex: tab, onTap: select)
        : NavigationBar(
            height: 58,
            backgroundColor: const Color(0xff101720),
            indicatorColor: const Color(0xff17374d),
            labelTextStyle: WidgetStatePropertyAll(
              TextStyle(
                fontSize: (MobileLayout(context).width * .0235).clamp(
                  9.0,
                  10.0,
                ),
                fontWeight: FontWeight.w600,
              ),
            ),
            selectedIndex: tab,
            onDestinationSelected: select,
            destinations: [
              for (final item in items)
                NavigationDestination(icon: item.icon, label: item.label!),
            ],
          );
    return AdaptivePage(
      title: const MobileBrand(),
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search, size: 19),
            onPressed: () => showPage(
              context,
              SearchPage(api: widget.api, onChange: refreshPersonal),
            ),
          ),
          IconButton(
            tooltip: 'Configurações',
            icon: Icon(
              apple(context) ? CupertinoIcons.gear : Icons.settings_outlined,
              size: 19,
            ),
            onPressed: () => showPage(
              context,
              CatalogSettings(api: widget.api, onLogout: widget.onLogout),
            ),
          ),
        ],
      ),
      bottom: wide && !apple(context) ? null : bottom,
      overlayBottom: glass,
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
  final controller = TextEditingController();
  final historyStore = const FlutterSecureStorage();
  static const historyKey = 'bechi.search.recent-titles.v1';
  final recent = <String>[];
  String query = '';
  Timer? debounce;
  late final genres = widget.api.request('genres');
  @override
  void initState() {
    super.initState();
    restoreHistory();
  }

  Future<void> restoreHistory() async {
    try {
      final items = jsonDecode(
        await historyStore.read(key: historyKey) ?? '[]',
      );
      if (mounted && recent.isEmpty && items is List) {
        setState(() => recent.addAll(items.whereType<String>().take(5)));
      }
    } on Exception {
      return;
    }
  }

  Future<void> remember(Item title) async {
    final name = (title['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return;
    setState(() {
      recent.removeWhere((v) => v.toLowerCase() == name.toLowerCase());
      recent.insert(0, name);
      if (recent.length > 5) recent.removeLast();
    });
    try {
      await historyStore.write(key: historyKey, value: jsonEncode(recent));
    } on Exception {
      return;
    }
  }

  void change(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => query = value.trim());
    });
  }

  void selectTerm(String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    debounce?.cancel();
    setState(() => query = value);
  }

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gutter = MobileLayout(context).gutter;
    return AdaptivePage(
      title: const MobileBrand(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 15, gutter, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Buscar',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 44,
                  child: apple(context)
                      ? CupertinoSearchTextField(
                          controller: controller,
                          placeholder: 'Filmes, séries e mais',
                          onChanged: change,
                        )
                      : TextField(
                          controller: controller,
                          onChanged: change,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            hintText: 'Filmes, séries e mais',
                            suffixIcon: query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Limpar busca',
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => selectTerm(''),
                                  ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (query.isEmpty)
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: FutureBuilder(
                  future: genres,
                  builder: (ctx, snap) {
                    final terms = recent.isEmpty
                        ? jsonRows(
                            snap.data,
                          ).map((g) => g['name']).whereType<String>().take(8)
                        : recent;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (recent.isNotEmpty)
                          const Text(
                            'Pesquisas recentes',
                            style: TextStyle(fontSize: 12),
                          ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final term in terms)
                              ActionChip(
                                label: Text(
                                  term,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onPressed: () => selectTerm(term),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
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
                onTitleSelected: remember,
              ),
            ),
        ],
      ),
    );
  }
}

class Feed extends StatefulWidget {
  const Feed({
    super.key,
    required this.api,
    required this.index,
    required this.onChange,
    this.query = '',
    this.onTitleSelected,
    this.bottomInset = 0,
    this.active = true,
  });
  final BechiApi api;
  final int index;
  final String query;
  final ValueChanged<Item>? onTitleSelected;
  final double bottomInset;
  final bool active;
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
  Map<String, String> filters = {};
  String get filterQuery =>
      filters.isEmpty ? '' : '&${Uri(queryParameters: filters).query}';
  String get path => [
    'home?rankings=1',
    'titles?kind=movie&limit=42$filterQuery',
    'titles?kind=series&limit=42$filterQuery',
    'live/catalog',
    'me/library',
    'search?q=${Uri.encodeQueryComponent(widget.query)}&limit=42',
  ][widget.index];
  @override
  void initState() {
    super.initState();
    result = load();
  }

  Future<dynamic> load() async {
    final current = ++generation;
    final data = await widget.api.request(path);
    if (current == generation) {
      cursor =
          jsonMap(data)[widget.index == 4 ? 'continue_cursor' : 'next_cursor']
              as String?;
    }
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
          widget.index == 4
              ? 'me/continue-watching?page=1&limit=40&cursor=${Uri.encodeQueryComponent(cursor!)}'
              : '$path&cursor=${Uri.encodeQueryComponent(cursor!)}',
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

  Future<void> open(Item t, {bool play = false}) async {
    if (t['slug'] == null ||
        t['slug'] == '' ||
        jsonMap(t['ranking'])['available'] == false) {
      await showAdaptiveDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog.adaptive(
          title: Text(t['name'] ?? 'Em alta'),
          content: const Text(
            'Este título ainda não está disponível no catálogo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
      return;
    }
    widget.onTitleSelected?.call(t);
    var changed = false;
    await showPage(
      context,
      TitleDetails(
        api: widget.api,
        summary: t,
        playOnOpen: play && t['kind'] != 'series',
        onLibraryChange: () => changed = true,
      ),
    );
    if (mounted && changed) widget.onChange();
  }

  Widget poster(Item t, {bool resume = false, bool grid = false}) => Semantics(
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
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Art(
                      (resume
                              ? t['resume_image']
                              : t['poster'] ??
                                    jsonMap(t['ranking'])['artwork']) ??
                          t['rail_cover'] ??
                          t['landscape_cover'] ??
                          t['backdrop'] ??
                          t['poster'],
                    ),
                    if (t['drive_source'] == true || t['online_source'] == true)
                      Positioned(
                        right: 4,
                        top: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (t['drive_source'] == true)
                              const _CoverBadge('Drive', Icons.cloud_outlined),
                            if (t['online_source'] == true)
                              const _CoverBadge('Online', Icons.wifi),
                          ],
                        ),
                      ),
                    if (jsonMap(t['ranking'])['available'] == false)
                      const Positioned(
                        bottom: 4,
                        left: 4,
                        right: 4,
                        child: ColoredBox(
                          color: Colors.black87,
                          child: Text(
                            'Indisponível',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    if (resume &&
                        t['duration_ms'] is num &&
                        t['duration_ms'] > 0 &&
                        t['position_ms'] is num)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: LinearProgressIndicator(
                          value: (t['position_ms'] / t['duration_ms'])
                              .clamp(0, 1)
                              .toDouble(),
                        ),
                      ),
                    if (jsonMap(t['ranking'])['position'] case final num rank)
                      Positioned(
                        left: 6,
                        top: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              '#$rank',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: grid ? 8 : 6),
          SizedBox(
            height:
                MediaQuery.textScalerOf(context).scale(grid ? 12 : 11) *
                (grid ? 1.3 : 1.28) *
                2,
            child: Text(
              t['name'] ?? '',
              style: grid
                  ? MobileLayout.cardLabel.copyWith(fontSize: 12, height: 1.3)
                  : MobileLayout.cardLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (resume && t['episode_number'] != null)
            Text(
              'T${t['season_number']} · EP ${t['episode_number']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
      final layout = MobileLayout(context);
      final spacing = layout.gutter;
      if (widget.index == 0 || widget.index == 4) {
        final library = widget.index == 4;
        final hero = library ? <Item>[] : highlights(data);
        final continuing = <String, Item>{
          for (final t in [...jsonRows(data['continue_watching']), ...extra])
            t['id'].toString(): t,
        }.values.toList();
        final rails = library
            ? <Item>[
                {'name': 'Minha lista', 'items': data['watchlist']},
                if (continuing.isNotEmpty)
                  {
                    'id': 'continue',
                    'name': 'Continuar assistindo',
                    'items': continuing,
                  },
                if (jsonRows(data['watch_again']).isNotEmpty)
                  {'name': 'Assistir novamente', 'items': data['watch_again']},
              ]
            : jsonRows(data['rails'])
                  .where((r) => r['id'] != 'continue' && r['id'] != 'watchlist')
                  .toList();
        return ListView.builder(
          padding: widget.bottomInset == 0
              ? null
              : EdgeInsets.only(bottom: widget.bottomInset),
          itemCount: rails.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return library
                  ? const SizedBox.shrink()
                  : CatalogHighlights(
                      titles: hero,
                      active: widget.active,
                      onDetails: open,
                      onPlay: (t) => open(t, play: true),
                    );
            }
            final rail = rails[i - 1];
            final rows = jsonRows(rail['items']);
            if (rows.isEmpty && library) {
              return const ListTile(
                title: Text('Minha lista'),
                subtitle: Text(
                  'Adicione títulos à sua lista para encontrá-los aqui.',
                ),
              );
            }
            if (rows.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(spacing, 20, spacing, 8),
                  child: Text(
                    rail['name'],
                    style: TextStyle(
                      fontSize: layout.railTitle,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.02 * layout.railTitle,
                    ),
                  ),
                ),
                SizedBox(
                  height:
                      (rail['id'] == 'continue'
                          ? layout.previewWidth * 9 / 16
                          : layout.coverWidth * 1.5) +
                      6 +
                      MediaQuery.textScalerOf(context).scale(11) *
                          1.28 *
                          (rail['id'] == 'continue' ? 3 : 2),
                  child: ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: spacing),
                    scrollDirection: Axis.horizontal,
                    itemCount:
                        rows.length +
                        (rail['id'] == 'continue' && cursor != null ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => i == rows.length
                        ? Center(
                            child: actionButton(
                              context,
                              pageError ?? 'Carregar mais',
                              paging ? null : more,
                            ),
                          )
                        : SizedBox(
                            width: rail['id'] == 'continue'
                                ? layout.previewWidth
                                : layout.coverWidth,
                            child: poster(
                              rows[i],
                              resume: rail['id'] == 'continue',
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        );
      }
      if (widget.index == 3) {
        return LiveGuide(
          api: widget.api,
          data: data,
          bottomInset: widget.bottomInset,
        );
      }
      final items = [
        ...jsonRows(widget.index == 4 ? snap.data : data['items']),
        ...extra,
      ];
      final browse = widget.index == 1 || widget.index == 2;
      if (items.isEmpty && !browse) {
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
          if (browse)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(spacing, 16, spacing, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.index == 1 ? 'Filmes' : 'Séries',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CatalogFilters(
                      api: widget.api,
                      kind: widget.index == 1 ? 'movie' : 'series',
                      initial: filters,
                      onChange: (next) {
                        filters = next;
                        reload();
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (browse && items.isEmpty)
            const SliverToBoxAdapter(
              child: Center(
                child: Text('Nenhum conteúdo disponível para esses filtros.'),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.all(spacing),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: layout.columns,
                mainAxisExtent:
                    ((layout.width - 2 * spacing - 9 * (layout.columns - 1)) /
                            layout.columns) *
                        1.5 +
                    8 +
                    MediaQuery.textScalerOf(context).scale(12) * 2 * 1.3,
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => poster(items[i], grid: true),
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
          if (widget.bottomInset > 0)
            SliverToBoxAdapter(child: SizedBox(height: widget.bottomInset)),
        ],
      );
    },
  );
}

class _CoverBadge extends StatelessWidget {
  const _CoverBadge(this.label, this.icon);
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 3),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xff164762),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: Colors.white),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}
