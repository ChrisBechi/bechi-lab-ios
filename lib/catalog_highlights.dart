part of 'catalog.dart';

List<Item> highlights(Item home) {
  final curated = jsonRows(home['hero']);
  final movies =
      [
        ...curated,
        ...jsonRows(home['rails']).expand((rail) => jsonRows(rail['items'])),
      ].where(
        (title) =>
            title['kind'] == 'movie' &&
            title['backdrop'] != null &&
            title['ranking'] == null,
      );
  final seen = <Object?>{};
  return (movies.isEmpty ? curated : movies)
      .where((t) => seen.add(t['id']))
      .take(5)
      .toList();
}

class CatalogHighlights extends StatefulWidget {
  const CatalogHighlights({
    super.key,
    required this.titles,
    required this.onDetails,
    required this.onPlay,
    required this.active,
  });
  final List<Item> titles;
  final ValueChanged<Item> onDetails, onPlay;
  final bool active;
  @override
  State<CatalogHighlights> createState() => _CatalogHighlightsState();
}

class _CatalogHighlightsState extends State<CatalogHighlights> {
  final pages = PageController();
  int index = 0;
  Timer? timer;
  void schedule() {
    timer?.cancel();
    if (widget.titles.length < 2 ||
        !widget.active ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    timer = Timer(const Duration(seconds: 9), () {
      if (!mounted || !pages.hasClients) return;
      if (ModalRoute.of(context)?.isCurrent == true &&
          !pages.position.isScrollingNotifier.value) {
        pages.animateToPage(
          (index + 1) % widget.titles.length,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
        );
      }
      schedule();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    schedule();
  }

  @override
  void didUpdateWidget(CatalogHighlights old) {
    super.didUpdateWidget(old);
    schedule();
  }

  @override
  void dispose() {
    timer?.cancel();
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.titles.isEmpty) return const SizedBox.shrink();
    final t = widget.titles[index.clamp(0, widget.titles.length - 1)];
    final layout = MobileLayout(context);
    final kind = t['kind'] == 'series' ? 'SÉRIE' : 'FILME';
    Widget button(
      String label,
      IconData icon,
      VoidCallback callback, {
      bool primary = false,
    }) => Expanded(
      child: TextButton.icon(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          backgroundColor: primary
              ? const Color(0xfff3f6fa)
              : const Color(0xff202a35),
          foregroundColor: primary ? MobileLayout.background : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        onPressed: callback,
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
    return Stack(
      children: [
        SizedBox(
          height: layout.artHeight,
          child: PageView.builder(
            controller: pages,
            itemCount: widget.titles.length,
            onPageChanged: (i) {
              setState(() => index = i);
              schedule();
            },
            itemBuilder: (_, i) {
              final item = widget.titles[i];
              return GestureDetector(
                onTap: () => widget.onDetails(item),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Art(
                      item['backdrop'] ?? item['poster'],
                      alignment: const Alignment(.24, -.30),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [.1, .45, .74, 1],
                          colors: [
                            Color(0x100c1015),
                            Color(0x230c1015),
                            Color(0xbc0c1015),
                            MobileLayout.background,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            layout.gutter,
            layout.artCopy,
            layout.gutter,
            18,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BECHI FLIX   $kind',
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff63cfff),
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => widget.onDetails(t),
                  child: Text(t['name'], style: layout.heading),
                ),
                const SizedBox(height: 9),
                Text(
                  [
                    t['release_year'],
                    t['content_rating'],
                    if (t['runtime_seconds'] is num)
                      '${(t['runtime_seconds'] / 60).round()} min',
                    ...jsonRows(t['genres']).map((g) => g['name']),
                  ].whereType<Object>().join('  ·  '),
                  style: const TextStyle(fontSize: 11),
                ),
                if (t['synopsis_short'] case final String d)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 14),
                    child: Text(
                      d,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.45),
                    ),
                  ),
                Row(
                  children: [
                    button(
                      'Assistir',
                      Icons.play_arrow,
                      () => widget.onPlay(t),
                      primary: true,
                    ),
                    const SizedBox(width: 9),
                    button(
                      'Mais informações',
                      Icons.info_outline,
                      () => widget.onDetails(t),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
