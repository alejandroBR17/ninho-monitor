# Restaurar o Ninho Monitor

## Ferramentas

- Git para clonar o repositório.
- Flutter estável compatível com Dart >=3.10, Android SDK e JDK 17 para o aplicativo.
- Go >=1.26 para a ponte (o pacote atual foi compilado com Go 1.27.4).

## Android

```sh
cd apps/android
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

As dependências estão descritas em pubspec.yaml/pubspec.lock. O SDK local e saídas de build não são versionados. Os arquivos iOS foram preservados, mas o acesso já utilizado no iPhone é a PWA servida pela ponte; não foi entregue um IPA.

**Assinatura:** para atualizar a instalação existente sem perder a identidade do app, será necessária a chave de assinatura original. Ela foi deliberadamente mantida fora deste repositório. O projeto existente usa a configuração de assinatura debug também no build pessoal release; um novo computador pode gerar outro certificado. Não publique esse APK sobre a versão instalada sem conferir o certificado. Guarde o keystore original em um backup privado separado, com acesso restrito. Nenhuma chave está incluída aqui.

## Ponte Windows e visualizador web

```sh
cd bridge
go test -race ./...
```

Em PowerShell, para gerar o executável Windows:

```powershell
$env:GOOS = 'windows'
$env:GOARCH = 'amd64'
$env:CGO_ENABLED = '0'
go build -trimpath -ldflags='-s -w' -o JortanPonte.exe .
```

O nome do executável atual foi preservado para os atalhos existentes. HTML, CSS, JavaScript e hls.js de `bridge/web/` são incorporados no executável. Coloque os atalhos `.cmd`, FFmpeg e cloudflared na mesma pasta. Fontes oficiais, versões e hashes estão em `bridge/COMPONENTES.json`; as licenças acompanham o projeto. Para o endereço fixo, instale Tailscale no Windows e use o atalho `INICIAR-COM-ENDERECO-FIXO.cmd`. Não é necessário comprar domínio.

Leia `bridge/README.md` e `bridge/VALIDACAO.md` para configuração, histórico, modos, notificações e limites dos testes. A configuração protegida do notebook e as permissões de notificação dos aparelhos não estão no GitHub. Uma instalação nova requer configuração local; não envie senhas pelo chat.

## Site de download

`website/dist/` contém HTML, CSS e scripts do site. Arquivos APK/ZIP e partes binárias de download não foram incluídos no Git; os manifestos de lançamento foram preservados como referência. Para republicar downloads, gere os pacotes e as partes com hashes atualizados. Os metadados privados de hospedagem e credenciais de publicação também não estão neste repositório. O site atualmente em produção não foi modificado por este backup; sua audiência permanece privada.

## Validar o backup

`docs/SOURCE-SNAPSHOT.json` registra versões e hashes dos arquivos originais copiados. Os arquivos de documentação adicionados organizam a restauração; o código funcional foi preservado sem renomear pacotes ou armazenamento protegido. Mantenha cópia local deste repositório e envie futuros commits para o GitHub: mudanças no notebook não são sincronizadas automaticamente.


## Publicação para portfólio

O proprietário autorizou a publicação pública do código. Os exemplos de IP foram substituídos por um endereço fictício e o contato VAPID aponta ao repositório público. Os identificadores de pacote, diretórios de armazenamento e assinatura das instalações existentes foram preservados. Essas alterações não implantam uma nova versão nos aparelhos em uso.
