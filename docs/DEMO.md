# Demonstração local com vídeo sintético

As capturas do README mostram a interface reproduzindo uma cena fictícia de ambiente doméstico, gerada por IA. A imagem é transformada em vídeo com um pequeno deslocamento e transmitida por RTSP; a ponte a converte para HLS. Não é uma imagem da casa do proprietário nem comprovação de movimento físico.

## Preparar

Instale Go >=1.26, Python 3, FFmpeg e o executável MediaMTX, obtido de https://github.com/bluenviron/mediamtx/releases. O gerador usa uma configuração de teste incluída no projeto.

Em um terminal, na raiz do repositório:

```sh
python tools/scene-source.py --mediamtx /caminho/para/mediamtx
```

No Windows, use `python` e o caminho correspondente ao executável `.exe`.

## Abrir a ponte sem publicar túnel

Use uma pasta de dados separada da instalação doméstica. Não configure a fonte de teste no painel da ponte usada pela câmera real.

Em Bash, abra outro terminal na raiz do repositório:

```sh
cd bridge
LOCALAPPDATA="$(mktemp -d)" go run . --local-only --port 9096
```

Em PowerShell:

```powershell
cd bridge
$ninhoPreviousAppData = $env:LOCALAPPDATA
try {
  $env:LOCALAPPDATA = Join-Path $env:TEMP 'ninho-monitor-demo'
  go run . --local-only --port 9096
} finally {
  $env:LOCALAPPDATA = $ninhoPreviousAppData
}
```

A variável se aplica à sessão de demonstração; o exemplo PowerShell restaura o valor ao encerrar. A pasta de dados original não deve ser modificada.

Abra o link de configuração mostrado no terminal. Para a fonte de teste, use:

| Campo | Valor fictício |
| --- | --- |
| Host | `127.0.0.1` |
| Porta RTSP | `8554` |
| Usuário | `viewer` |
| Senha da fonte sintética | `test-only` |
| Caminho | `/onvif1` |

Crie uma senha remota de demonstração com pelo menos 12 caracteres. Os dados de teste acima não são credenciais de uma câmera real. Abra `http://127.0.0.1:9096`, entre e conecte o vídeo. Ative Dormir para observar eventos de movimento do padrão sintético.

O ambiente de teste não fornece uma câmera ONVIF física. É esperado que as operações PTZ não sejam liberadas por esse fluxo. Em Linux, a condição da bateria Windows aparece como não confirmada; isso preserva a distinção entre dado desconhecido e estado saudável.

## Reproduzir as capturas

O repositório inclui [tools/capture-portfolio.cjs](../tools/capture-portfolio.cjs), que usa Playwright e Chromium. Ele acessa somente o loopback, configura a fonte sintética, grava capturas da interface e não solicita permissão de notificações.

Em um terminal de desenvolvimento, instale o auxiliar e o navegador:

```sh
cd tools
npm ci
npx playwright install chromium
```

Informe a senha fictícia criada no painel e execute. No PowerShell:

```powershell
$env:NINHO_DEMO_PASSWORD = 'sua-senha-ficticia-da-demonstracao'
npm run capture
```

Em Bash:

```sh
NINHO_DEMO_PASSWORD='sua-senha-ficticia-da-demonstracao' npm run capture
```

Se já tiver Chromium instalado, `BROWSER_BIN` pode apontar para seu executável.

O comando espera que a ponte de demonstração esteja configurada. Informe a senha fictícia por `NINHO_DEMO_PASSWORD`; os exemplos do script não devem ser usados em produção. Os arquivos vão para `docs/media/`. Não execute a captura contra uma instalação doméstica real.

Ao terminar, interrompa a fonte e a ponte com Ctrl+C. Nenhum túnel ou endpoint público é necessário para esta demonstração.


## Fonte usada na apresentação

`docs/media/demo-room.webp` é a cena fictícia gerada para a apresentação. `tools/scene-source.py` a publica somente no loopback, com uma pequena animação e a identificação DEMO no vídeo quando a fonte de texto está disponível. Não recebe imagem de uma câmera real e não altera a implementação de produção.

As capturas principal e móvel focam o painel de vídeo, evitando áreas vazias da página. O histórico é um recorte de 440 px e fica recolhido no README. O padrão de barras de teste anterior continua disponível em `apps/android/scripts/rtsp_fixture.py` para diagnóstico técnico, mas não é a vitrine visual do projeto.
