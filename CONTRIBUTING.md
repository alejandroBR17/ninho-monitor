# Contribuindo

Comece pelo [README](README.md), [arquitetura](docs/ARCHITECTURE.md) e [guia de restauração](docs/RESTORE.md). Antes de alterar interfaces, leia [DESIGN.md](docs/DESIGN.md) e as instruções do subprojeto.

## Verificar uma alteração

```sh
cd bridge
go test -race ./...
```

```sh
cd apps/android
flutter pub get
flutter test
```

Use os testes relacionados à mudança. Não trate uma simulação como validação de hardware. Para correções de protocolo, inclua uma reprodução sintética sem credenciais reais; para interface, descreva como verificou tamanhos móveis e os estados de carregamento, erro e desconexão.

## Pull requests

Explique o problema, o comportamento final e a validação executada. Preserve parada PTZ, autenticação e armazenamento protegido. Não altere identificadores de pacote ou diretórios de dados apenas para mudar o nome visível do produto.

Não envie configurações reais, chaves, tokens, imagens domésticas ou logs brutos de autenticação. Os exemplos de demonstração são fictícios. Se identificar uma falha de segurança, não publique detalhes exploráveis ou credenciais em uma issue; peça primeiro um canal privado ao mantenedor, sem incluir esses dados.

O código próprio usa a [licença MIT](LICENSE). Preserve créditos e licenças de dependências e indique a origem de qualquer código de terceiros adicionado.
