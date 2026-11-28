import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'catalog.dart';
import 'web_mobile_style.dart';
import 'package:media_kit/media_kit.dart';
import 'bechi_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
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
    title: 'Bechi Flix',
    locale: const Locale('pt', 'BR'),
    supportedLocales: const [Locale('pt', 'BR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.lightBlue,
      scaffoldBackgroundColor: MobileLayout.background,
      fontFamily: 'Arial',
      fontFamilyFallback: const ['Helvetica', 'Roboto', 'sans-serif'],
      appBarTheme: const AppBarTheme(
        backgroundColor: MobileLayout.background,
        toolbarHeight: 50,
        scrolledUnderElevation: 0,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 14, height: 1.4),
        bodySmall: TextStyle(fontSize: 12, height: 1.4),
      ),

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
            ? CatalogHome(
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
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.8),
            radius: .9,
            colors: [Color(0xff13283c), MobileLayout.background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
              child: Container(
                width: 410,
                padding: EdgeInsets.all((width * .05).clamp(22.0, 36.0)),
                decoration: BoxDecoration(
                  color: const Color(0xff111821),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 75,
                      child: ClipRect(
                        child: OverflowBox(
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: Image.asset(
                            'assets/bechi-flix.webp',
                            width: 171,
                            semanticLabel: 'Bechi Flix',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Entre no Bechi Flix',
                      style: TextStyle(
                        fontSize: (width * .05).clamp(23.0, 29.0),
                        fontWeight: FontWeight.bold,
                        letterSpacing: -.7,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (apple(context))
                      CupertinoTextField(
                        key: const Key('login-email'),
                        controller: email,
                        placeholder: 'E-mail',
                        padding: const EdgeInsets.all(14),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                      )
                    else
                      TextField(
                        key: const Key('login-email'),
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'E-mail'),
                      ),
                    const SizedBox(height: 12),
                    if (apple(context))
                      CupertinoTextField(
                        key: const Key('login-password'),
                        controller: password,
                        placeholder: 'Senha',
                        padding: const EdgeInsets.all(14),
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => login(),
                      )
                    else
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
                    if (Theme.of(context).platform == TargetPlatform.iOS)
                      CupertinoButton.filled(
                        onPressed: busy ? null : login,
                        child: Text(busy ? 'Entrando…' : 'Entrar'),
                      )
                    else
                      FilledButton(
                        onPressed: busy ? null : login,
                        child: Text(busy ? 'Entrando…' : 'Entrar'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
