<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.svg">
    <img src="docs/images/logo-light.svg" alt="Brainagram" width="300">
  </picture>
</h1>

**Diagramas de software que contam uma história.**
Escreva o fluxo em texto, dê play e veja as mensagens percorrerem as setas — passo a passo.

[English](README.md) · **Português (Brasil)**

[![CI](https://github.com/LucasNasc/brainagram/actions/workflows/ci.yml/badge.svg)](https://github.com/LucasNasc/brainagram/actions/workflows/ci.yml)
[![Versão](https://img.shields.io/badge/vers%C3%A3o-0.1.0-7c5cff.svg)](CHANGELOG.md)
[![Testes](https://img.shields.io/badge/testes-350%2B%20passando-2f9e4f.svg)](#desenvolvimento)
[![Licença: MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-7c5cff.svg)](LICENSE)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.pt-BR.md)
<br>
![Elixir](https://img.shields.io/badge/Elixir-1.15%2B-4e2a8e.svg)
![Phoenix](https://img.shields.io/badge/Phoenix-1.8-f05423.svg)
![Phoenix LiveView](https://img.shields.io/badge/LiveView-1.2-f05423.svg)
![Idiomas](https://img.shields.io/badge/idiomas-7-0c9b8c.svg)
[![PRs bem-vindos](https://img.shields.io/badge/PRs-bem--vindos-0c9b8c.svg)](CONTRIBUTING.pt-BR.md)

</div>

<p align="center">
  <img src="docs/images/checkout.pt-BR.gif" alt="Diagrama de sequência animado no modo escuro: um checkout tocando passo a passo, com o payload da requisição se abrindo enquanto a mensagem percorre a seta" width="760">
</p>

---

## Por quê

Todo diagrama de sequência é explicado em voz alta: *"primeiro o cliente chama a
API, aí ela publica um evento…"*. É essa narração que dá sentido ao diagrama — e
ela se perde quando a reunião acaba.

O Brainagram transforma a narração em artefato. A **linha do tempo faz parte do
diagrama**: você agrupa as mensagens em passos, e o diagrama os toca em ordem,
com um impulso percorrendo cada seta. Feito para onboarding, RFCs, postmortems e
revisões de design — onde alguém apontaria para uma imagem parada e diria
"e aí…".

## Funcionalidades

- **O texto é a fonte da verdade.** Uma DSL pequena (`.brain`) descreve o
  diagrama; o layout é calculado, nunca guardado. O diff é legível e revisável
  num PR.
- **Linha do tempo animada.** Play, pausa, arrastar a posição, passo a passo,
  repetição, velocidade.
- **Dois tipos de diagrama.** *Sequência* (raias, barras de ativação, notas) e
  *arquitetura* (camadas, grupos e roteamento ortogonal).
- **Edição visual sobre o texto.** Arraste nós, conecte, renomeie, troque o tipo
  da seta, apague — cada gesto é uma edição cirúrgica do texto, então
  comentários e formatação sobrevivem.
- **Payloads.** Anexe o que a mensagem carrega (corpo JSON, SQL, cabeçalhos)
  num chip sob a seta. Ele expande enquanto a mensagem toca e pode ser fixado
  aberto com um clique.
- **Organizar setas.** Um clique reorganiza um diagrama de arquitetura para
  minimizar cruzamentos — de 8 para 1 no exemplo abaixo.
- **Importa** `sequenceDiagram` do Mermaid, diagramas de sequência e de
  componentes do PlantUML, arquivos `.brain` e pacotes do Brainagram.
- **Exporta** SVG, PNG (2×), GIF animado (HD ou leve), `.brain` e pacotes
  `.json` de projetos inteiros.
- **Projetos.** Uma área de gestão para separar os diagramas em projetos com
  cor, com busca, filtros, miniaturas e atualização ao vivo.
- **Paleta de comandos** (`Ctrl/⌘ K`), atalhos de teclado, desfazer/refazer que
  cobre texto e canvas.
- Interface em **7 idiomas** — português do Brasil, inglês, chinês
  simplificado, russo, italiano, japonês e hindi —, temas claro e escuro.
- **Linha de comando** para renderizar e formatar `.brain` no CI — sem navegador.

<p align="center">
  <img src="docs/images/platform.pt-BR.gif" alt="Diagrama de arquitetura animado no modo escuro: o tráfego passa pelos grupos Borda, Aplicação e Dados ao longo de setas ortogonais" width="460">
</p>

## Começando

**Requisitos:** Elixir 1.15+ e Erlang/OTP 25+ (o CI usa Elixir 1.18 / OTP 27 e 1.20 / OTP 29, a da imagem de produção) e
PostgreSQL (o CI usa o 16).

```bash
git clone https://github.com/LucasNasc/brainagram.git
cd brainagram

# Postgres para desenvolvimento (pule se já tem um em localhost:5432)
docker run -d --name brainagram-pg -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:16

mix setup          # dependências, banco, migrações, exemplos, assets
mix phx.server     # http://localhost:4000
```

O banco de desenvolvimento usa `postgres` / `postgres` em `localhost` (veja
`config/dev.exs`). O `mix setup` também roda o `priv/repo/seeds.exs`, que cria
os diagramas de exemplo pelo mesmo barramento de comandos que a interface usa.

## Usando o Brainagram

### 1. A área de gestão (`/`)

Seus diagramas, em cards com miniatura.

- **Projetos** à esquerda: crie com **+**, dê nome e cor. *Todos os diagramas*
  e *Sem projeto* estão sempre lá. Excluir um projeto nunca apaga os diagramas —
  eles vão para *Sem projeto*.
- **Novo diagrama** pede nome, tipo (sequência ou arquitetura) e projeto, e
  abre o editor com um exemplo curto para começar.
- O menu **⋯** de cada card: abrir, renomear, mover para projeto, duplicar,
  tornar público/privado, baixar `.brain`, excluir.
- Busca, filtro por tipo e ordenação; o filtro fica na URL, então dá para
  favoritar e compartilhar a visão de um projeto.
- **Importar** e **Exportar** — veja [Importar e exportar](#importar-e-exportar).

O **Editor livre** (`/new`) abre o editor sem salvar nada até você apertar
**Salvar**.

### 2. O editor (`/d/:slug`)

```
┌──────────── código ────────────┬──────────── canvas ────────────┬─ passos ┐
│ diagram sequence "Checkout"    │  ○ Cliente    ○ API   ○ Orders │ 1 ...   │
│ user -> api : POST /orders     │      ●─────────▶               │ 2 ...   │
│   payload: {"items": 3}        │                                │ 3 ...   │
└────────────────────────────────┴───────── ▶ timeline ──────────┴─────────┘
```

- **Código** à esquerda: o diagrama recompila enquanto você digita. O erro
  aponta a linha, e o último diagrama válido continua na tela. O autocompletar
  sugere tipos de nó, palavras-chave, setas e ids existentes.
- **Canvas** no meio, com dois modos (`E` alterna):
  - **Editar** — arraste nós, puxe da alça de um nó para conectar, duplo clique
    renomeia um nó ou o rótulo de uma seta, duplo clique numa área vazia cria um
    nó, selecione uma seta para trocar o tipo ou pôr um payload (`P`).
  - **Mover** — arrastar move a tela; o clique ainda abre e fecha payloads.
- **Passos** à direita: clique em um para ir até ele.
- **Barra do canvas:** *Nó*, *Conectar*, *Organizar setas* (arquitetura),
  *Soltar posições* (esquece as posições arrastadas e volta ao automático).

### Atalhos de teclado

| Tecla | Ação |
|---|---|
| `Espaço` | tocar / pausar (segure e arraste para mover a tela) |
| `←` `→` | passo anterior / próximo |
| `F` | enquadrar o diagrama |
| `R` | reiniciar |
| `E` | alternar Editar / Mover |
| `Ctrl/⌘ K` | paleta de comandos |
| `Ctrl/⌘ Z`, `Ctrl/⌘ Shift Z` | desfazer / refazer (texto e canvas) |
| `Shift Alt F` | formatar o código |
| `F8` | ir para o próximo erro |
| `Alt ↑` `Alt ↓` | mover o bloco `step` atual para cima / baixo |
| `Enter` | renomear o nó / a seta selecionada |
| `P` | editar o payload da seta selecionada |
| `Delete` | apagar a seleção |
| `Esc` | cancelar (também cancela a gravação de um GIF) |

## A DSL

Um diagrama é texto puro. Nós usados em setas são declarados automaticamente —
`a -> b` já é um diagrama válido — e, sem nenhum `step`, cada mensagem vira um
passo.

```text
diagram sequence "Checkout"          # ou: diagram architecture "Plataforma"

actor       user   "Cliente"         # <tipo> <id> "<rótulo>"
participant api    "API Gateway"
service     orders "Order Service"
database    db     "PostgreSQL"

step "Cliente confirma o pedido" {   # um passo da animação
  user -> api : POST /orders
    payload """
    {"items": [{"sku": "A-1", "qty": 2}]}
    """
  api -> orders : CreateOrder
  note over user, api : notas se ancoram em um ou mais nós
}
```

**Setas**

| Seta | Significado |
|---|---|
| `a -> b` | chamada síncrona (abre barra de ativação) |
| `a --> b` | retorno / resposta (fecha a barra) |
| `a ->> b` | assíncrona, fire-and-forget |
| `a -x b` | falha / timeout |

**Tipos de nó:** `actor`, `participant`, `service`, `component`, `database`,
`queue`, `external`, `system`, `node`, `boundary`.

**Blocos e linhas**

| Sintaxe | O que faz |
|---|---|
| `step "…" { … }` | um passo da linha do tempo |
| `group "…" { … }` | agrupa nós (uma VPC, um bounded context…) |
| `note over a, b : texto` · `note left of a : …` · `note right of a : …` | anotação |
| `payload: …` (logo abaixo de uma mensagem) | o que a mensagem carrega; várias linhas se somam |
| `payload """ … """` | payload de várias linhas — texto cru, `#` e `//` são conteúdo aqui |
| `layout { api at (420, 680) }` | posições fixadas ao arrastar (o canvas escreve por você) |
| `#` ou `//` | comentário (aspas são respeitadas) |

Também valem apelidos em português, como `diagram arquitetura` e `dados:`.
Mais exemplos em [`docs/examples/`](docs/examples).

## Importar e exportar

| Formato | Exportar | Importar |
|---|---|---|
| `.brain` (um diagrama, o texto da DSL) | editor → *Exportar → Arquivo .brain*; card → *Baixar .brain* | área de gestão → *Importar*; editor → *Importar* |
| Pacote `.json` (diagramas + projetos) | área de gestão → *Exportar* (o projeto aberto, *Sem projeto* ou tudo) | área de gestão → *Importar* (os projetos são recriados; um de mesmo nome é reaproveitado) |
| `sequenceDiagram` do Mermaid | — | nos dois diálogos de importar |
| PlantUML (sequência → sequência, componentes → arquitetura) | — | nos dois diálogos de importar |
| SVG, PNG 2× | editor → *Exportar* | — |
| GIF (HD 2× ou leve 1×) | editor → *Exportar* | — |

O que não converte na importação vira comentário no topo do código, nunca uma
falha. Importar vários arquivos de uma vez mostra, por arquivo, o que entrou e o
que não entrou (com a linha do erro).

## Linha de comando

O domínio roda sem Phoenix e sem banco, então dá para renderizar e formatar
diagramas no CI:

```bash
mix brainagram.render docs/examples/checkout.pt-BR.brain                 # → .svg ao lado
mix brainagram.render docs/examples/checkout.pt-BR.brain -o out/c.svg
mix brainagram.render docs/examples/checkout.pt-BR.brain --format png --scale 2   # precisa de resvg, rsvg-convert ou ImageMagick

mix brainagram.fmt                       # formata todos os **/*.brain
mix brainagram.fmt --check-formatted     # para CI: falha se algo mudaria
```

As imagens deste README foram geradas com `mix brainagram.render`.

## Como funciona

```
        ┌─────────────── servidor (Elixir) ───────────────┐   ┌─ navegador (JS) ─┐
texto → │ Parser → AST → Layout → Scene (posições, paths) │ → │ SVG → Timeline   │
        └──────────────────────────────────────────────────┘   └──────────────────┘
              roda enquanto você digita (debounce)                  60 fps, local
```

- **O servidor decide *onde*** — o layout é a parte difícil e cheia de regra, e
  em Elixir é código puro e testável. A `Scene` traz coordenadas absolutas e o
  path SVG de cada seta.
- **O navegador só desenha e toca.** Play, arrastar a posição, zoom e mover a
  tela nunca tocam o servidor. `seek(t)` é uma função pura do tempo.
- **Arquitetura em camadas com CQRS.** `web → application → domain → shared`;
  a infraestrutura (Ecto, PubSub) implementa portas e só é amarrada em
  `config/config.exs`. A regra é verificada por teste
  (`test/brainagram/architecture_test.exs`). Toda mudança passa por
  `Bus.dispatch/2`, toda leitura por `Bus.ask/2`.

```
lib/brainagram/
├── shared/                         sem regra de negócio
├── domain/diagramming/             regra pura — sem Ecto, sem Phoenix
│   ├── diagram.ex  project.ex      agregados
│   ├── dsl/                        parser, printer, editor cirúrgico
│   ├── layout/                     sequência, arquitetura, roteador, organizar setas
│   ├── authoring.ex                gestos do canvas como edições de texto
│   └── import/  render/            importação Mermaid/PlantUML, SVG no servidor
├── application/                    comandos, queries, handlers, read models
└── infrastructure/                 repositórios/leitores Ecto, PubSub, catálogo
lib/brainagram_web/                 LiveViews, controllers, componentes
assets/                             CSS escrito à mão (tokens de design) e hooks JS
```

As decisões de projeto estão documentadas em
[`docs/ARQUITETURA.md`](docs/ARQUITETURA.md) e
[`docs/specs/001-autoria-visual.md`](docs/specs/001-autoria-visual.md).

## Desenvolvimento

```bash
mix test            # testes de unidade, de propriedade (StreamData) e de LiveView
mix precommit       # compila com warnings como erro, formata, testa
```

A maioria dos testes não precisa de banco: domínio e aplicação são testados com
repositórios em memória. O CI (`.github/workflows/ci.yml`) confere
dependências sem uso, formatação, warnings (como erro) e se a extração do
gettext está em dia, e depois roda a suíte inteira contra o Postgres.

**Convenções que valem saber** (a lista completa está no [`AGENTS.md`](AGENTS.md)):

- **CSS escrito à mão** — sem Tailwind. Use os tokens de
  `assets/css/tokens.css`; componentes em BEM com o prefixo `ba-`; regras do
  canvas em `diagram.css` começam com `.bg-`.
- **Todo texto da interface é traduzido.** O português é a chave:
  `gettext("Salvar")`. Depois de mudar textos, rode
  `mix gettext.extract --merge` e preencha os `msgstr` vazios de
  `priv/gettext/<idioma>/LC_MESSAGES/default.po` em todos os idiomas (`en`,
  `zh`, `ru`, `it`, `ja`, `hi`) — um teste falha com tradução faltando ou
  "fuzzy". No JavaScript, use `t("…")` e ponha a chave em todos os
  dicionários de `assets/js/brainagram/locales/`.
- **Comando novo?** Struct em `application/commands/` declarando o handler →
  transição no agregado devolvendo `{:ok, agregado, eventos}` → evento em
  `domain/diagramming/events.ex` → handler → teste com o repositório em memória.

## Deploy

O Brainagram traz um **Dockerfile** de produção (um release Elixir sobre Debian
slim). Por padrão o container também roda o próprio **PostgreSQL**, ouvindo só
dentro do container, com os dados em `/app/data` — monte um volume persistente
aí. Ao subir, ele inicializa o banco (na primeira vez), aplica as migrações
pendentes, sobe o servidor na porta `4000` e responde `GET /health`.

```bash
docker build -t brainagram .
docker run -p 4000:4000 -v brainagram-data:/app/data   -e SECRET_KEY_BASE="$(mix phx.gen.secret)"   -e PHX_HOST=localhost   brainagram
```

| Variável | Obrigatória | Para quê |
|---|---|---|
| `SECRET_KEY_BASE` | sim | no mínimo 64 bytes — gere com `mix phx.gen.secret` |
| `PHX_HOST` | sim | o host público, sem `https://` (padrão `example.com`) |
| `DATABASE_URL` | não | um PostgreSQL **externo** (`ecto://USUARIO:SENHA@HOST/BANCO`); definida, o embutido não sobe |
| `PORT` | não | padrão `4000` |
| `POOL_SIZE` | não | conexões com o banco, padrão `10` |
| `ECTO_IPV6` | não | `true` para conectar por IPv6 |

> **TODO — banco externo.** O PostgreSQL embutido é o ponto de partida: uma
> instância, um container. Passar para um banco externo (um PostgreSQL do
> Coolify, um serviço gerenciado…) é só definir `DATABASE_URL` e levar os dados
> com `pg_dump`/`pg_restore`; procure `TODO(external-db)` no `Dockerfile` e em
> `rel/overlays/bin/start`.

Sem Docker: `MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix release`, e
depois `_build/prod/rel/brainagram/bin/migrate` e `.../bin/server`.

### Coolify

1. **Aplicação**: *+ New → Private Repository (GitHub App)*, branch `main`,
   **Build Pack: Dockerfile**, **Ports Exposes: `4000`** e o seu **Domain**
   (`https://…`). O proxy cuida do HTTPS.
2. **Persistent Storage** → *Volume Mount* com destino **`/app/data`**. Sem
   isso o banco se perde a cada deploy.
3. **Advanced → Consistent Container Names: ligado.** Assim o Coolify para o
   container antigo antes de subir o novo. Dois containers nunca podem rodar o
   banco embutido ao mesmo tempo — o script de início se recusa (espera e
   depois falha o deploy), mas a opção evita o deploy falho.
4. **Variáveis de ambiente**: `SECRET_KEY_BASE` e `PHX_HOST` (o domínio sem
   `https://`).
5. **Auto Deploy** (já vem ligado com o GitHub App): cada push na `main`
   constrói a imagem e troca o container. O GitHub Actions só roda os testes
   (não segura o deploy), então mantenha a `main` verde.

A imagem tem `HEALTHCHECK` em `/health`, então um deploy cujas migrações
falhem nunca recebe tráfego. Faça backup do volume `/app/data` (ou rode
`pg_dump` dentro do container) com frequência.

> **Atenção:** ainda não há contas de usuário — todo diagrama é visível para
> quem acessar a instância. No Coolify, ative a **HTTP Basic Authentication**
> nas configurações da aplicação, ou mantenha-a numa rede privada. Contas e um
> modo só no navegador estão especificados em
> [`docs/specs/002-contas-e-modo-local.md`](docs/specs/002-contas-e-modo-local.md).

## Contribuindo

Contribuições são muito bem-vindas: código, traduções, exemplos, documentação
e revisões. Comece pelo **[guia de contribuição](CONTRIBUTING.pt-BR.md)**, que
explica o ambiente, as regras do projeto, o padrão de commits e como abrir um
PR. Em resumo:

1. Rode `mix precommit` e garanta que passa.
2. Escreva testes para mudanças de comportamento (as suítes existentes mostram o estilo).
3. Respeite a regra de camadas: o domínio nunca referencia Ecto, Phoenix ou a
   infraestrutura.

| | |
|---|---|
| [Guia de contribuição](CONTRIBUTING.pt-BR.md) | ambiente, regras, traduções, commits e PRs |
| [Código de Conduta](CODE_OF_CONDUCT.pt-BR.md) | como nos tratamos (Contributor Covenant 2.1) |
| [Segurança](SECURITY.md) | como relatar uma vulnerabilidade em particular |
| [Suporte](SUPPORT.md) | onde tirar dúvidas |
| [Changelog](CHANGELOG.md) | o que mudou |

Nunca contribuiu com open source? Procure as issues marcadas como
`good first issue`. Revisar a tradução de um idioma que você fala também é um
ótimo começo.

Ideias no roadmap: contas de usuário, página pública somente leitura e embed,
exportar vídeo, colaboração em tempo real, balões de payload nas setas de
arquitetura.

## Licença

[MIT](LICENSE) © Lucas Nascimento e contribuidores do Brainagram.
