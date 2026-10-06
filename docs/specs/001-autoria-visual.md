# Spec 001 — Autoria dupla: canvas com drag-and-drop sobre uma DSL

| | |
|---|---|
| **Status** | Implementada (fases A–E) — ver §14 |
| **Escopo** | Editor visual + adoção por quem já escreve diagramas em texto |
| **Depende de** | `docs/ARQUITETURA.md` §2 (o texto é a fonte da verdade), §4 (CQRS) |
| **Fase no roadmap** | 3 (editor visual) + parte da 5 (integrações) |

---

## 1. O problema

Brainagram hoje serve um público só: quem topa escrever uma DSL. Isso é uma
fatia estreita — e, pior, é uma fatia que **já tem ferramenta**. Quem escreve
Mermaid ou PlantUML há três anos não troca de ferramenta por uma sintaxe
ligeiramente diferente; troca por uma capacidade que a atual não tem (aqui, a
timeline animada) — e só se o custo de migrar for perto de zero.

Do outro lado existe um público maior que nunca vai digitar `api -> db : SELECT`:
gente que abre o draw.io, arrasta uma caixa e desenha. Para essa pessoa, o
Brainagram hoje é uma página em branco com um manual.

Servir os dois é a diferença entre um projeto de nicho e um produto. O risco é
servir os dois **mal**, construindo dois produtos dentro de um: um editor de
texto que ninguém usa e um canvas pior que o do concorrente.

Esta spec descreve como servir os dois sobre **um único modelo**.

---

## 2. Objetivos

1. Criar e editar um diagrama inteiro sem digitar DSL: arrastar caixas, puxar
   setas, renomear no lugar.
2. Alternar entre texto e canvas a qualquer momento, nos dois sentidos, sem
   perder nada — nem conteúdo, nem comentários, nem formatação.
3. Importar diagramas de Mermaid e PlantUML com fidelidade suficiente para a
   pessoa trazer o acervo dela.
4. Autoria por teclado competitiva para quem prefere texto.

### Não-objetivos

- **Tela infinita com formas livres.** Brainagram desenha diagramas de
  engenharia com layout automático; não é substituto de Figma nem de Miro.
  Caixa solta sem semântica não entra.
- **Edição colaborativa simultânea.** É a fase 4 e tem spec própria. Esta spec
  só se compromete a não fechar a porta (§8).
- **Paridade de formas com draw.io.** O catálogo de tipos de nó cresce por
  demanda de domínio, não por catálogo.
- **Editar a animação pelo canvas.** Timeline continua sendo definida por `step`
  no texto. Entra numa spec futura.

---

## 3. Decisão central: o texto continua sendo a fonte da verdade

O canvas é uma **projeção editável** da DSL. Todo gesto no canvas termina em uma
reescrita do texto; nada é guardado "só no visual".

```
gesto no canvas ──▶ comando ──▶ edição do texto ──▶ parse ──▶ AST ──▶ layout ──▶ canvas
                                      ▲                                            │
                                      └──────────────  digitar  ───────────────────┘
```

### Alternativas consideradas

| Opção | A favor | Contra | Veredito |
|---|---|---|---|
| **Texto manda** (escolhida) | um modelo, um histórico, diff revisável em PR, colaboração via CRDT de texto | exige editor cirúrgico de texto que preserve comentários — a parte difícil | escolhida |
| Canvas com modelo próprio, DSL como export | drag-and-drop trivial de implementar | mata a promessa central: diff deixa de ser revisável, autor de texto vira cidadão de segunda classe, dois modelos para sincronizar | rejeitada |
| Dois modos que não se convertem | evita o problema técnico inteiro | dois produtos, dois backlogs, e a pessoa escolhe errado no primeiro clique | rejeitada |

A razão de fundo: **o valor do Brainagram em code review depende do texto.** Um
diagrama que vive num JSON de geometria não tem diff legível, não entra num PR e
não sobrevive a um `git blame`. Abrir mão disso para ganhar um mês de
implementação seria trocar o produto pelo protótipo.

---

## 4. O contrato de escrita: dois escritores, não um

A tentação é escrever um pretty-printer AST → DSL e regenerar o arquivo a cada
gesto. **Não faça isso.** Regenerar o arquivo apaga comentários, normaliza
alinhamento e reordena declarações — ou seja, transforma "arrastei uma caixa"
num diff de quarenta linhas. Para o autor de texto, isso é o fim da confiança na
ferramenta.

São dois escritores, com responsabilidades distintas:

### 4.1 Editor cirúrgico (interativo)

Aplica o **menor patch possível** sobre o texto existente. Trocar um rótulo
altera os bytes daquele rótulo, e nada mais. Requisito habilitador:

> **A AST precisa carregar spans de origem.** Hoje cada nó guarda só `:line`
> (`Dsl.Node`, `Dsl.Edge`, `Dsl.Step`…). Passa a guardar
> `%Span{line, column, offset, length}` para o nó inteiro e para cada campo
> editável (id, rótulo, seta, mensagem).

Isso é uma mudança de contrato no parser e deve ser o **primeiro** item entregue:
tudo depende dela.

```elixir
# Domain.Diagramming.Dsl.Editor
@spec replace(source :: String.t(), Span.t(), String.t()) :: String.t()
@spec insert_line(source :: String.t(), after :: Span.t(), String.t()) :: String.t()
@spec remove_line(source :: String.t(), Span.t()) :: String.t()
```

Cada função devolve texto novo. Sem estado, sem efeito — testável com property
testing (§12).

### 4.2 Printer completo (explícito)

AST → DSL canônica, usada **só** quando a pessoa pede: comando `Formatar`,
`mix brainagram.fmt`, e na importação de Mermaid/PlantUML (onde não há
formatação original a preservar).

É a mesma separação que existe entre o *refactor* de uma IDE e rodar o
`prettier`: um mexe no que você apontou, o outro mexe no arquivo todo — e é você
quem decide quando.

---

## 5. Posições manuais: o bloco `layout`

Arrastar um nó precisa virar texto. A posição vai para um bloco dedicado **no
fim do arquivo**:

```
diagram architecture "Plataforma"

group "Dados" {
  database pg "PostgreSQL"   # o texto narrativo continua limpo
  queue    mq "RabbitMQ"
}

api -> pg : SELECT

layout {
  pg at (420, 680)
  mq at (700, 420)
}
```

Por que um bloco separado, e não `database pg "PostgreSQL" at (420, 680)`:

- **O diff fica contido.** Uma sessão de arrastar mexe num trecho só do arquivo,
  não em vinte linhas espalhadas.
- **A narrativa continua legível.** Quem lê o diagrama para entender o sistema
  não quer coordenadas no meio da frase.
- **Voltar ao automático é apagar o bloco.** Operação óbvia, reversível, e que
  cabe num botão ("Soltar posições").

### Semântica

| Situação | Comportamento |
|---|---|
| Nó ausente do bloco | posicionado pelo layout automático |
| Nó presente | **fixado** naquela coordenada |
| Nó fixado | vira **obstáculo**: o layout automático posiciona os demais evitando a área dele |
| Bloco `layout` ausente | tudo automático (comportamento atual) |

**Consequência algorítmica, e é a parte cara:** `Layout.Architecture` e
`Layout.Sequence` hoje assumem controle total da geometria. Passam a receber
`%Hints{pinned: %{id => {x, y}}}` e a respeitá-los. A regra proposta, por ser a
mais previsível:

1. Nós fixados mantêm a coordenada exata. Ponto.
2. A camada de um nó fixado passa a ser derivada do `y` dele, não do grafo.
3. Os demais seguem o algoritmo atual, tratando as caixas fixadas como ocupadas.
4. Uma fixação que contradiz o grafo (destino acima da origem) é **permitida** e
   desenhada como aresta ascendente. O autor mandou; o algoritmo obedece.

Regra 4 é deliberada: uma ferramenta que "corrige" o que a pessoa acabou de
arrastar é uma ferramenta que ninguém usa duas vezes.

---

## 6. Modelo de interação do canvas

| Gesto | Comando | Efeito no texto |
|---|---|---|
| Arrastar nó | `PinNode` | insere/atualiza linha no bloco `layout` |
| Arrastar em área vazia | `AddNode` | nova linha de declaração + entrada em `layout` |
| Puxar da alça de um nó até outro | `ConnectNodes` | nova linha `a -> b` no passo ativo |
| Duplo clique no rótulo | `RenameNodeLabel` | substitui o texto entre aspas |
| Duplo clique na aresta | `RelabelEdge` | substitui o texto depois de `:` |
| Clicar no tipo da seta | `ChangeEdgeArrow` | troca `->` por `-->`, `->>`, `-x` |
| `Delete` com seleção | `RemoveNode` / `RemoveEdge` | remove as linhas correspondentes |
| Arrastar para dentro de um grupo | `MoveNodeToGroup` | move a declaração para dentro do bloco `group` |
| Botão "Soltar posições" | `ClearLayoutHints` | apaga o bloco `layout` |
| Botão "Organizar setas" (arquitetura) | `UntangleLayout` | reescreve o bloco `layout` com a arrumação de menos cruzamentos |

Regras de interação:

- **Arrastar é local.** O nó acompanha o mouse a 60fps no cliente; o comando só é
  despachado no `mouseup`. É a mesma fronteira já estabelecida em
  `ARQUITETURA.md` §2.2 — o servidor decide *onde as coisas ficam*, não
  *onde o mouse está agora*.
- **Snapping** a uma grade de 8px e às bordas dos vizinhos.
- **Otimista com reconciliação.** O canvas aplica o efeito na hora e, quando a
  `Scene` recompilada volta, reconcilia. Divergiu? A `Scene` do servidor vence,
  com uma transição de 150ms para a diferença não parecer um glitch.

---

## 7. Onde isso entra na arquitetura

Nada aqui fura a regra de dependência (`architecture_test.exs` continua valendo).

**`domain/diagramming/`**

| Novo | Papel |
|---|---|
| `dsl/span.ex` | posição de um trecho no texto original |
| `dsl/editor.ex` | edições cirúrgicas sobre o fonte |
| `dsl/printer.ex` | AST → DSL canônica (só para `format` e import) |
| `layout/hints.ex` | posições fixadas, extraídas do bloco `layout` |
| `import/mermaid.ex`, `import/plant_uml.ex` | dialeto externo → AST |

**`application/commands/`** — os nove comandos da tabela do §6. Todos seguem o
padrão existente: struct + handler, agregado decide, barramento publica. O
agregado ganha uma transição só, genérica:

```elixir
Diagram.apply_edit(diagram, fn source -> Editor.replace(source, span, novo) end)
```

Ela reusa `change_source/2` por dentro — inclusive a regra de que **texto
idêntico não gera evento**, que aqui vale ouro: arrastar um nó e soltar no mesmo
lugar não suja o histórico.

**`infrastructure/`** — nada novo.

**`brainagram_web/`** — o hook `DiagramCanvas` ganha o modo de edição. O
renderizador já produz elementos com `data-node` e `data-edge`, então o
hit-testing sai barato.

---

## 8. Undo/redo: uma pilha só, sobre o texto

Todo gesto produz um `source` novo. Logo, **desfazer é voltar ao `source`
anterior** — não existe uma pilha para o canvas e outra para o editor de texto.

Isso resolve de graça o caso que costuma quebrar editores híbridos: arrastar uma
caixa, digitar no texto, e desfazer duas vezes. Aqui, as duas ações estão na
mesma linha do tempo, porque são a mesma coisa.

A pilha vive no cliente (é interação, não estado de negócio) e guarda os últimos
100 estados. Para colaboração (fase 4), a mesma escolha se paga: um CRDT de
texto substitui a pilha sem que nada acima mude.

---

## 9. Autoria para quem já é expert

Esta metade é o que traz a pessoa que **já sabe** fazer diagrama.

### Import

Converter de Mermaid e PlantUML para a DSL, via `Printer`. Cobertura mínima para
a v1: `sequenceDiagram` do Mermaid (participantes, mensagens síncronas,
assíncronas, retornos, `Note over`, `loop`/`alt` como `step`) e o diagrama de
sequência do PlantUML.

Depois da v1: o diagrama de **componentes** do PlantUML (`[X] as A`,
`component`/`database`/`queue`/`cloud`/`rectangle`, contêineres `package`/
`node`/`cloud { }` como `group`, setas com cor, estilo e direção) vira
`diagram architecture`. O diálogo de import traz "Organizar as setas", ligado
por padrão, que aplica o `Layout.Untangle` no resultado.

O que não converte vira **comentário no topo do arquivo**, não erro:

```
# 2 construções não convertidas do Mermaid original:
#   linha 14: `par` / `and` (paralelismo) — vire `step` manualmente
```

Falhar por inteiro num arquivo de 80 linhas por causa de duas construções é como
se perde um usuário na primeira tentativa.

### Teclado

- **Paleta de comandos** (`Ctrl/Cmd+K`): adicionar nó, conectar, formatar,
  importar, alternar tipo de diagrama.
- **Autocomplete de ids** no editor, alimentado pela AST atual.
- **Navegação por erro**: `F8` pula para a próxima linha com erro de sintaxe.
- **Reordenar passo** com `Alt+↑/↓`, movendo o bloco `step` inteiro.
- **Formatar** com `Shift+Alt+F`, usando o printer.

### Fora do navegador

- `mix brainagram.fmt` — formata `.brain` no repositório.
- `mix brainagram.render` — gera SVG/PNG, para rodar em CI.

Os dois reusam exatamente os mesmos módulos de domínio. É o dividendo de o motor
de diagramação não depender de Phoenix.

---

## 10. Riscos

| Risco | Probabilidade | Mitigação |
|---|---|---|
| O editor cirúrgico corrompe o fonte num caso de borda | média | property testing agressivo (§12); em caso de falha na validação pós-edição, descartar o patch e não aplicar nada |
| Layout com pinos fica pior que o automático | **alta** | entregar a fixação depois do resto, e sempre com "Reorganizar" a um clique |
| O canvas vira um draw.io pior | média | não-objetivos do §2 são para serem defendidos, não decorados |
| Import de Mermaid gera expectativa de paridade total | alta | comentário explícito do que não converteu; documentar a cobertura |
| Escopo cresce e nada fica pronto | **alta** | as fases do §11 são entregáveis independentes: cada uma pode ir a produção sozinha |

O segundo risco merece ênfase. Posição manual e layout automático **brigam** por
natureza: a pessoa arrasta uma caixa, o algoritmo reorganiza o resto em volta, e
o resultado pode ficar pior do que antes de ela mexer. A mitigação não é técnica,
é de produto: fixar pouco, fixar tarde, e tornar trivial voltar atrás.

---

## 11. Entrega em fases

Cada fase é entregável sozinha e tem critério de aceite verificável.

### Fase A — Spans na AST *(habilitador)*

Parser passa a registrar `%Span{}` por declaração e por campo editável.

**Aceite:** para cada exemplo do catálogo, `Editor.replace/3` em qualquer span
troca só aquele trecho — o resto do arquivo permanece **byte a byte idêntico**.

### Fase B — Edição pontual pelo canvas

Renomear rótulo de nó e de aresta, trocar tipo de seta, apagar. Sem arrastar.

**Aceite:** renomear um nó num diagrama com comentários preserva todos os
comentários; desfazer devolve o fonte original byte a byte.

### Fase C — Criar e conectar

Adicionar nó em área vazia, puxar aresta entre nós, remover. Posição ainda
automática.

**Aceite:** um diagrama de 10 nós e 12 arestas é construído do zero sem digitar,
e o fonte resultante compila e reproduz a mesma cena.

### Fase D — Arrastar e fixar

Bloco `layout`, `Hints` nos dois motores de layout, botão "Reorganizar".

**Aceite:** arrastar um nó, recarregar a página e ver o nó onde foi solto;
apagar o bloco `layout` restaura o automático.

### Fase E — Import e teclado

Mermaid, PlantUML, paleta de comandos, autocomplete, tarefas Mix.

**Aceite:** 20 diagramas Mermaid reais importados; ≥90% sem intervenção manual,
e os demais com comentário explicando o que faltou.

---

## 12. Testes

A suíte existente (`architecture_test.exs` inclusive) continua valendo. Somam-se:

**Property-based (StreamData)** — é aqui que esta spec se defende:

```elixir
property "o printer é reversível" do
  check all ast <- ast_generator() do
    assert {:ok, ^ast} = Parser.parse(Printer.print(ast))
  end
end

property "edição cirúrgica só toca o span informado" do
  check all {source, span, novo} <- edit_generator() do
    editado = Editor.replace(source, span, novo)
    assert fora_do_span(source, span) == fora_do_span(editado, span)
  end
end

property "arrastar e desfazer volta ao byte original" do
  check all {source, node_id, posicao} <- drag_generator() do
    assert source == source |> Hints.pin(node_id, posicao) |> Hints.unpin(node_id)
  end
end
```

**Integração** — cada comando do §6 no `bus_test.exs`, com repositório em
memória. **LiveView** — um teste por gesto, verificando o fonte resultante.
**Visual** — snapshot de `Scene` para os exemplos do catálogo, para pegar
regressão de layout.

---

## 13. Questões em aberto

1. **Grupo no canvas.** Arrastar um nó para dentro de um `group` move a
   declaração no texto — mas e arrastar o grupo inteiro? Fixa todos os membros?
   Precisa de um `layout` por grupo?
2. **Conflito entre pino e camada.** A regra 2 do §5 deriva a camada do `y`.
   Dois nós fixados em `y` próximos mas logicamente em camadas distintas
   produzem um desenho ambíguo. Vale um aviso na interface?
3. **Tamanho do nó.** Hoje é derivado do rótulo. Redimensionar manualmente entra
   no bloco `layout` ou fica de fora?
4. **Passo ativo ao conectar.** Ao puxar uma aresta, ela entra em qual `step`?
   Proposta: o passo selecionado na timeline; se nenhum, o último. Precisa de
   validação com usuário.
5. **`.brain` como extensão.** Padronizar agora, antes de haver acervo.

---

## Referências

- `docs/ARQUITETURA.md` §2.1 (texto como fonte da verdade), §2.2 (fronteira
  servidor/cliente), §6 (pipeline de diagramação)
- Sugiyama et al., *Methods for Visual Understanding of Hierarchical System
  Structures* (1981) — base do layout em camadas já implementado
- `dagre` e `ELK` — referências de layout com restrições de posição

---

## 14. Notas de implementação

Onde cada parte mora e as decisões tomadas nas questões em aberto do §13.

| Parte | Onde |
|---|---|
| Spans (fase A) | `Dsl.Span`; `span`/`spans` em cada struct de `Dsl.Ast`; `Dsl.Parser` |
| Editor cirúrgico e printer | `Dsl.Editor`, `Dsl.Printer` |
| Operações de autoria | `Domain.Diagramming.Authoring` (puras, `texto -> texto`) |
| Transição do agregado | `Diagram.apply_edit/2` |
| Bloco `layout` e pinos | `Layout.Hints`; `Layout.Architecture`/`Layout.Sequence` recebem `%Hints{}` |
| Comandos do §6 | `Application.Commands.*` (onze structs) → `Handlers.EditDiagram` |
| Organizar setas | `Layout.Untangle` (busca), `Layout.Router` (rotas que desviam de caixas), `Layout.Quality` (medida) |
| Pré-visualização no editor | query `EditSource` (gesto → texto + cena, sem persistir) |
| Import | `Domain.Diagramming.Import` (+ `Import.Mermaid`, `Import.PlantUml`, `Import.PlantUmlComponent`, `Import.Builder`), query `ImportDiagram` (`organize: true` → `Untangle`) |
| Canvas | `assets/js/brainagram/editor.js`, hook `DiagramCanvas` |
| Editor de texto, desfazer único, F8, Alt+↑/↓, autocomplete | hook `SourceEditor` |
| Paleta ⌘K | hook `CommandPalette` |
| Fora do navegador | `mix brainagram.fmt`, `mix brainagram.render` (`Render.Svg`) |

Decisões:

- **Editor da sessão × persistência.** Os gestos no editor passam pela query
  `EditSource`: mudam o texto da sessão, que só é gravado no "Salvar" — o
  mesmo contrato de digitar. Os comandos (`PinNode`, `AddNode`…) fazem o
  caminho completo pelo agregado para diagramas já salvos e são o ponto de
  entrada de uma API ou da colaboração (fase 4).
- **Passo ativo ao conectar (§13.4).** O passo escolhido na timeline (clique no
  card, na faixa ou ←/→); sem escolha, o último. Em passo implícito, a seta
  entra logo depois da mensagem dele.
- **Pino × camada (§13.2).** Sem aviso por enquanto: a camada vem do `y`
  (regra 2) e a sobreposição é resolvida empurrando os livres para a direita.
- **Sequência.** Só o eixo horizontal é livre: o `y` de um pino é ignorado.
- **Grupo inteiro (§13.1) e redimensionar (§13.3).** Fora desta entrega:
  arrasta-se o nó; o tamanho continua derivado do rótulo.
- **Extensão (§13.5).** `.brain`, já usada pelas tarefas Mix.
- **Formatar** usa o printer e, como ele, não preserva comentários: o editor
  avisa e o Ctrl+Z desfaz; `mix brainagram.fmt` pula arquivos com comentário
  sem `--drop-comments`.
- **Import.** `par`, `rect`, `ref`, atrasos e setas bidirecionais viram
  comentário no topo; as mensagens de dentro desses blocos são mantidas.
  `#` e `//` no texto importado viram `＃` e `/⁄`, porque na DSL começam
  comentário.
- **Organizar setas.** Arquiteturas vindas de Mermaid/PlantUML costumam ter as
  setas entrelaçadas, e a ordem das declarações sozinha não resolve (o
  automático só melhora localmente). `Layout.Untangle` busca a arrumação —
  ordem das faixas de grupo (grupos em camadas disjuntas empilham na mesma
  coluna), ordem dentro de cada camada, camada de cada nó sem nenhuma seta
  subir — com uma medida rápida de segmentos retos, confirma as melhores
  roteando de verdade e medindo com `Layout.Quality` (cruzamentos, setas por
  cima de caixas e de grupos alheios, quinas, comprimento), e grava o
  resultado como pinos no bloco `layout`. Só aplica se melhorar; é
  determinístico e idempotente, e "Soltar posições" devolve o texto original
  byte a byte. Com qualquer pino, as rotas vêm de `Layout.Router` (A\* numa
  grade de vãos, portas espalhadas por lado e ordenadas pela outra ponta,
  custo por quina, cruzamento, sobreposição e passagem por grupo alheio).
- **Ciclos na arquitetura.** "Cliente manda comando, sistema devolve evento
  ao cliente" é comum em diagramas importados. A atribuição de camadas ignora
  as arestas de retorno (DFS a partir das fontes, na ordem de declaração) —
  sem isso a relaxação empurrava o ciclo para baixo a cada passada e a cena
  passava de 8.000 px de altura. A aresta de retorno é desenhada subindo.
