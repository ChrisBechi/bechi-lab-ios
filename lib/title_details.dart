part of 'catalog.dart';

class TitleDetails extends StatefulWidget {
  const TitleDetails({
    super.key,
    required this.api,
    required this.summary,
    this.onLibraryChange,
    this.playOnOpen = false,
  });
  final VoidCallback? onLibraryChange;
  final bool playOnOpen;
  final BechiApi api;
  final Item summary;
  @override
  State<TitleDetails> createState() => _TitleDetailsState();
}

class _TitleDetailsState extends State<TitleDetails> {
  late Future<void> ready;
  Item title = {};
  List<Item> seasons = [];
  int seasonIndex = 0, episodeIndex = 0, sourceIndex = 0;
  bool? favorite;
  bool saving = false;
  int? reaction;
  bool ratingBusy = false;
  String? notice;
  @override
  void initState() {
    super.initState();
    ready = load();
    loadFavorite();
    loadReaction();
  }

  Future<void> loadReaction() async {
    try {
      final ratings = jsonRows(await widget.api.request('me/reactions'));
      if (mounted) {
        setState(
          () => reaction =
              ratings
                      .where((r) => r['title_id'] == widget.summary['id'])
                      .firstOrNull?['reaction']
                  as int? ??
              0,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => notice = 'Não foi possível consultar suas avaliações.');
      }
    }
  }

  Future<void> rate(int value) async {
    if (ratingBusy) return;
    if (reaction == null) {
      await loadReaction();
      if (reaction == null || !mounted) return;
    }
    final selection = reaction == value ? 0 : value;
    setState(() => ratingBusy = true);
    try {
      await widget.api.request(
        'me/reactions/${title['id']}',
        method: 'PUT',
        body: {'reaction': selection},
      );
      if (mounted) {
        setState(() => reaction = selection);
        widget.onLibraryChange?.call();
      }
    } catch (_) {
      if (mounted) {
        setState(() => notice = 'Não foi possível salvar a avaliação.');
      }
    } finally {
      if (mounted) setState(() => ratingBusy = false);
    }
  }

  Future<void> loadFavorite() async {
    try {
      final list = jsonRows(await widget.api.request('me/watchlist'));
      if (mounted) {
        setState(
          () => favorite = list.any((t) => t['id'] == widget.summary['id']),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => notice = 'Não foi possível consultar sua lista.');
      }
    }
  }

  Future<void> load() async {
    title = jsonMap(
      await widget.api.request(
        'titles/${Uri.encodeComponent(widget.summary['slug'])}',
      ),
    );
    if (title['kind'] == 'series') {
      seasons = jsonRows(
        await widget.api.request('titles/${title['id']}/seasons'),
      ).where((s) => jsonRows(s['episodes']).isNotEmpty).toList();
      final s = seasons.indexWhere(
        (s) =>
            s['season_number'] ==
            (title['season_number'] ?? widget.summary['season_number']),
      );
      seasonIndex = s < 0 ? 0 : s;
      final e = episodes.indexWhere(
        (e) =>
            e['id'] == (title['episode_id'] ?? widget.summary['episode_id']) ||
            e['episode_number'] ==
                (title['episode_number'] ?? widget.summary['episode_number']),
      );
      episodeIndex = e < 0 ? 0 : e;
    }
    if (widget.playOnOpen && sources.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) play();
      });
    }
  }

  List<Item> get episodes =>
      seasons.isEmpty ? [] : jsonRows(seasons[seasonIndex]['episodes']);
  List<Item> get sources {
    final ep = episodes.elementAtOrNull(episodeIndex);
    final streams = jsonRows(
      ep == null ? title['streams'] : ep['streams'],
    ).where((s) => s['available'] != false && s['kind'] != 'trailer').toList();
    if (ep == null &&
        title['kind'] != 'series' &&
        selectMagnetOption(jsonRows(title['source_options'])) != null) {
      streams.add({'source_type': 'torrent', 'name': 'Online · torrent'});
    }
    return streams;
  }

  Future<void> toggleFavorite() async {
    if (saving) return;
    if (favorite == null) {
      await loadFavorite();
      return;
    }
    setState(() => saving = true);
    try {
      await widget.api.request(
        'me/watchlist/${title['id']}',
        method: favorite! ? 'DELETE' : 'POST',
      );
      if (mounted) {
        setState(() {
          favorite = !favorite!;
          notice = null;
        });
        widget.onLibraryChange?.call();
      }
    } catch (_) {
      if (mounted) {
        setState(() => notice = 'Não foi possível atualizar sua lista.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> play() async {
    final stream = sources.elementAtOrNull(sourceIndex);
    if (stream == null) return;
    final name = stream['name']?.toString() ?? 'Principal',
        type = stream['source_type']?.toString() ?? 'media_server';
    final id =
        stream['superflix_browser'] == true ||
            name.toLowerCase().startsWith('superflix')
        ? 'superflix-catalog'
        : name.toLowerCase().startsWith('c7')
        ? 'c7'
        : type == 'web_video'
        ? 'nflix'
        : type;
    await showPage(
      context,
      NativePlayerPage(
        api: widget.api,
        source: SourceCase(
          id,
          name,
          title['name'],
          type,
          slug: title['slug'],
          season: seasons.elementAtOrNull(seasonIndex)?['season_number'] ?? 1,
          episode:
              episodes.elementAtOrNull(episodeIndex)?['episode_number'] ?? 1,
          preferredStreamId: stream['id'],
        ),
      ),
    );
    if (mounted) widget.onLibraryChange?.call();
  }

  Future<void> choose(
    String label,
    List<String> choices,
    int selected,
    ValueChanged<int> onSelect,
  ) async {
    final options = List.generate(
      choices.length,
      (i) => ListTile(
        selected: i == selected,
        title: Text(choices[i]),
        onTap: () => Navigator.pop(context, i),
      ),
    );
    final chosen = apple(context)
        ? await showCupertinoModalPopup<int>(
            context: context,
            builder: (ctx) => CupertinoActionSheet(
              title: Text(label),
              actions: [
                for (var i = 0; i < choices.length; i++)
                  CupertinoActionSheetAction(
                    isDefaultAction: i == selected,
                    onPressed: () => Navigator.pop(ctx, i),
                    child: Text(choices[i]),
                  ),
              ],
              cancelButton: CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
            ),
          )
        : await showModalBottomSheet<int>(
            context: context,
            showDragHandle: true,
            useSafeArea: true,
            builder: (_) => ListView(shrinkWrap: true, children: options),
          );
    if (mounted && chosen != null) setState(() => onSelect(chosen));
  }

  @override
  Widget build(BuildContext context) => AdaptivePage(
    title: const MobileBrand(),
    body: FutureBuilder(
      future: ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        if (snap.hasError) {
          return Center(
            child: actionButton(
              context,
              'Tentar novamente',
              () => setState(() => ready = load()),
            ),
          );
        }
        final eps = episodes, streams = sources;
        final layout = MobileLayout(context);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView.builder(
              itemCount: 1 + eps.length,
              itemBuilder: (context, i) {
                if (i > 0) {
                  final ep = eps[i - 1];
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: layout.gutter,
                      vertical: 6,
                    ),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          episodeIndex = i - 1;
                          sourceIndex = 0;
                        });
                        if (sources.isNotEmpty) play();
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            flex: 38,
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: Art(ep['thumbnail_url']),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Flexible(
                            flex: 62,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EP ${ep['episode_number']} · ${ep['name']}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                DefaultTextStyle.merge(
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                  child: ExpandableSynopsis(
                                    ep['synopsis'] ??
                                        ep['synopsis_short'] ??
                                        '',
                                    collapsedLines: 3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Stack(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: layout.artHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Art(
                            title['backdrop'] ??
                                title['landscape_cover'] ??
                                title['poster'],
                            alignment: const Alignment(.24, -.3),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  MobileLayout.background,
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        layout.gutter,
                        layout.artCopy,
                        layout.gutter,
                        18,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title['name'],
                            style: layout.heading.copyWith(height: 1.15),
                          ),
                          Text(
                            [
                              title['release_year'],
                              title['content_rating'],
                              ...jsonRows(
                                title['genres'],
                              ).map((g) => g['name']),
                            ].whereType<Object>().join(' · '),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          ExpandableSynopsis(
                            title['synopsis'] ?? title['synopsis_short'] ?? '',
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              actionButton(
                                context,
                                eps.isEmpty
                                    ? 'Assistir'
                                    : 'Assistir T${seasons[seasonIndex]['season_number']} EP${eps[episodeIndex]['episode_number']}',
                                streams.isEmpty ? null : play,
                              ),
                              IconButton(
                                tooltip: favorite == true
                                    ? 'Remover da minha lista'
                                    : 'Minha lista',
                                onPressed: saving ? null : toggleFavorite,
                                icon: Icon(
                                  favorite == true
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                ),
                              ),
                            ],
                          ),
                          if (notice != null) Text(notice!),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final entry in {
                                1: 'Gostei',
                                2: 'Amei',
                              }.entries)
                                FilterChip(
                                  label: Text(entry.value),
                                  selected: reaction == entry.key,
                                  onSelected: ratingBusy
                                      ? null
                                      : (_) => rate(entry.key),
                                ),
                            ],
                          ),
                          Wrap(
                            children: [
                              for (final name in [
                                'Títulos semelhantes',
                                'Idioma e legendas',
                                'Créditos e mais informações',
                              ])
                                TextButton(
                                  onPressed: () => showPage(
                                    context,
                                    DetailPanel(
                                      api: widget.api,
                                      title: title,
                                      panel: name,
                                      streams: streams,
                                      onLibraryChange: widget.onLibraryChange,
                                    ),
                                  ),
                                  child: Text(name),
                                ),
                            ],
                          ),
                          if (streams.isEmpty)
                            const Text('Nenhuma fonte disponível.'),
                          if (streams.length > 1)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Fonte'),
                              subtitle: Text(
                                streams[sourceIndex]['name'] ?? 'Principal',
                              ),
                              trailing: const Icon(Icons.expand_more),
                              onTap: () => choose(
                                'Escolher fonte',
                                streams
                                    .map(
                                      (s) =>
                                          (s['name'] ?? 'Principal').toString(),
                                    )
                                    .toList(),
                                sourceIndex,
                                (v) => sourceIndex = v,
                              ),
                            ),
                          if (seasons.isNotEmpty)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                seasons[seasonIndex]['name'] ?? 'Temporada',
                              ),
                              trailing: const Icon(Icons.expand_more),
                              onTap: () => choose(
                                'Temporada',
                                seasons
                                    .map(
                                      (s) =>
                                          (s['name'] ??
                                                  'Temporada ${s['season_number']}')
                                              .toString(),
                                    )
                                    .toList(),
                                seasonIndex,
                                (v) {
                                  seasonIndex = v;
                                  episodeIndex = 0;
                                  sourceIndex = 0;
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    ),
  );
}
