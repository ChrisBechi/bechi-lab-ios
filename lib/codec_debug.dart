import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'bechi_api.dart';
import 'main.dart' show BechiNativeApp;
import 'player_view.dart';
import 'source_case.dart';

/// Android diagnostic entry point. Uses the same decoder and player route as
/// iOS. The synthetic files work without a network connection or an account.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const CodecDebugApp());
}

class CodecDebugApp extends StatelessWidget {
  const CodecDebugApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bechi · Codecs',
    theme: ThemeData.dark(useMaterial3: true),
    home: const _Codecs(),
  );
}

class _Codecs extends StatefulWidget {
  const _Codecs();
  @override
  State<_Codecs> createState() => _CodecsState();
}

class _CodecsState extends State<_Codecs> {
  final api = BechiApi();
  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bechi · teste de formatos')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Amostras locais com o player nativo',
          style: TextStyle(fontSize: 20),
        ),
        const SizedBox(height: 8),
        const Text(
          'Abra um formato para conferir imagem, áudio, pausa e busca. Estes arquivos são vídeos sintéticos do projeto.',
        ),
        const SizedBox(height: 12),
        for (final source in codecCases)
          Card(
            child: ListTile(
              key: Key('source-${source.id}'),
              leading: const Icon(Icons.play_circle_outline),
              title: Text(source.name.replaceFirst('Teste nativo · ', '')),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NativePlayerPage(api: api, source: source),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BechiNativeApp()),
          ),
          child: const Text('Entrar para testar as fontes da conta'),
        ),
        const Text(
          'SuperFlix e C7 usam um conector próprio do aplicativo. Se a origem pedir confirmação humana, ela será apresentada aqui.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}
