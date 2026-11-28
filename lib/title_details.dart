part of 'catalog.dart';

class TitleDetails extends StatefulWidget {
  const TitleDetails({super.key, required this.api, required this.summary});
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
  String? notice;
  @override
  void initState() {
    super.initState();
    ready = load();
    loadFavorite();
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
    title: const Text('Detalhes'),
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
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView.builder(
              itemCount: 1 + eps.length,
              itemBuilder: (context, i) {
                if (i > 0) {
                  final ep = eps[i - 1];
                  return ListTile(
                    selected: episodeIndex == i - 1,
                    leading: SizedBox(
                      width: 72,
                      height: 46,
                      child: Art(ep['thumbnail_url']),
                    ),
                    title: Text('EP ${ep['episode_number']} · ${ep['name']}'),
                    subtitle: ep['synopsis_short'] == null
                        ? null
                        : Text(
                            ep['synopsis_short'],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: const Icon(Icons.play_arrow),
                    onTap: () {
                      setState(() {
                        episodeIndex = i - 1;
                        sourceIndex = 0;
                      });
                      if (sources.isNotEmpty) play();
                    },
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 2.25,
                      child: SizedBox.expand(
                        child: Art(
                          title['backdrop'] ??
                              title['landscape_cover'] ??
                              title['poster'],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title['name'],
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          Text(
                            [
                              title['release_year'],
                              title['content_rating'],
                              ...jsonRows(
                                title['genres'],
                              ).map((g) => g['name']),
                            ].whereType<Object>().join(' · '),
                          ),
                          const SizedBox(height: 12),
                          Text(
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
