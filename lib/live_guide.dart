part of 'catalog.dart';

class LiveGuide extends StatelessWidget {
  const LiveGuide({super.key, required this.data, required this.api});
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
    final groupsList = groups.values.toList();
    return ListView.builder(
      itemCount: groupsList.length + events.length,
      itemBuilder: (context, i) {
        if (i < events.length) {
          final e = events[i];
          return ListTile(
            leading: const Icon(Icons.sports),
            title: Text(e['title']),
            onTap: () => showPage(
              context,
              NativePlayerPage(
                api: api,
                source: SourceCase(
                  'event',
                  'Ao vivo',
                  e['title'],
                  'live',
                  liveId: e['id'],
                  isEvent: true,
                ),
              ),
            ),
          );
        }
        final group = groupsList[i - events.length];
        final channel = group.first;
        final title =
            jsonMap(channel['source_group'])['name'] ?? channel['name'];
        final programs =
            group
                .map((c) => guides[c['guide_id'] ?? c['id']])
                .whereType<List<Item>>()
                .where((g) => g.isNotEmpty)
                .firstOrNull ??
            [];
        return ListTile(
          leading: SizedBox(
            width: 60,
            height: 40,
            child: Art(channel['image']),
          ),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showPage(
            context,
            ChannelGuide(
              api: api,
              name: title,
              sources: group,
              programs: programs,
            ),
          ),
        );
      },
    );
  }
}

class ChannelGuide extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = programs.where((p) {
      final ends = DateTime.tryParse(p['end'] ?? p['start'] ?? '');
      return ends != null && ends.isAfter(now);
    }).toList();
    return AdaptivePage(
      title: Text(name),
      body: ListView(
        children: [
          for (final source in sources)
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(source['source_label'] ?? source['name']),
              onTap: () => showPage(
                context,
                NativePlayerPage(
                  api: api,
                  source: SourceCase(
                    'live',
                    source['source_label'] ?? source['name'],
                    name,
                    'live',
                    liveId: source['id'],
                  ),
                ),
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
