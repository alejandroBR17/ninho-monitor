# Dependências e licenças de terceiros

A licença MIT da raiz aplica-se ao código próprio do Ninho Monitor. Ela não substitui as licenças dos componentes de terceiros.

| Componente | Referência preservada |
| --- | --- |
| Dependências Flutter / media_kit | [Avisos do aplicativo](apps/android/THIRD_PARTY_NOTICES.md), pubspec.yaml e pubspec.lock |
| Playwright · captura de demonstração | Dependência de desenvolvimento em [tools/package.json](tools/package.json), licença Apache-2.0 da distribuição original |
| hls.js | [Licença incluída](bridge/web/vendor/HLS-LICENSE.txt) |
| webpush-go | [Licença incluída](bridge/licenses/WEBPUSH-LICENSE.txt) |
| golang-jwt | [Licença incluída](bridge/licenses/JWT-LICENSE.txt) |
| golang.org/x/crypto | [Licença incluída](bridge/licenses/X-CRYPTO-LICENSE.txt) |
| FFmpeg, cloudflared e ferramentas de distribuição | [Versões e fontes oficiais](bridge/COMPONENTES.json); executáveis externos não incluídos neste repositório |

Ao distribuir binários, reúna também os avisos e obrigações correspondentes à versão e à configuração dos componentes usados. Não remova cabeçalhos de licença de arquivos vendorizados.
