import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'source_case.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BechiLab());
}

class BechiLab extends StatelessWidget {
  const BechiLab({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bechi Lab',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.lightBlue,
      scaffoldBackgroundColor: const Color(0xff0b1018),
      useMaterial3: true,
    ),
    home: const SourceList(),
  );
}

class SourceList extends StatelessWidget {
  const SourceList({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('BECHI FLIX · LAB')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Teste cada fonte',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Cada opção abre seu próprio player de teste. Entre no Bechi Flix na primeira abertura. A sessão fica neste app.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Se sua rede bloquear a fonte, mantenha a conexão que já funcionou no Safari. Confirme a verificação humana quando a origem solicitar.',
        ),
        const SizedBox(height: 16),
        for (final source in sourceCases)
          Card(
            child: ListTile(
              leading: Icon(
                source.liveId == null
                    ? Icons.play_circle_outline
                    : Icons.live_tv,
              ),
              title: Text(source.name),
              subtitle: Text(source.example),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SourcePlayer(source: source),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class SourcePlayer extends StatefulWidget {
  const SourcePlayer({super.key, required this.source});
  final SourceCase source;
  @override
  State<SourcePlayer> createState() => _SourcePlayerState();
}

class _SourcePlayerState extends State<SourcePlayer> {
  InAppWebViewController? _controller;
  String _status = 'Abrindo…';
  int _blocked = 0;
  late final Future<String> _script = rootBundle.loadString(
    'assets/source_lab.js',
  );
  void status(String value) {
    if (mounted && value != _status) setState(() => _status = value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.source.name, style: const TextStyle(fontSize: 15)),
      actions: [
        IconButton(
          tooltip: 'Recarregar',
          icon: const Icon(Icons.refresh),
          onPressed: () => _controller?.reload(),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _status,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (_blocked > 0)
                Tooltip(
                  message: 'Janelas ou navegações externas bloqueadas',
                  child: Text(
                    '🛡 $_blocked',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<String>(
            future: _script,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Não foi possível preparar o teste.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(widget.source.initialUrl.toString()),
                ),
                initialUserScripts: UnmodifiableListView([
                  UserScript(
                    source:
                        '(${snapshot.data})(${jsonEncode(widget.source.configuration)});',
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    forMainFrameOnly: false,
                  ),
                ]),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  allowsInlineMediaPlayback: true,
                  mediaPlaybackRequiresUserGesture: false,
                  javaScriptCanOpenWindowsAutomatically: false,
                  supportMultipleWindows: true,
                  useShouldOverrideUrlLoading: true,
                  isInspectable: false,
                ),
                onWebViewCreated: (controller) {
                  _controller = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'bechiLabStatus',
                    callback: (args) {
                      if (args.length == 1 && args[0] is String) {
                        const messages = {
                          'login': 'Entre no Bechi Flix para continuar.',
                          'search': 'Localizando o exemplo no catálogo…',
                          'missing':
                              'Fonte não encontrada neste exemplo. Escolha outro título no catálogo.',
                          'source': 'Fonte selecionada. Preparando o player…',
                          'principal': 'Preparando o servidor principal…',
                          'manual':
                              'A origem solicita interação. Use os controles da fonte.',
                          'playing': 'Vídeo reproduzindo',
                          'paused': 'Vídeo pausado',
                          'buffering': 'Carregando vídeo…',
                          'error':
                              'A fonte não conseguiu reproduzir. Tente recarregar.',
                          'magnet':
                              'Escolha Online → 1080p no catálogo para testar o magnet.',
                        };
                        final message = messages[args[0]];
                        if (message != null) status(message);
                      }
                      return null;
                    },
                  );
                },
                shouldOverrideUrlLoading: (controller, action) async {
                  final value = action.request.url;
                  if (value != null &&
                      allowedNavigation(Uri.parse(value.toString()))) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  if (mounted) setState(() => _blocked++);
                  return NavigationActionPolicy.CANCEL;
                },
                onCreateWindow: (controller, action) async {
                  if (mounted) setState(() => _blocked++);
                  return false;
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame == true) {
                    status(
                      'A página não abriu. Confira a conexão e recarregue.',
                    );
                  }
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
