import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'bechi_api.dart';
import 'player_view.dart';
import 'source_case.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const BechiNativeApp());
}

class BechiNativeApp extends StatefulWidget {
  const BechiNativeApp({super.key});
  @override
  State<BechiNativeApp> createState() => _BechiNativeAppState();
}

class _BechiNativeAppState extends State<BechiNativeApp> {
  final api = BechiApi();
  late final Future<bool> restored = api.restore();
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bechi Native',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.lightBlue,
      scaffoldBackgroundColor: const Color(0xff0b1018),
      useMaterial3: true,
    ),
    home: FutureBuilder<bool>(
      future: restored,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return api.authenticated
            ? NativeSources(
                api: api,
                onLogout: () async {
                  await api.logout();
                  setState(() {});
                },
              )
            : NativeLogin(api: api, onLogin: () => setState(() {}));
      },
    ),
  );
}

class NativeLogin extends StatefulWidget {
  const NativeLogin({super.key, required this.api, required this.onLogin});
  final BechiApi api;
  final VoidCallback onLogin;
  @override
  State<NativeLogin> createState() => _NativeLoginState();
}

class _NativeLoginState extends State<NativeLogin> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String? error;
  Future<void> login() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.login(email.text, password.text);
      password.clear();
      if (mounted) widget.onLogin();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiFailure
              ? e.message
              : 'Não foi possível entrar. Confira sua conexão.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('BECHI · NATIVO 0.2.0')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Entre no Bechi Flix',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('Player nativo, com os controles feitos em Flutter.'),
            const SizedBox(height: 24),
            TextField(
              key: const Key('login-email'),
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('login-password'),
              controller: password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => login(),
              decoration: const InputDecoration(labelText: 'Senha'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : login,
              child: Text(busy ? 'Entrando…' : 'Entrar'),
            ),
            const SizedBox(height: 24),
            const Text('Conferir os codecs do aparelho'),
            for (final source in codecCases)
              ListTile(
                title: Text(source.name),
                trailing: const Icon(Icons.play_arrow),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        NativePlayerPage(api: widget.api, source: source),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class NativeSources extends StatelessWidget {
  const NativeSources({super.key, required this.api, required this.onLogout});
  final BechiApi api;
  final Future<void> Function() onLogout;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('BECHI · NATIVO 0.2.0'),
      actions: [
        IconButton(
          tooltip: 'Sair da conta',
          icon: const Icon(Icons.logout),
          onPressed: onLogout,
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Fontes de reprodução',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Cada fonte usa o motor nativo e os mesmos controles do app.',
        ),
        const SizedBox(height: 16),
        for (final source in [...sourceCases, ...codecCases])
          Card(
            child: ListTile(
              key: Key('source-${source.id}'),
              leading: Icon(
                source.isLive ? Icons.live_tv : Icons.play_circle_outline,
              ),
              title: Text(source.name),
              subtitle: Text(source.example),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NativePlayerPage(api: api, source: source),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Motor nativo: libmpv / FFmpeg. Interface: Flutter.',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Bechi Native',
          ),
          child: const Text('Licenças de código aberto'),
        ),
      ],
    ),
  );
}
