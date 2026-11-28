part of 'catalog.dart';

class LiveGuide extends StatelessWidget {
  const LiveGuide({
    super.key,
    required this.data,
    required this.api,
    this.bottomInset = 0,
  });
  final double bottomInset;
  final Item data;
  final BechiApi api;
  @override
  Widget build(BuildContext context) {
    final channels = jsonRows(data['channels']),
        events = jsonRows(data['events']);
    final guides = {
      for (final guide in jsonRows(data['epg']))
        guide['id']: jsonRows(guide['programs']),
    };
    final groups = <String, List<Item>>{};
    for (final c in channels) {
      final id =
          (jsonMap(c['source_group'])['id'] ?? c['variant_of'] ?? c['id'])
              .toString();
      groups.putIfAbsent(id, () => []).add(c);
    }
    final categories = {
      for (final c in jsonRows(data['categories'])) c['id']: c['name'],
    };
    final rails =
        <String, List<({String label, String art, VoidCallback open})>>{};
    final now = DateTime.now();
    for (final event in events) {
      final start = DateTime.tryParse(event['time_start'] ?? '');
      final end = DateTime.tryParse(event['time_end'] ?? '');
      if (end != null && !end.isAfter(now)) continue;
      final rail = start != null && start.isAfter(now)
          ? 'Próximos eventos'
          : 'Eventos ao vivo';
      rails.putIfAbsent(rail, () => []).add((
        label: event['title'],
        art: '/api/v1/live/art/event/${event['id']}?v=4',
        open: () => showPage(
          context,
          NativePlayerPage(
            api: api,
            source: SourceCase(
              'event',
              'Ao vivo',
              event['title'],
              'live',
              liveId: event['id'],
              isEvent: true,
            ),
          ),
        ),
      ));
    }
    final channelsByName = groups.values.toList()
      ..sort(
        (a, b) =>
            (a.first['name'] as String).compareTo(b.first['name'] as String),
      );
    for (final group in channelsByName) {
      final channel = group.first;
      final name =
          (jsonMap(channel['source_group'])['name'] ?? channel['name'])
              as String;
      final rail =
          group
              .expand((c) => c['categories'] as List? ?? [])
              .where((id) => id != 0)
              .map((id) => categories[id])
              .whereType<String>()
              .firstOrNull ??
          'Outros canais';
      final programs =
          group
              .map((c) => guides[c['guide_id'] ?? c['id']])
              .whereType<List<Item>>()
              .where((p) => p.isNotEmpty)
              .firstOrNull ??
          [];
      rails.putIfAbsent(rail, () => []).add((
        label: name,
        art:
            '/api/v1/live/art/channel/${channel['artwork_id'] ?? channel['id']}?v=${channel['provider'] != null && channel['artwork_id'] == null ? 6 : 5}',
        open: () => showPage(
          context,
          ChannelGuide(
            api: api,
            name: name,
            sources: group,
            programs: programs,
          ),
        ),
      ));
    }
    final layout = MobileLayout(context);
    final sections = rails.entries.toList();
    return ListView.builder(
      padding: EdgeInsets.only(top: 16, bottom: 20 + bottomInset),
      itemCount: sections.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
            child: const Text(
              'Ao vivo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          );
        }
        final section = sections[i - 1];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter, 16, layout.gutter, 8),
              child: Text(
                section.key,
                style: TextStyle(
                  fontSize: layout.railTitle,
                  height: 1.2,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(
              height:
                  layout.previewWidth * 9 / 16 +
                  6 +
                  MediaQuery.textScalerOf(context).scale(11) * 1.28 * 2,
              child: ListView.separated(
                key: PageStorageKey('live-${section.key}'),
                padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                scrollDirection: Axis.horizontal,
                itemCount: section.value.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final card = section.value[index];
                  return SizedBox(
                    width: layout.previewWidth,
                    child: InkWell(
                      onTap: card.open,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Art(card.art),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            card.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: MobileLayout.cardLabel,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class ChannelGuide extends StatefulWidget {
  const ChannelGuide({
    super.key,
    required this.api,
    required this.name,
    required this.sources,
    required this.programs,
  });
  final BechiApi api;
  final String name;
  final List<Item> sources, programs;
  @override
  State<ChannelGuide> createState() => _ChannelGuideState();
}

class _ChannelGuideState extends State<ChannelGuide> {
  int selected = 0;
  bool inPlayer = false;
  SourceCase get source {
    final item = widget.sources[selected];
    return SourceCase(
      'live',
      item['source_label'] ?? item['name'],
      widget.name,
      'live',
      liveId: item['id'],
    );
  }

  Future<void> expand() async {
    if (inPlayer) return;
    setState(() => inPlayer = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await showPage(context, NativePlayerPage(api: widget.api, source: source));
    if (mounted) setState(() => inPlayer = false);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = widget.programs.where((p) {
      final ends = DateTime.tryParse(p['end'] ?? p['start'] ?? '');
      return ends != null && ends.isAfter(now);
    }).toList();
    return AdaptivePage(
      title: Text(widget.name),
      body: ListView(
        children: [
          if (!inPlayer)
            ChannelPreview(
              key: ValueKey(source.liveId),
              api: widget.api,
              source: source,
              onExpand: expand,
            ),
          if (widget.sources.length > 1)
            ListTile(
              title: const Text('Fonte'),
              subtitle: DropdownButton<int>(
                isExpanded: true,
                value: selected,
                items: [
                  for (var i = 0; i < widget.sources.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        widget.sources[i]['source_label'] ??
                            widget.sources[i]['name'],
                      ),
                    ),
                ],
                onChanged: (i) {
                  if (i != null) setState(() => selected = i);
                },
              ),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Programação'),
          ),
          if (upcoming.isEmpty)
            const ListTile(title: Text('Programação indisponível.')),
          for (final p in upcoming)
            ListTile(
              title: Text(p['title'] ?? ''),
              subtitle: Text(p['description'] ?? ''),
              leading: Text(_time(context, p['start'])),
            ),
        ],
      ),
    );
  }

  String _time(BuildContext context, dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null
        ? ''
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(date.toLocal()),
            alwaysUse24HourFormat: true,
          );
  }
}
