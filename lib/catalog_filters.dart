part of 'catalog.dart';

class CatalogFilters extends StatefulWidget {
  const CatalogFilters({
    super.key,
    required this.api,
    required this.kind,
    required this.initial,
    required this.onChange,
  });
  final BechiApi api;
  final ValueChanged<Map<String, String>> onChange;
  final String kind;
  final Map<String, String> initial;
  @override
  State<CatalogFilters> createState() => _CatalogFiltersState();
}

class _CatalogFiltersState extends State<CatalogFilters> {
  late final selected = Map.of(widget.initial);
  late Future<dynamic> facets = query();
  Future<dynamic> query() => widget.api.request(
    'facets?${Uri(queryParameters: {
      'kind': widget.kind,
      for (final key in ['genre', 'year', 'rating'])
        if (selected[key] != null) key: selected[key]!,
    }).query}',
  );
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: facets,
    builder: (ctx, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator.adaptive());
      }
      if (snap.hasError) {
        return Center(
          child: actionButton(
            ctx,
            'Tentar novamente',
            () => setState(() => facets = query()),
          ),
        );
      }
      final data = jsonMap(snap.data);
      Widget field(
        String key,
        String name,
        Map<String, String> options,
        String all,
      ) {
        final values = {
          '': all,
          ...options,
          if (selected.containsKey(key) && !options.containsKey(selected[key]))
            selected[key]!: selected[key]!,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 5),
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: const Color(0xff16202b),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  isExpanded: true,
                  value: selected[key] ?? '',
                  items: [
                    for (final entry in values.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          entry.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    if (v == null || v.isEmpty) {
                      selected.remove(key);
                    } else {
                      selected[key] = v;
                    }
                    widget.onChange(Map.of(selected));
                  }),
                ),
              ),
            ),
          ],
        );
      }

      return LayoutBuilder(
        builder: (ctx, box) {
          final fields = <Widget>[
            field('genre', 'Gênero', {
              for (final g in jsonRows(data['genres'])) g['slug']: g['name'],
            }, 'Todos os gêneros'),
            field('year', 'Ano', {
              for (final y in (data['years'] as List? ?? []))
                y.toString(): y.toString(),
            }, 'Todos os anos'),
            field('rating', 'Classificação', {
              for (final r in (data['ratings'] as List? ?? []))
                r.toString(): r.toString(),
            }, 'Todas'),
            field('sort', 'Ordenar', {
              'name': 'Título A–Z',
              'year': 'Ano de lançamento',
            }, 'Mais recentes'),
          ];
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final f in fields)
                SizedBox(width: (box.maxWidth - 10) / 2, child: f),
            ],
          );
        },
      );
    },
  );
}
