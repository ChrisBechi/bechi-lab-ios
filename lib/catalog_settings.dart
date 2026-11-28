part of 'catalog.dart';

class CatalogSettings extends StatefulWidget {
  const CatalogSettings({super.key, required this.api, required this.onLogout});
  final BechiApi api;
  final Future<void> Function() onLogout;
  @override
  State<CatalogSettings> createState() => _CatalogSettingsState();
}

class _CatalogSettingsState extends State<CatalogSettings> {
  late Future<Item> loaded = widget.api.readPreferences();
  bool saving = false;
  String? error;
  Future<void> save(Item settings, String key, dynamic value) async {
    setState(() => saving = true);
    try {
      final updated = jsonMap(
        await widget.api.request(
          'me/preferences',
          method: 'PUT',
          body: {...settings, key: value},
        ),
      );
      widget.api.preferences = updated;
      if (mounted) {
        setState(() {
          loaded = Future.value(updated);
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível salvar a preferência.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdaptivePage(
    title: const Text('Configurações'),
    body: FutureBuilder(
      future: loaded,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(
            child: actionButton(
              ctx,
              'Tentar novamente',
              () => setState(() => loaded = widget.api.readPreferences()),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final p = snap.data!;
        Widget choice(String key, String label, Map<String, String> values) =>
            ListTile(
              title: Text(label),
              trailing: DropdownButton<String>(
                value: values.containsKey(p[key]) ? p[key] : values.keys.first,
                items: [
                  for (final v in values.entries)
                    DropdownMenuItem(value: v.key, child: Text(v.value)),
                ],
                onChanged: saving ? null : (v) => save(p, key, v),
              ),
            );
        return ListView(
          children: [
            for (final entry in {
              'autoplay_next': 'Próximo episódio automático',
              'resume': 'Retomar de onde parou',
            }.entries)
              SwitchListTile.adaptive(
                title: Text(entry.value),
                value: p[entry.key] != false,
                onChanged: saving ? null : (v) => save(p, entry.key, v),
              ),
            choice('audio_language', 'Áudio preferido', {
              'pt-BR': 'Português',
              'en': 'Inglês',
              'original': 'Original',
            }),
            choice('subtitle_language', 'Legendas preferidas', {
              'off': 'Desativadas',
              'pt-BR': 'Português',
              'en': 'Inglês',
            }),
            choice('subtitle_size', 'Tamanho das legendas', {
              'normal': 'Normal',
              'small': 'Pequena',
              'large': 'Grande',
            }),
            if (error != null) ListTile(title: Text(error!)),
            const Divider(),
            const ListTile(
              title: Text('Servidor online'),
              subtitle: Text(bechiOrigin),
            ),
            ListTile(
              title: const Text('Sair da conta'),
              leading: const Icon(Icons.logout),
              onTap: () async {
                Navigator.pop(ctx);
                await widget.onLogout();
              },
            ),
          ],
        );
      },
    ),
  );
}
