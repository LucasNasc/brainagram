<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.svg">
    <img src="docs/images/logo-light.svg" alt="Brainagram" width="220">
  </picture>
</p>

# Contribuindo com o Brainagram

[English](CONTRIBUTING.md) · **Português (Brasil)**

Obrigado por querer ajudar! O Brainagram é um projeto pequeno, então cada
issue, tradução, revisão e pull request faz diferença de verdade. Este guia
explica como preparar o ambiente e o que uma contribuição precisa ter para ser
aceita rápido.

Ao participar, você concorda em seguir o nosso
[Código de Conduta](CODE_OF_CONDUCT.pt-BR.md).

## Sumário

- [Formas de contribuir](#formas-de-contribuir)
- [Dúvidas](#dúvidas)
- [Relatando bugs](#relatando-bugs)
- [Sugerindo funcionalidades](#sugerindo-funcionalidades)
- [Sua primeira contribuição de código](#sua-primeira-contribuição-de-código)
- [Ambiente de desenvolvimento](#ambiente-de-desenvolvimento)
- [Onde fica cada coisa](#onde-fica-cada-coisa)
- [Regras do projeto](#regras-do-projeto)
- [Traduções](#traduções)
- [Mensagens de commit](#mensagens-de-commit)
- [Pull requests](#pull-requests)
- [Falhas de segurança](#falhas-de-segurança)
- [Contribuições com ajuda de IA](#contribuições-com-ajuda-de-ia)

## Formas de contribuir

Não é preciso escrever Elixir para ajudar:

- **Relatar um bug** ou um diagrama que renderiza mal (o fonte `.brain` é a
  reprodução perfeita).
- **Melhorar uma tradução.** A interface fala sete idiomas, e os que não são
  português nem inglês começaram com tradução automática, então revisões de
  falantes nativos são muito bem-vindas.
- **Compartilhar exemplos.** Diagramas de fluxos reais viram ótimos casos de
  teste e entradas do catálogo.
- **Melhorar a documentação** (os READMEs, este guia, `docs/`).
- **Revisar pull requests** e testá-los localmente.
- **Escrever código**: correções, melhorias de layout, importadores, recursos
  novos na DSL.

## Dúvidas

Por favor, não use issues para dúvidas. Veja em [SUPPORT.md](SUPPORT.md) onde
perguntar.

## Relatando bugs

1. Confira se está na `main` mais recente e procure nas
   [issues existentes](../../issues?q=is%3Aissue), inclusive nas fechadas.
2. Abra uma issue com o modelo **Bug report** e preencha todos os campos. O
   anexo mais útil é o **menor fonte da DSL que reproduz o problema**. Use
   *Exportar → Arquivo .brain* no editor, ou cole o texto.
3. Inclua capturas de tela, navegador e sistema operacional, e qualquer erro do
   console do navegador ou do log do servidor.

Nunca relate falhas de segurança numa issue pública. Veja
[Falhas de segurança](#falhas-de-segurança).

## Sugerindo funcionalidades

Abra uma issue com o modelo **Feature request**. Descreva o *problema* antes
da solução. "Não consigo mostrar que uma chamada é refeita" rende uma conversa
melhor que "adicione a palavra-chave `retry`". Para mudanças grandes, como um
tipo novo de diagrama, uma mudança na DSL ou uma dependência nova, **espere o
aval de quem mantém o projeto antes de escrever o código**, para ninguém
perder trabalho.

## Sua primeira contribuição de código

Procure issues com as etiquetas
[`good first issue`](../../labels/good%20first%20issue) ou
[`help wanted`](../../labels/help%20wanted). Comente na issue avisando que vai
pegá-la, para duas pessoas não fazerem o mesmo trabalho. Se travar, pergunte na
própria issue. PRs inacabados também são bem-vindos; abra-os como
**rascunho** (*draft*).

## Ambiente de desenvolvimento

**Requisitos:** Elixir 1.15+ e Erlang/OTP 25+ (o CI usa Elixir 1.18 / OTP 27) e
PostgreSQL (o CI usa o 16).

```bash
# antes, faça o fork de https://github.com/LucasNasc/brainagram no GitHub; depois:
git clone https://github.com/<seu-usuario>/brainagram.git
cd brainagram
git remote add upstream https://github.com/LucasNasc/brainagram.git

# Postgres para desenvolvimento (pule se já tiver um em localhost:5432)
docker run -d --name brainagram-pg -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:16

mix setup          # dependências, banco, migrações, exemplos, assets
mix phx.server     # http://localhost:4000
```

No dia a dia:

```bash
mix test                          # a suíte inteira (a maior parte nem toca no banco)
mix test test/caminho/do_test.exs # um arquivo
mix test --failed                 # só o que falhou da última vez
mix precommit                     # o que o CI confere: warnings como erro, deps sem uso, formato, testes
```

Se mudar CSS ou JS com o servidor parado, `mix assets.build` refaz os pacotes.

## Onde fica cada coisa

```
lib/brainagram/
├── shared/                 sem regra de negócio
├── domain/diagramming/     regras puras: parser/printer da DSL, layout, roteamento, render
├── application/            comandos, consultas e seus handlers (CQRS)
└── infrastructure/         repositórios/leitores Ecto, PubSub, catálogo de exemplos
lib/brainagram_web/         LiveViews, controllers, componentes, idioma
assets/css/                 CSS escrito à mão, com tokens de design
assets/js/                  canvas, timeline, hooks, dicionários de tradução
priv/gettext/               traduções
test/                       espelha lib/; test/support tem os adaptadores em memória
```

O desenho completo está na seção [Como funciona](README.pt-BR.md#como-funciona)
do README e em [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md).

Receitas comuns:

- **Comando ou consulta nova**: struct em `application/commands/` (ou
  `queries/`) declarando o handler → transição no agregado devolvendo
  `{:ok, agregado, eventos}` → evento em `domain/diagramming/events.ex` →
  handler → teste com o repositório em memória.
- **Sintaxe nova na DSL**: parser em `domain/diagramming/dsl/`, o printer
  correspondente (o fonte precisa ir e voltar igual), teste do parser e a seção
  *A DSL* do README.
- **Mudança de layout**: acrescente um caso aos testes de layout. Os testes de
  qualidade (`layout/quality_test.exs`) contam cruzamentos e sobreposições,
  então confira que os números não pioram.
- **Mudou o visual?** Refaça os GIFs de demonstração do README (modo escuro,
  gravados pelo próprio exportador de GIF do app) com o servidor rodando:
  `node docs/tools/record_gifs.mjs` (`PORT=` e `BROWSER=` se precisar; Node 22+
  e Chrome ou Edge).

## Regras do projeto

Elas são conferidas na revisão, e a maioria também por testes. A lista
completa, para pessoas e agentes de código, está em [`AGENTS.md`](AGENTS.md).

- **Regra das camadas.** O domínio nunca referencia Ecto, Phoenix nem
  `Brainagram.Infrastructure`. Infraestrutura nova entra por uma porta e é
  ligada em `config/config.exs`. `test/brainagram/architecture_test.exs`
  garante isso.
- **O texto é a fonte da verdade.** Gestos no canvas viram edições cirúrgicas
  no texto da DSL. Não guarde estado do diagrama que não possa ser escrito de
  volta como texto.
- **CSS puro, sem framework.** Use os tokens de `assets/css/tokens.css` e
  nunca escreva cores fixas no código. Componentes em BEM com o prefixo `ba-`,
  e estado em atributos (`aria-pressed`, `data-state`). As regras do canvas
  em `diagram.css` começam com `.bg-`.
- **Nada de dependência nova** sem discutir antes numa issue.
- **Teste para mudança de comportamento.** Lógica de domínio ganha teste
  unitário ou de propriedade (StreamData). Interface ganha teste de LiveView
  usando os IDs dos elementos do template.
- **A documentação também é testada.** `test/brainagram/project_docs_test.exs`
  confere se os badges do README (versão, quantidade de testes, idiomas,
  versões do Elixir/Phoenix) batem com o código, e se os links entre os
  documentos funcionam. Se ele falhar depois que você criou testes ou subiu
  uma versão, atualize o badge nos dois READMEs.

## Traduções

O Brainagram fala português do Brasil (padrão e idioma de origem), inglês,
chinês simplificado, russo, italiano, japonês e hindi.

- **Elixir/HEEx**: todo texto visível passa por
  `gettext("Texto em português")`. O texto em português *é* a chave.
- Depois de criar ou mudar textos, rode `mix gettext.extract --merge` e preencha
  os `msgstr` vazios de `priv/gettext/<idioma>/LC_MESSAGES/default.po` em
  **todos** os idiomas. As formas de plural mudam: chinês e japonês têm uma,
  e russo tem três. `test/brainagram_web/locale_test.exs` falha com qualquer
  tradução faltando ou `fuzzy`.
- **JavaScript**: `t("Texto em português", {vars})`, pondo a chave em todos os
  dicionários de `assets/js/brainagram/locales/`.
- **Revisar um idioma** é uma ótima primeira contribuição. Abra uma issue com o
  modelo **Translation** ou mande um PR que mexa só nos arquivos `.po` e
  `locales/*.js` daquele idioma.

Para adicionar um idioma novo, siga a lista em
[`AGENTS.md`](AGENTS.md#internationalization-pt-br-en-zh-ru-it-ja-hi).

## Mensagens de commit

Seguimos o [Conventional Commits](https://www.conventionalcommits.org/pt-br/v1.0.0/)
(em inglês, como o código):

```
<tipo>(<escopo opcional>): <resumo curto no imperativo>

<corpo opcional: o quê e por quê, não como>
```

Tipos comuns: `feat`, `fix`, `docs`, `i18n`, `refactor`, `perf`, `test`,
`build`, `ci`, `chore`. Mudanças incompatíveis levam `!`
(`feat(dsl)!: rename the payload keyword`). Exemplo:

```
fix(layout): keep return arrows inside the activation bar
```

## Pull requests

1. Faça um fork e crie um branch a partir da `main`
   (`fix/payload-overflow`, `feat/plantuml-notes`…).
2. Mantenha o PR focado: uma correção ou uma funcionalidade. Faxinas sem
   relação vão num PR separado.
3. Rode **`mix precommit`** e confira que passa.
4. Atualize a documentação e o [`CHANGELOG.md`](CHANGELOG.md) (em *Unreleased*)
   quando o comportamento mudar.
5. Abra o PR e preencha o modelo. Para mudanças visuais, inclua capturas de
   antes e depois ou um GIF (o editor exporta um).
6. O CI precisa estar verde. Alguém que mantém o projeto revisa, normalmente em
   até uma semana. Se ficar parado mais que isso, pode chamar no PR.

Os PRs entram com *squash and merge*, então o título do PR vira a mensagem do
commit. Escreva-o no formato do Conventional Commits.

Ao enviar uma contribuição, você concorda que ela fica sob a
[licença MIT](LICENSE) do projeto.

## Falhas de segurança

Por favor, **não** abra issue pública. Siga o [SECURITY.md](SECURITY.md).

## Contribuições com ajuda de IA

Usar ferramentas de IA tudo bem. O [`AGENTS.md`](AGENTS.md) existe justamente
para que agentes de código sigam as convenções do projeto. Mas a autoria
continua sendo sua: leia e entenda cada linha que enviar, confira que os testes
fazem sentido e esteja pronto para explicar as mudanças na revisão.

---

Obrigado por contribuir! 💜
