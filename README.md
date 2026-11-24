# Bechi Lab · protótipo Flutter para iPhone

Versão 0.1.1: libera o documento oficial Abyss/C7 e reconhece as duas formas
(Unicode e ASCII) dos domínios internacionais usados pela SuperFlix. Se a origem
responder com uma verificação, “Validar fonte” abre a página oficial no próprio
app; conclua a confirmação e toque em “Voltar ao player”. A sessão permanece
no armazenamento do mesmo app. O protótipo não resolve desafios humanos.

Laboratório com 15 entradas para testar separadamente SuperFlix, Drive, TeraBox,
Rede Canais, MediaFire, NoveFlix, C7, magnet, Archive, Animes Digital, South Park
e três fontes ao vivo. A interface e o controle de navegação são Flutter/WKWebView;
cada entrada usa o adaptador web correspondente do Bechi Flix. Este protótipo
avalia a reprodução e o controle da WebView antes de uma migração dos codecs.

Entre normalmente no Bechi Flix dentro do app. O app mantém os dados da sessão
no armazenamento padrão do WebKit. Não contém senha, chave de servidor ou conta
Apple. Se a rede bloquear a origem, use a conexão que já permitiu acessá-la.

Para SuperFlix, o script executado no documento da própria fonte tenta selecionar
o servidor principal dublado pela sessão oficial. Ele não interage com desafios
humanos, não forja cookies e preserva recusas de autorização. O teste de magnet
abre os detalhes para selecionar Online → 1080p. Fontes ausentes no exemplo são
informadas, sem escolher silenciosamente outra fonte.

Novas janelas são recusadas pelo aplicativo. A navegação de documentos permite
somente os domínios declarados em `lib/source_case.dart`. TLS e as proteções do
WebKit permanecem normais. A captura de diagnóstico aceita somente estados
predefinidos; URLs assinadas, cookies e mensagens de terceiros não são gravados.

## Validar

```sh
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos
flutter test
node --test test/source_lab.test.mjs
```

## Gerar o IPA

O build Flutter iOS precisa de macOS/Xcode. O workflow manual
`.github/workflows/ios-lab.yml` instala o SDK Flutter oficial com checksum,
executa as verificações e compila um binário ARM64 de dispositivo real.
Ele publica um prerelease com o IPA e seu SHA-256; não usa certificado Apple.

O IPA produzido precisa ser reassinado no SideStore ou Sideloadly, como o app
Contador. A abertura, imagem e áudio no iPhone serão confirmados na instalação
física. A assinatura não é uma autorização de distribuição pela App Store.
