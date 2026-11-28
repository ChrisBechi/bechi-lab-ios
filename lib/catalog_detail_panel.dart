part of 'catalog.dart';

class DetailPanel extends StatefulWidget {
  const DetailPanel({
    super.key,
    required this.api,
    required this.title,
    required this.panel,
    required this.streams,
    required this.onLibraryChange,
  });
  final BechiApi api;
  final Item title;
  final String panel;
  final List<Item> streams;
  final VoidCallback? onLibraryChange;
  @override
  State<DetailPanel> createState() => _DetailPanelState();
}

class _DetailPanelState extends State<DetailPanel> {
  late Future<dynamic>? related = widget.panel == 'Títulos semelhantes'
      ? fetch()
      : null;
  Future<dynamic> fetch() =>
      widget.api.request('titles/${widget.title['id']}/related');
  @override
  Widget build(BuildContext context) {
    final t = widget.title;
    Widget section(String heading, List<String> values) => ListTile(
      title: Text(heading),
      subtitle: Text(
        values.isEmpty ? 'Sem informação no catálogo.' : values.join(' · '),
      ),
    );
    Widget content;
    if (related != null) {
      content = FutureBuilder(
        future: related,
        builder: (ctx, snap) {
          if (snap.hasError) {
            return Center(
              child: actionButton(
                ctx,
                'Tentar novamente',
                () => setState(() => related = fetch()),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          final rows = jsonRows(snap.data);
          if (rows.isEmpty) {
            return const Center(
              child: Text('Nenhum título semelhante disponível.'),
            );
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (ctx, i) {
              final row = rows[i];
              return ListTile(
                leading: SizedBox(
                  width: 40,
                  height: 56,
                  child: Art(row['poster']),
                ),
                title: Text(row['name']),
                onTap: () => showPage(
                  ctx,
                  TitleDetails(
                    api: widget.api,
                    summary: row,
                    onLibraryChange: widget.onLibraryChange,
                  ),
                ),
              );
            },
          );
        },
      );
    } else if (widget.panel == 'Idioma e legendas') {
      Set<String> labels(String key) => {
        for (final s in widget.streams)
          for (final track in jsonRows(s[key]))
            if ((track['label'] ?? track['language_code']) != null)
              (track['label'] ?? track['language_code']).toString(),
      };
      content = ListView(
        children: [
          section('Áudio', labels('audio').toList()),
          section('Legendas', labels('subtitles').toList()),
        ],
      );
    } else {
      final credits = jsonRows(t['credits']);
      content = ListView(
        children: [
          section(
            'Elenco',
            credits
                .where((c) => c['department'] == 'cast')
                .map((c) => c['full_name'].toString())
                .toList(),
          ),
          section(
            'Direção e criação',
            credits
                .where(
                  (c) =>
                      c['department'] == 'directing' ||
                      c['job']?.toString().toLowerCase().contains('cria') ==
                          true,
                )
                .map((c) => c['full_name'].toString())
                .toSet()
                .toList(),
          ),
          if (t['original_name'] != null)
            section('Título original', [t['original_name']]),
          if (t['awards'] != null) section('Prêmios', [t['awards']]),
        ],
      );
    }
    return AdaptivePage(title: Text(widget.panel), body: content);
  }
}
