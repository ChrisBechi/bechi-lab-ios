# Bechi Native · iPhone 0.2.0

Player com interface e controles próprios em Flutter. A decodificação usa
libmpv/FFmpeg nativos pelo media_kit, com textura GPU. O alvo é iOS ARM64.

SuperFlix e C7 possuem adaptadores privados Swift/WebKit no iOS e Kotlin/WebView no Android para preparar a origem e
entregar seus trechos ao motor nativo. Ele escolhe o principal e mantém a sessão
na troca de episódio, como na TV. A confirmação oficial só é apresentada quando
há uma caixa humana disponível. A pessoa toca na própria confirmação; não há
solução automática nem fabricação de cookies. O player e os controles são Flutter.
As outras fontes recebem a mídia diretamente dos adaptadores da API.

As 16 entradas mantêm cada fonte separada. Super Shock T1 EP10 testa o AVI
original com Xvid e MP3, além do caminho de Cyberchase. O app consulta o catálogo e os
adaptadores normais do Bechi Flix e recebe mídia para o motor nativo. Não contém
senhas ou chaves de servidor. Login usa a API normal e a sessão fica no Keychain.
Cookies da sessão não são enviados para CDNs externas. TLS é verificado.

Controles: pausa, busca, ±10 segundos, episódios, qualidade, áudio e legendas.
A rotação segue o aparelho. Ao sair, o app salva o progresso e libera somente
a sessão encerrada. Uma fonte não é substituída silenciosamente por outra.

## Verificar

```sh
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos
flutter test
flutter test integration_test/native_player_test.dart -d <iPhone-simulator> --dart-define=BECHI_SIMULATOR_DECODER_ONLY=true
```

Os testes de lógica cobrem as fontes e as sessões. A integração decodifica
AVI/Xvid/MP3, MP4/H264/AAC, MKV/H264/AC3 e MKV/HEVC/EAC3 com duas faixas de áudio e legenda.
Também inclui MOV/PCM, WebM/VP9/Opus, MPEG-TS, FLV/MP3, WMV/WMA, MPEG-2/MP2
e MKV/DTS. HLS é exercitado pelas transmissões reais; não se confunde uma
extensão aceita com a confirmação de todos os codecs possíveis naquele formato.
Os vídeos são sintéticos, criados pelo projeto. Os testes verificam o motor
real, pausa, busca, menus e retorno de rota. A disponibilidade e reprodução
das fontes reais são registradas separadamente.

A biblioteca oficial libmpv 0.6.0 inclui AudioUnit no iPhone físico, mas não
na fatia do simulador. Por isso o CI usa uma saída virtual exclusivamente no
teste do simulador: valida codecs, áudio decodificado e controles, e registra
`system_audio_verified: false`. O aplicativo de dispositivo mantém a saída
real; o som audível precisa ser conferido em hardware. A sessão temporária de
QA entra em tempo de execução no simulador e é removida ao terminar, sem ser
compilada no IPA. O workflow falha se faltar qualquer resultado esperado.
O [script oficial desta versão](https://github.com/media-kit/libmpv-darwin-build/blob/v0.6.0/scripts/mpv/build.sh)
habilita AudioUnit apenas para o alvo `ios`, deixando `iossimulator` sem ele.

## Gerar IPA

O workflow ios-lab.yml usa Flutter 3.44.2 com checksum e um Mac do GitHub.
O ambiente temporário aplica a correção oficial flutter/flutter#193142 para
aguardar o leitor de logs antes de iniciar o simulador. O patch e seu checksum
ficam em ci; o Flutter engine do aplicativo permanece o da versão fixada.
Executa análise, testes e simulador antes de empacotar ARM64. Confere Mpv e a
ausência da antiga WebView. A publicação é manual; RELEASE_NOTES.md deve
refletir os resultados reais antes de publicar.

O IPA sem assinatura precisa ser reassinado no SideStore ou Sideloadly.
O arquivo build_info.json identifica o commit realmente compilado.
A conferência física de imagem, áudio e desempenho é feita após instalar.
Fontes das bibliotecas e avisos estão em THIRD_PARTY_NOTICES.txt.

## Diagnóstico Android por USB

O alvo `lib/codec_debug.dart` permite testar os mesmos 11 vídeos sintéticos sem
conta e sem rede no Android. O APK de depuração usa um identificador separado,
`app.bechiflix.codecdebug`. Drive e demais fontes diretas também podem ser
conferidos pelo login normal. Os conectores privados SuperFlix/C7 usam a mesma
interface e transporte local nas duas plataformas. No Android, AndroidX WebKit
restringe a comunicação às origens permitidas, valida a origem real de cada
frame e transfere os trechos como buffers binários quando disponível. A janela
da fonte fica em segundo plano e só recebe foco durante uma confirmação humana.
Nova aba, popup e navegação externa são bloqueados. Não há dependência de navegador,
extensão ou computador para essa preparação. Os testes finais são feitos em cada
plataforma; a confirmação no Android não substitui a conferência do iPhone.
