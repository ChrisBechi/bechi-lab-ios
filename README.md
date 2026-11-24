# Bechi Native · iPhone 0.2.0

Player com interface e controles próprios em Flutter. A decodificação usa
libmpv/FFmpeg nativos pelo media_kit, com textura GPU. Sem WebView, iframe ou
player web no aplicativo. O alvo é iOS ARM64, não o backend web do media_kit.

As 15 entradas mantêm cada fonte separada. O app consulta o catálogo e os
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
flutter test integration_test/native_player_test.dart -d <iPhone-simulator>
```

Os testes de lógica cobrem as fontes e as sessões. A integração decodifica
MP4/H264/AAC, MKV/H264/AC3 e MKV/HEVC/EAC3 com duas faixas de áudio e legenda.
Os vídeos são sintéticos, criados pelo projeto. Os testes verificam o motor
real, pausa, busca, menus e retorno de rota. A disponibilidade e reprodução
das fontes reais são registradas separadamente.

## Gerar IPA

O workflow ios-lab.yml usa Flutter 3.44.2 com checksum e um Mac do GitHub.
Executa análise, testes e simulador antes de empacotar ARM64. Confere Mpv e a
ausência da antiga WebView. A publicação é manual; RELEASE_NOTES.md deve
refletir os resultados reais antes de publicar.

O IPA sem assinatura precisa ser reassinado no SideStore ou Sideloadly.
A conferência física de imagem, áudio e desempenho é feita após instalar.
Fontes das bibliotecas e avisos estão em THIRD_PARTY_NOTICES.txt.
