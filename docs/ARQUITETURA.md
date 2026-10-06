# Brainagram — Arquitetura

> Diagramas de engenharia de software que **contam uma história**: em vez de uma
> imagem estática, uma linha do tempo que você dá play e as mensagens percorrem
> as setas.

Documento de decisões. Explica *por que* cada peça é como é, não só o que ela faz.

---

## 1. Posicionamento

O mercado de diagramas está lotado (draw.io, Excalidraw, Miro, Mermaid, D2, Lucid).
Competir em "mais formas, mais templates" é perder. O diferencial precisa ser
uma dimensão que ninguém ocupa bem: **tempo**.

| Ferramenta | Modelo mental | O que falta |
|---|---|---|
| draw.io / Lucid | tela infinita, formas livres | nenhuma noção de sequência temporal |
| Excalidraw | rascunho à mão livre | idem, e não é versionável |
| Mermaid / D2 | texto → imagem estática | imagem morta, sem narrativa |
| **Brainagram** | texto → **cena com timeline** | — |

O caso de uso real: onboarding de dev novo, RFC de arquitetura, postmortem,
apresentação de design. Em todos, alguém aponta para o diagrama e narra
"primeiro isso acontece, aí isso...". Hoje essa narração é oral e se perde.
Brainagram a torna um artefato.

**Consequência de produto:** o `step` não é enfeite, é a entidade central.
Um diagrama sem passos é um caso degenerado (cada mensagem vira seu próprio passo).

---

## 2. As duas decisões estruturais

### 2.1 O texto é a fonte da verdade

O banco guarda **só a DSL**, nunca geometria.

```
diagrams.source  →  texto da DSL   (persistido)
Scene            →  derivado       (compilado sob demanda)
```

Por quê:

- **Diff legível.** `git diff` de um diagrama vira um diff de código — revisável em PR.
- **Layout evolui sem migração.** Melhorou o algoritmo? Todos os diagramas melhoram.
- **Banco pequeno.** Um diagrama de 40 mensagens são ~2 KB de texto.
- **Import/export trivial.** Copiar e colar texto é o formato universal.

O custo é recompilar a cada carga. Medido: ~1 ms para um diagrama de 16 mensagens.

Isso tem uma consequência que atravessa o código inteiro: **título e tipo do
diagrama são derivados do fonte, nunca digitados**. O `RenameDiagram` da área de
gestão respeita isso: ele não grava um título num campo à parte, ele **edita a
DSL** — troca o texto entre aspas de `diagram <tipo> "<título>"`, pelo mesmo
trilho de edição cirúrgica dos gestos do canvas — e o título é re-derivado.

### 2.2 Layout no servidor, animação no cliente

```
        ┌──────────── servidor (Elixir) ────────────┐   ┌─── cliente (JS) ───┐
texto → │ Lexer/Parser → AST → Layout → Scene (IR)  │ → │ SVG → Timeline     │
        └───────────────────────────────────────────┘   └────────────────────┘
             roda ao digitar (debounce 220ms)              roda a 60fps, local
```

**Servidor decide onde e quando.** A `Scene` carrega coordenadas absolutas, o
`d` de cada path SVG e a lista de passos com durações.

**Cliente só desenha e toca.** Play, pause, scrub, zoom e pan não tocam no servidor.

Por que não LiveView puro para tudo? Porque cada `mousemove` de pan viraria um
round-trip de WebSocket. A 80 ms de latência, arrastar o canvas ficaria
intragável. LiveView é excelente para *estado*, não para *interação contínua a
60fps*. Usar LiveView onde ele brilha e um hook onde não brilha é o que torna a
escolha de stack defensável.

Por que não layout no cliente? Porque layout é a parte difícil e cheia de regra:
ordenação de camadas, colisão de rótulos, pilha de ativação. Em Elixir isso é
código puro e testável — `assert scene.activations == [...]` sem DOM, sem
headless browser.

---

## 3. Camadas

```
lib/brainagram/
├── shared/           utilitários sem regra de negócio (texto, relógio)
├── domain/           regra de negócio pura — sem Ecto, sem Phoenix
├── application/      CQRS: comandos, queries, handlers, read models
└── infrastructure/   Postgres, PubSub, catálogos
lib/brainagram_web/   LiveView, router, componentes
```

### A regra de dependência

As setas só apontam para dentro:

```
web  ──▶  application  ──▶  domain  ──▶  shared
                │                ▲
                └── portas ──────┘
infrastructure ─────────┘  (implementa as portas, não é conhecida por ninguém)
```

`infrastructure/` aparece **exatamente uma vez** fora de si mesma: em
`config/config.exs`, amarrando cada porta à sua implementação. Um `alias
Brainagram.Infrastructure...` dentro de `domain/` ou `application/` é violação —
e é verificado por teste (`architecture_test.exs`).

Isso não é purismo. É o que faz `mix test` da suíte de domínio rodar em
microssegundos sem Postgres de pé, e é o que permite trocar Ecto por outra coisa
sem abrir um único arquivo de regra.

### O que vive em cada camada

**`domain/diagramming/`** — o bounded context único, por enquanto.

| Arquivo | Papel |
|---|---|
| `diagram.ex` | o agregado. Transições retornam `{:ok, agregado, eventos}` |
| `value_objects/source.ex` | o fonte da DSL — **só existe se compilar** |
| `value_objects/{slug,title,kind,visibility}.ex` | invariantes de cada valor |
| `events.ex` | eventos de domínio, em tipos primitivos |
| `ports/diagram_repository.ex` | contrato de escrita (behaviour) |
| `ports/event_bus.ex` | contrato de publicação e assinatura |
| `dsl/`, `layout/`, `scene.ex` | serviços de domínio: o motor de diagramação |

O motor de DSL e layout está no **domínio**, não na infraestrutura. Decidir como
um diagrama de sequência se parece é a regra de negócio central deste produto —
não um detalhe técnico substituível.

**`application/`** — a fronteira transacional.

| Arquivo | Papel |
|---|---|
| `bus.ex` | porta de entrada única: `dispatch/2` e `ask/2` |
| `message.ex` | base de comandos e queries (validação schemaless) |
| `commands/`, `handlers/` | lado de escrita |
| `queries/`, `query_handlers/` | lado de leitura |
| `read_models/` | structs moldados para a tela |
| `ports/diagram_reader.ex` | contrato de leitura |

**`infrastructure/`** — adaptadores. `EctoDiagramRepository`,
`EctoDiagramReader`, `PubSubEventBus`, `StaticExampleCatalog`, o `Repo`.

Uma sutileza que vale explicar: a porta de **escrita** mora no domínio, a de
**leitura** mora na aplicação. O motivo é a direção da seta — o leitor devolve
*read models*, que são artefatos de aplicação; se o domínio declarasse esse
contrato, ele passaria a depender de uma camada acima. E isso reflete o próprio
CQRS: a leitura não passa pelo agregado, então não é assunto do domínio.

> O módulo OTP gerado pelo Phoenix foi renomeado de `Brainagram.Application`
> para `Brainagram.Runtime`, liberando o namespace `Brainagram.Application`
> para a camada de aplicação.

---

## 4. CQRS

O sabor adotado é **CQRS-lite**: caminhos de escrita e leitura separados, um
único Postgres. Sem event sourcing, sem consistência eventual, sem projeções
materializadas — por enquanto.

### Escrita

```
Bus.dispatch(ChangeDiagramSource, %{slug: ..., source: ...})
   │
   ├─ 1. valida a mensagem  (changeset schemaless)
   ├─ 2. handler carrega o agregado pela porta de escrita
   ├─ 3. agregado decide   → {:ok, agregado, eventos}
   ├─ 4. handler persiste   (só se houve evento)
   └─ 5. barramento publica os eventos — depois da escrita confirmada
```

Três decisões dentro desse fluxo:

**Lista de eventos vazia significa "nada mudou".** Salvar o mesmo fonte não gera
`UPDATE`, não mexe em `updated_at` e não faz broadcast. Não existe um caminho
separado de no-op para alguém esquecer de tratar — está no tipo de retorno.

**O handler nunca publica.** Ele *devolve* os eventos e o barramento publica
depois. É o que garante que um evento não vaze para o mundo por causa de uma
escrita que acabou falhando.

**O agregado não atravessa a fronteira.** Handlers de comando devolvem o slug,
não o `%Diagram{}`. Quem chama recebe um identificador e, se quiser o estado,
faz uma query — que é o lado de leitura, com o read model certo.

### Leitura

```
Bus.ask(GetDiagramBySlug, %{slug: "abc123"})
   │
   ├─ leitor projeta direto no `select:` os campos que a tela usa
   └─ handler chama o compilador do domínio para montar a cena
```

Nenhum agregado é reconstituído. A listagem pública, por exemplo, nunca traz a
coluna `source`: exibir 50 títulos não deve arrastar 50 blocos de DSL pela rede.

Quando um read model materializado fizer sentido (feed com contadores, ranking
de bifurcações), ele entra atrás da mesma `DiagramReader`. Nada acima muda.

### Sem registro central de rotas

Cada mensagem declara seu handler:

```elixir
use Brainagram.Application.Command,
  handler: Brainagram.Application.Handlers.CreateDiagram,
  fields: [source: :string, slug: :string, visibility: :string],
  required: [:source]
```

Evita o arquivo gigante de despacho que sempre vira ponto de conflito de merge,
e faz "quem trata isso?" ser uma ida à definição no editor.

### Comandos e queries existentes

| Comando | Efeito |
|---|---|
| `CreateDiagram` | cria a partir do fonte; deriva título e tipo |
| `ChangeDiagramSource` | troca o fonte, re-derivando metadados |
| `ChangeDiagramVisibility` | publica / despublica |
| `ForkDiagram` | duplica sob slug novo, **privado** por padrão, no mesmo projeto |
| `DeleteDiagram` | remove |
| `StartDiagram` | cria a partir do modelo inicial do tipo (`Templates.starter/3`), com o título no cabeçalho |
| `RenameDiagram` | troca o título **no fonte** (`Authoring.rename_title/2`) |
| `MoveDiagram` | muda o diagrama de projeto (ou tira de qualquer um) |
| `CreateProject` / `UpdateProject` | projeto: nome e cor |
| `DeleteProject` | exclui o projeto; os diagramas dele ficam **sem projeto** |

| Query | Retorno |
|---|---|
| `GetDiagramBySlug` | `DiagramDetail` com a cena compilada |
| `ListPublicDiagrams` | `[DiagramSummary]` sem o fonte |
| `ListDiagrams` | `[DiagramSummary]` da área de gestão: por projeto, tipo, busca e ordem |
| `ListProjects` | `[ProjectSummary]` com contagem, mais o total e os sem projeto |
| `GetDiagramPreview` | a miniatura SVG de um card (`/d/:slug/preview.svg`) |
| `RenderScene` | `Scene` a partir de fonte avulso, sem tocar no banco |
| `ListExamples` / `GetExample` | catálogo do editor |

`ForkDiagram` no lugar de `RenameDiagram` não é acaso: bifurcar é a operação que
as pessoas realmente querem quando o texto é a fonte da verdade. E a cópia nasce
privada de propósito — bifurcar o diagrama de alguém não deve publicar nada em
nome de ninguém sem um segundo ato deliberado.

### Projetos

O segundo agregado, `Project`, é uma pasta com nome e cor. O diagrama aponta
para ele **por identidade** (`project`: o slug do projeto, ou `nil`) — nunca o
contrário, e nunca carregando o outro agregado. Criar ou renomear um projeto não
toca em diagrama nenhum; mover um diagrama não toca no projeto.

Excluir um projeto é a única operação que atravessa os dois: o handler tira os
diagramas do projeto (`DiagramRepository.detach_project/1`, uma operação só, e
um `DiagramMoved` para cada um) e depois remove o projeto. A chave estrangeira
com `on_delete: :nilify_all` é rede de proteção, não a regra.

A área de gestão (`/`) escuta o tópico global de eventos (`Bus.subscribe_all/0`):
o que muda em outra aba ou por outra pessoa aparece sozinho.

---

## 5. Receita: adicionar um comando

1. **Comando** em `application/commands/` — struct, campos, handler, validação.
2. **Transição** no agregado, retornando `{:ok, agregado, eventos}`.
3. **Evento** em `domain/diagramming/events.ex`, com tipos primitivos.
4. **Handler** em `application/handlers/` — carrega, chama o agregado, persiste.
5. **Teste** em `test/brainagram/application/bus_test.exs`, com o repositório em
   memória. Sem banco, `async: true`.

Se o passo 2 for difícil de escrever, quase sempre é sinal de que a regra está
no lugar errado — não de que o agregado precisa de mais um campo.

---

## 6. O pipeline de diagramação

```
domain/diagramming/
├── dsl/
│   ├── ast.ex         structs: Ast, Node, Group, Step, Edge, Note
│   ├── parse_error.ex erro com linha
│   └── parser.ex      texto → AST (orientado a linha, coleta todos os erros)
├── layout/
│   ├── sequence.ex      AST → Scene (raias, timeline vertical, ativações)
│   └── architecture.ex  AST → Scene (Sugiyama: camadas, faixas, nós fantasma)
├── layout.ex          despacha pelo tipo
└── scene.ex           o IR serializado em JSON
```

### O parser nunca aborta no primeiro erro

Ele acumula `%ParseError{line:, message:}` e segue. Não é detalhe: o editor
recompila a cada 220 ms enquanto você digita, e **toda** linha incompleta é um
erro momentâneo. Abortar no primeiro erro faria a tela piscar.

Complemento no LiveView: quando a compilação falha, a **última cena válida
permanece na tela**. Você vê o erro na barra inferior sem perder o diagrama.

### Arestas longas viram cadeias, não diagonais

No diagrama arquitetural, uma aresta que pula camadas (a API na camada 2 falando
com o Postgres na camada 5) é o que destrói a legibilidade: a reta entre os dois
atravessa em diagonal tudo que estiver no caminho.

A normalização do grafo resolve isso. Toda aresta com vão maior que 1 ganha uma
vaga exclusiva num **corredor** — o vão vertical entre duas faixas de grupo — e
passa a ser desenhada como **polilinha ortogonal**: sai pela base da origem, corre
na horizontal dentro do vão entre camadas, desce reta pelo corredor e entra no
destino. A largura do corredor cresce com o número de arestas que passam nele.

Quatro decisões dentro disso:

- **Ortogonal, não diagonal.** Quando uma reta vertical cruza uma horizontal, o
  cruzamento é perpendicular e o olho separa as duas sem esforço — é o que mantém
  um esquema elétrico legível com dezenas de fios. Uma diagonal cruzando outra
  diagonal não tem essa propriedade.
- **O trecho horizontal fica no vão entre camadas**, nunca na altura das caixas.
  Sair pela lateral faria essa horizontal passar por cima dos vizinhos da mesma
  camada; o vão entre camadas é, por construção, vazio.
- **O lado do corredor é o lado do destino.** Descer sempre pela direita e depois
  voltar para um destino à esquerda faz a aresta cortar a última camada inteira.
- **A ordem das colunas é negociável.** A ordem declarada na DSL é o ponto de
  partida, e trocas entre faixas vizinhas são aceitas enquanto encurtarem a
  distância total das arestas entre grupos. A busca é local e parte do que o autor
  escreveu, então reordenar os `group` no texto ainda muda o desenho.

Sobra um caso que a arquitetura em colunas não resolve: quando dois grupos trocam
mensagens nos dois sentidos *e* há uma aresta longa entre eles, o corredor entre
as duas colunas é atravessado nos dois sentidos. Os cruzamentos restantes são
inerentes ao formato do grafo, não ao algoritmo — mas agora são perpendiculares,
que é a forma legível de cruzar.

### O IR (`Scene`)

```elixir
%Scene{
  kind: :sequence | :architecture,
  title: String.t(),
  width: integer(), height: integer(),
  nodes:       [%{id, label, kind, x, y, w, h, cx, lifeline_y1, lifeline_y2}],
  groups:      [%{id, label, x, y, w, h}],
  edges:       [%{id, step, from, to, arrow, label, path, x1, x2, y, duration, ...}],
  notes:       [%{id, step, text, x, y, w, h}],
  activations: [%{node, depth, y1, y2}],
  steps:       [%{index, label, y, edge_ids, note_ids, node_ids, duration}]
}
```

`path` é o `d` do SVG, gerado em Elixir. O cliente nunca calcula geometria — só
chama `getPointAtLength` para posicionar o pacote animado.

---

## 7. A DSL

```
diagram sequence "Checkout"

actor       user   "Cliente"
participant api    "API Gateway"
service     orders "Order Service"
database    db     "PostgreSQL"
queue       mq     "RabbitMQ"

step "Cliente confirma" {
  user -> api : POST /orders
  api  -> orders : CreateOrder
  orders -> orders : valida estoque      # auto-chamada
  orders -> db : INSERT order
  db --> orders : order_id
  note over user, api : a UI já responde aqui
}
```

| Seta | Semântica | Visual |
|---|---|---|
| `->`  | chamada síncrona | sólida, cabeça cheia, **abre barra de ativação** |
| `-->` | retorno / resposta | tracejada, cabeça aberta, **fecha a barra** |
| `->>` | assíncrono (fire-and-forget) | pontilhada, cabeça aberta, cor distinta |
| `-x`  | falha / timeout | tracejado curto, vermelho |

### Payload: o que a mensagem carrega

Logo abaixo de uma mensagem, o que ela leva — corpo de requisição, linha de
SQL, cabeçalhos — vira um balão sob a seta no diagrama de sequência:

```
user -> api : POST /orders
  payload: {"items": 3, "total": 199.90}

api -> db : INSERT order
  payload """
  INSERT INTO orders (id, total)   -- # e // aqui são conteúdo
  VALUES ($1, $2)
  """
```

- `payload:` numa linha (várias seguidas somam linhas); `payload """` abre um
  bloco **cru**: nada ali dentro é comentário, e o recuo comum sai.
- Só vale colado na mensagem (linhas em branco e comentários no meio podem);
  solto, é erro na linha dele.
- Minimizado por padrão: um **chip** sob a seta (o começo do conteúdo e
  quantas linhas tem). O layout reserva só o espaço do chip; o balão inteiro
  abre por cima do que vem abaixo, numa camada própria.
- Abre na animação quando a mensagem é a da vez e minimiza quando a próxima
  começa (a timeline dá uma pausa de leitura, `payload.hold`, proporcional ao
  tamanho). Clique no chip fixa aberto (e o balão fixado entra no SVG/PNG
  exportado); outro clique solta.
- Balão grande é aparado (16 linhas × 64 caracteres); o texto inteiro vai na
  cena, para a dica e para a edição pelo canvas (`Authoring.set_payload/3`:
  botão "Payload" na barra da seta, tecla P, ou duplo clique no chip/balão).

Princípios de design da linguagem:

- **Nós são declarados automaticamente.** `a -> b` já cria os dois. A declaração
  explícita só dá tipo e rótulo bonito. Barreira de entrada perto de zero.
- **Sem `step`, cada mensagem vira um passo.** Você ganha animação sem aprender
  nada além da seta.
- **Aliases em português** (`diagram arquitetura`).
- **`#` e `//` comentam**, respeitando aspas.

### Barras de ativação saem de uma pilha

`->` empilha uma ativação no destino, `-->` desempilha. É isso que produz a
leitura de "quem está executando agora" sem o autor anotar nada. Ativações que
nunca fecham são encerradas no fim do diagrama — chamada sem retorno explícito é
comum e não deve virar erro.

---

## 8. Modelo de animação

### Agendamento

```js
buildSchedule(scene) → { entries: Map(id → {start, dur, step}), steps: [...], total }
```

Dentro de um passo as arestas são sequenciais com 14% de sobreposição — dá
fluidez sem confundir a ordem. Entre passos, 340 ms de respiro.

### `seek(t)` é função pura do tempo

O motor não é uma cadeia de callbacks. É:

```js
seek(t) // desenha o estado exato do diagrama no instante t
```

`play()` vira "incrementa `t` e chama `seek`". O scrub vira "chama `seek`". Isso
elimina de uma vez toda a classe de bugs de animação — estado dessincronizado,
callback fora de ordem, scrub deixando metade das setas erradas.

### Estados visuais

| Estado | Condição | Opacidade |
|---|---|---|
| `is-pending` | `t < start` | 0.14 (fantasma: você vê a forma do diagrama inteiro) |
| `is-active` | animando | 1.0 |
| `is-done` | `t > start + dur` | 0.52 |

O "fantasma" é deliberado: mostrar a silhueta completa desde o início evita a
sensação de estar perdido no meio da animação.

### Técnica de revelação

Cada aresta tem dois paths: um **trilho** (sempre visível, carrega o tracejado
que codifica o tipo da seta) e uma **linha** revelada por `stroke-dashoffset`
indo de `pathLength` a `0`. Assim o tracejado semântico e a animação de
revelação não competem pela mesma propriedade CSS.

Um **pacote** viaja pela curva via `getPointAtLength`, e o nó de destino pulsa
quando ele passa de 82% do caminho. `prefers-reduced-motion` desliga pacote e
pulsos.

---

## 9. Modelo de dados

```sql
CREATE TABLE diagrams (
  id          bigserial PRIMARY KEY,
  slug        varchar   NOT NULL UNIQUE,   -- URL compartilhável
  title       varchar   NOT NULL,          -- derivado da DSL
  kind        varchar   NOT NULL,          -- derivado da DSL
  source      text      NOT NULL,          -- fonte da verdade
  visibility  varchar   NOT NULL,          -- 'public' | 'private'
  inserted_at timestamptz, updated_at timestamptz
);
```

`visibility` é string e não boolean porque o domínio já modela um enum, e um
terceiro estado (`:unlisted` — acessível por link, fora da listagem) está no
roadmap. Com boolean, essa migração de dados cairia junto com a feature; assim
ela já está paga.

Para as próximas fases:

```sql
diagram_versions (diagram_id, source, author_id, message, inserted_at)
workspaces / memberships
diagram_comments (diagram_id, step_index, anchor_id, body)
```

Comentário ancorado em **passo**, não em coordenada — sobrevive a mudanças de
layout. Vantagem direta de não persistir geometria.

---

## 10. Testes

101 testes, divididos por camada:

| Suíte | Precisa de banco? | O que prova |
|---|---|---|
| `domain/.../dsl/parser_test` | não | gramática, erros com linha |
| `domain/.../layout_test` | não | invariantes de geometria |
| `domain/.../diagram_test` | não | transições, eventos, no-op |
| `application/bus_test` | **não** (repo em memória) | comandos, queries, eventos |
| `infrastructure/persistence_test` | sim | mapeamento ida-e-volta, unicidade, projeções |
| `brainagram_web/.../editor_live_test` | sim | fluxo completo pela UI |
| `architecture_test` | não | **a regra de dependência, executável** |

O repositório em memória (`test/support/`) é a prova de que a porta pagou o
custo: um handler inteiro se testa em microssegundos. As portas são trocadas via
`Ports.override/2`, que grava no dicionário do processo — local ao teste, então a
suíte continua `async: true`.

Exemplos do tipo de invariante que dá para afirmar sem browser:

```elixir
test "raias não se sobrepõem" do
  pares = Enum.zip(scene.nodes, tl(scene.nodes))
  assert Enum.all?(pares, fn {l, r} -> l.x + l.w <= r.x end)
end

test "grupos ocupam faixas horizontais disjuntas" do
  [um, dois] = Enum.sort_by(scene.groups, & &1.x)
  assert um.x + um.w <= dois.x
end

test "fonte idêntico não gera evento" do
  assert {:ok, _same, []} = Diagram.change_source(diagram, mesmo_fonte)
end
```

### A regra de dependência é um teste

Um diagrama de camadas no README envelhece em silêncio. `architecture_test.exs`
lê a árvore de `lib/` e falha no CI se `domain/` mencionar Ecto ou Phoenix, se
qualquer camada acima aliasar `Brainagram.Infrastructure`, se a web falar com
repositório, ou se um comando declarar um handler que não implementa `handle/1`.

É a diferença entre uma convenção e uma regra.

### O que a suíte já pegou

`Slug.generate/0` usava base64url, cujo alfabeto inclui `-` e `_`. Como o
`@format` do próprio value object proíbe esses caracteres na primeira posição,
cerca de 3% dos slugs gerados eram rejeitados pelo `Slug.new/1` do caminho de
escrita — enquanto o de leitura, que não validava, aceitava. O sintoma era um
comando que falhava "aleatoriamente" em 1 de cada 30 diagramas novos.

Duas correções: o gerador passou a usar base32 minúsculo (válido por
construção) e o lado de leitura passou a validar pelo mesmo value object. A
regressão está fixada em teste com 2.000 gerações.

Próximo passo natural: **property-based testing** com StreamData — gerar DSLs
aleatórias e afirmar invariantes ("nada sai do canvas", "y cresce
monotonicamente", "nenhuma caixa colide").

---

## 11. Roadmap

### Fase 1 — MVP (o que já existe)
Parser, dois layouts, timeline, editor LiveView, export SVG/PNG, persistência
com link compartilhável, CQRS com eventos de domínio.

### Fase 2 — Compartilhar
- Página pública read-only, `<iframe>` embed + oEmbed (Notion, Confluence)
- Export **GIF/MP4** da animação: frames no servidor com Playwright via
  `Task.Supervisor` + fila. É o feature que tira a animação de dentro do site.
- Autenticação (`phx.gen.auth`) e workspaces

### Fase 3 — Editor visual

> Especificada em [`specs/001-autoria-visual.md`](specs/001-autoria-visual.md):
> canvas com drag-and-drop sobre a DSL, import de Mermaid/PlantUML e autoria por
> teclado. O resumo abaixo continua valendo; a spec detalha como.

A AST continua sendo a fonte da verdade:

```
arrastar nó  →  muda a AST  →  serializa para DSL  →  editor de texto atualiza
digitar      →  parseia     →  AST                 →  canvas atualiza
```

Exige um **printer** (AST → DSL) que preserve comentários e formatação — o mesmo
problema que o `prettier` resolve. Não é trivial, e por isso não está no MVP.
Posições manuais viram anotações na própria DSL (`participant api at 400`).

### Fase 4 — Colaboração em tempo real
Aqui o Elixir paga a aposta — e o barramento de eventos já está pronto:

- `Phoenix.Presence` para cursores e avatares
- Um `GenServer` por diagrama como sessão de edição, com `:syn`/`Horde`
- Edição concorrente de texto: **CRDT no cliente** (Yjs/Automerge), servidor como
  relay persistente. Não tente OT server-side

Os eventos de domínio já são publicados em `diagram:<slug>` — quando duas pessoas
abrirem o mesmo `/d/:slug`, cada uma já é assinante do canal certo. O editor
hoje usa isso para avisar "este diagrama mudou em outro lugar" sem sobrescrever
o que você está digitando.

### Fase 5 — Integrações
- CLI + GitHub Action: renderiza `.brain` do repositório, comenta o diff visual no PR
- Importar de Mermaid e PlantUML
- Gerar esqueleto a partir de traces OpenTelemetry — o diagrama de sequência
  *real* do sistema, não o que você acha que é

---

## 12. Stack e deploy

| Camada | Escolha |
|---|---|
| Runtime | Elixir 1.18 / OTP 25+ |
| Web | Phoenix 1.8 + LiveView 1.1 |
| Banco | PostgreSQL 16 |
| Assets | esbuild (JS + CSS puro com tokens do design system; sem Node em produção) |
| Render | SVG + hook JS |

Deploy em Fly.io com `libcluster` + `DNSCluster`. Uma instância `shared-cpu-1x`
aguenta milhares de editores simultâneos — o trabalho por keystroke é um parse
de ~2 KB. Custo de memória por sessão LiveView: alguns KB.

---

## 13. Licença e modelo

O repositório sai como **MIT** — máxima adoção, que é o que importa para uma
ferramenta de dev no começo.

A alternativa séria é **AGPL-3.0**: protege contra um concorrente subir um SaaS
fechado em cima do código. O trade-off é real — AGPL afasta uso corporativo e
contribuição de empresas.

- **Só open source / portfólio / comunidade** → MIT
- **Open core com SaaS pago** → AGPL no core + licença comercial (Grafana/Sentry/Cal.com)

Trocar de AGPL para MIT é fácil; o contrário, não.

---

## 14. Riscos

| Risco | Mitigação |
|---|---|
| Layout automático insuficiente para diagramas reais | Fase 3: âncoras manuais expressas na própria DSL |
| Editor visual é caro e pode nunca ficar bom | O produto já tem valor só com texto; visual é incremento |
| "Só mais um Mermaid" | A animação e o export em vídeo são o que não existe em lugar nenhum |
| Colaboração em tempo real é difícil | Não implemente OT. CRDT no cliente, servidor como relay |
| A arquitetura em camadas virar cerimônia | A regra de dependência é auditável por `grep`; se um handler começar a acumular regra, ela pertence ao agregado |
| Adoção | Integração com GitHub/Notion/Confluence vale mais que qualquer feature nova de canvas |
