defmodule Brainagram.Domain.Diagramming.Import.MermaidFlowchartTest do
  @moduledoc "`flowchart` / `graph` do Mermaid → arquitetura."

  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.Dsl.Parser
  alias Brainagram.Domain.Diagramming.Import

  @dispatch """
  flowchart LR
      BO["BackOffice"]
      APIM["api-manager"]

      DA["deal-api<br/>HTTP :3010"]
      DR["dispatch-router<br/>worker"]
      AT["affiliate-tracking<br/>HTTP :3011"]
      DT["delivery-tracker<br/>worker"]
      CF["cloudforge<br/>HTTP :3012"]

      Q_RULES[["fila de regras<br/>1 msg por regra · RN-01"]]
      Q_SESS[["fila da sessão<br/>uma por sessão"]]
      Q_ERR[["fila de erros de regra<br/>RN-02"]]
      Q_RES[["fila de resultados"]]

      WPP["wpp-api"]
      TG["Telegram Bot API"]
      SHORT["affiliate-link-shortener"]
      CORE[("schema core<br/>só leitura")]
      DDB[("Dynamo do deal-api<br/>disparos, alvos, status")]
      S3[("S3<br/>imagens")]

      BO -->|"cria o disparo"| DA
      DA -->|"grava"| DDB
      DA -->|"imagem"| S3
      DA -.->|"/links/resolve"| AT
      DA -->|"publica"| Q_RULES
      Q_RULES -->|"consome"| DR

      DR -->|"lê regras e sessões"| CORE
      DR -->|"/links/generate"| AT
      AT --> SHORT
      DR -->|"publica (WhatsApp)"| Q_SESS
      Q_SESS -->|"consome"| WPP
      DR -->|"envia (Telegram)"| TG
      DR -->|"publica falhas"| Q_ERR

      WPP -->|"publica"| Q_RES
      DR -.->|"resultado do Telegram<br/>(a confirmar)"| Q_RES
      Q_RES -->|"consome"| DT
      Q_ERR -->|"consome"| DT
      DT -->|"status e progresso"| DDB

      APIM -->|"ciclo de vida da sessão"| CF
      CF -.->|"cria, atualiza, remove"| Q_SESS

      classDef queue fill:#fff4d6,stroke:#c28f00,color:#3b2e00
      classDef svc fill:#dbeafe,stroke:#2563eb,color:#0b2a5b
      classDef ext fill:#eeeeee,stroke:#777777,color:#222222
      classDef store fill:#e8f5e9,stroke:#2e7d32,color:#12361a
      class Q_RULES,Q_SESS,Q_ERR,Q_RES queue
      class DA,DR,AT,DT,CF svc
      class BO,APIM,WPP,SHORT,TG ext
      class CORE,DDB,S3 store
  """

  defp convert!(text) do
    {:ok, %{source: source, warnings: warnings, format: :mermaid}} = Import.convert(text)
    {:ok, ast} = Parser.parse(source)
    {ast, source, warnings}
  end

  defp node(ast, id), do: Enum.find(ast.nodes, &(&1.id == id))
  defp edges(ast), do: ast.steps |> Enum.flat_map(& &1.items)
  defp pairs(ast), do: ast |> edges() |> Enum.map(&{&1.from, &1.to, &1.arrow})

  describe "um mapa de serviços real" do
    setup do
      {ast, source, warnings} = convert!(@dispatch)
      %{ast: ast, source: source, warnings: warnings}
    end

    test "vira arquitetura sem nenhum aviso", %{ast: ast, warnings: warnings} do
      assert ast.kind == :architecture
      assert warnings == []
      assert length(ast.nodes) == 17
    end

    test "o tipo vem da classe e do cilindro", %{ast: ast} do
      kinds = ast.nodes |> Enum.frequencies_by(& &1.kind)
      assert kinds == %{queue: 4, database: 3, external: 5, service: 5}
      assert node(ast, "Q_RULES").kind == :queue
      assert node(ast, "DDB").kind == :database
      assert node(ast, "TG").kind == :external
      assert node(ast, "DR").kind == :service
    end

    test "rótulos numa linha, com <br/> virando ·", %{ast: ast} do
      assert node(ast, "DA").label == "deal-api · HTTP :3010"
      assert node(ast, "Q_RULES").label == "fila de regras · 1 msg por regra · RN-01"
    end

    test "as 20 setas, na ordem, cada uma num passo", %{ast: ast, source: source} do
      assert length(ast.steps) == 20
      assert hd(pairs(ast)) == {"BO", "DA", :sync}
      assert List.last(pairs(ast)) == {"CF", "Q_SESS", :async}
      assert {"DA", "AT", :async} in pairs(ast)
      assert source =~ "DA ->> AT : /links/resolve"
      assert source =~ "DR ->> Q_RES : resultado do Telegram (a confirmar)"
      assert source =~ "AT -> SHORT\n"
    end
  end

  describe "nós" do
    test "todas as formas clássicas dão o rótulo de dentro" do
      {ast, _, []} =
        convert!("""
        graph TD
          A[ret] --> B(arredondado) --> C([estádio]) --> D[[sub]] --> E((círculo))
          E --> F(((duplo))) --> G{decisão} --> H{{hexágono}} --> I>bandeira]
          I --> J[/para/] --> K[\\inv\\] --> L[/trap\\] --> M[\\trapinv/]
          M --> N
        """)

      assert Enum.map(ast.nodes, & &1.label) ==
               ~w(ret arredondado estádio sub círculo duplo decisão hexágono bandeira para inv trap trapinv N)

      # o losango é a pergunta de um fluxo de decisão; o resto é serviço
      assert node(ast, "G").kind == :decision
      assert ast.nodes |> Enum.reject(&(&1.id == "G")) |> Enum.all?(&(&1.kind == :service))
    end

    test "losango é decisão, mesmo com classe, e na sintaxe nova" do
      {ast, source, []} =
        convert!("""
        flowchart TD
          Q{Tem estoque?}:::svc -->|sim| A
          Q -->|não| B
          B --> R@{ shape: diamond, label: "Tentar de novo?" }
        """)

      assert %{label: "Tem estoque?", kind: :decision} = node(ast, "Q")
      assert %{label: "Tentar de novo?", kind: :decision} = node(ast, "R")
      assert source =~ "Q -> A : sim"
      assert source =~ "Q -> B : não"
    end

    test "cilindro e formas de armazenamento são banco" do
      {ast, _, []} =
        convert!("""
        flowchart LR
          A[(Pedidos)] --> B@{ shape: cyl, label: "Eventos" }
          B --> C@{ shape: rounded, label: "API" }
        """)

      assert %{label: "Pedidos", kind: :database} = node(ast, "A")
      assert %{label: "Eventos", kind: :database} = node(ast, "B")
      assert %{label: "API", kind: :service} = node(ast, "C")
    end

    test "sem classe nem cilindro, o rótulo sugere o tipo" do
      {ast, _, []} =
        convert!("""
        flowchart LR
          U[Clientes] --> API --> K[Kafka] --> R[Redis]
        """)

      assert node(ast, "U").kind == :actor
      assert node(ast, "API").kind == :service
      assert node(ast, "K").kind == :queue
      assert node(ast, "R").kind == :database
    end

    test "classe com ::: e nomes compostos" do
      {ast, _, []} =
        convert!("""
        flowchart LR
          A:::extSystem --> B[Pagamentos]:::data-store
          B --> C
          class C message_queue
        """)

      assert node(ast, "A").kind == :external
      assert %{label: "Pagamentos", kind: :database} = node(ast, "B")
      assert node(ast, "C").kind == :queue
    end

    test "aspas, Markdown e entidades viram texto simples" do
      {ast, source, []} =
        convert!("""
        flowchart LR
          A["`**Checkout** #quot;v2#quot;`"] -->|"total #35;1"| B["a &amp; b"]
        """)

      assert node(ast, "A").label == "Checkout 'v2'"
      assert node(ast, "B").label == "a & b"
      assert source =~ "A -> B : total ＃1"
    end
  end

  describe "setas" do
    test "estilo da linha decide o tipo" do
      {ast, _, []} =
        convert!("""
        flowchart LR
          A --> B
          A ==> C
          A --o D
          A -.-> E
          A --x F
          A -..-> G
          A ---> H
          A --x|recusa| I
        """)

      assert pairs(ast) == [
               {"A", "B", :sync},
               {"A", "C", :sync},
               {"A", "D", :sync},
               {"A", "E", :async},
               {"A", "F", :fail},
               {"A", "G", :async},
               {"A", "H", :sync},
               {"A", "I", :fail}
             ]
    end

    test "texto no meio da seta, nas três formas" do
      {_ast, source, []} =
        convert!("""
        flowchart LR
          A -- chama --> B
          B -. avisa .-> C
          C == grava ==> D
          D -->|lê| E
        """)

      assert source =~ "A -> B : chama"
      assert source =~ "B ->> C : avisa"
      assert source =~ "C -> D : grava"
      assert source =~ "D -> E : lê"
    end

    test "cadeia e leque viram uma seta por par, em ordem" do
      {ast, _, []} = convert!("flowchart LR\n  A & B --> C --> D & E")

      assert Enum.map(pairs(ast), fn {f, t, _} -> {f, t} end) ==
               [{"A", "C"}, {"B", "C"}, {"C", "D"}, {"C", "E"}]
    end

    test "; separa comandos e id de seta, ~~~ e estilo somem sem aviso" do
      {ast, _, warnings} =
        convert!("""
        flowchart LR
          %%{init: {"theme": "dark"}}%%
          A --> B; B e1@--> C
          C ~~~ D
          style A fill:#f9f;stroke:#333
          linkStyle 0 stroke:red
          click A "https://example.com"
          direction TB
        """)

      assert warnings == []
      assert Enum.map(pairs(ast), fn {f, t, _} -> {f, t} end) == [{"A", "B"}, {"B", "C"}]
      assert node(ast, "D")
    end
  end

  describe "subgraphs" do
    test "viram grupos; aninhados, vale o de dentro" do
      {ast, _, []} =
        convert!("""
        flowchart TB
          subgraph edge [Borda]
            CDN --> LB
          end
          subgraph app["Aplicação"]
            API
            subgraph data[Dados]
              PG[(Postgres)]
            end
          end
          LB --> API --> PG
        """)

      assert Enum.map(ast.groups, &{&1.label, &1.node_ids}) == [
               {"Borda", ["CDN", "LB"]},
               {"Aplicação", ["API"]},
               {"Dados", ["PG"]}
             ]
    end
  end

  describe "o que não converte vira comentário" do
    test "sem ponta, mão dupla, seta para subgraph e linha estranha" do
      {ast, source, warnings} =
        convert!("""
        flowchart LR
          subgraph S [Grupo]
            X
          end
          A --- B
          B <--> C
          C --> S
          ??? isso não é mermaid
        """)

      assert length(warnings) == 4
      assert source =~ "# 4 construções não convertidas do Mermaid original:"
      assert source =~ "ligação sem seta `---` — convertida como A → B"
      assert source =~ "mão dupla `<-->`"
      assert source =~ "seta para o subgraph `S`"
      assert source =~ "linha não reconhecida"
      assert {"A", "B", :sync} in pairs(ast)
      assert {"B", "C", :sync} in pairs(ast)
      refute node(ast, "S")
    end
  end

  describe "cabeçalho e detecção" do
    test "graph e flowchart, com front matter e comentários antes" do
      text = """
      ---
      title: Plataforma
      ---
      %% mapa geral
      graph LR
        A --> B
      """

      assert Import.detect(text) == :mermaid
      assert Import.detect("flowchart TD\n A --> B") == :mermaid
      assert Import.detect("sequenceDiagram\nA->>B: oi") == :mermaid

      {ast, _, []} = convert!(text)
      assert ast.title == "Plataforma"
    end

    test "LR e RL deitam o diagrama; TD, TB, BT e sem direção, em pé" do
      for dir <- ~w(LR RL lr) do
        {ast, source, []} = convert!("flowchart #{dir}\n  A --> B")
        assert ast.direction == :horizontal
        assert source =~ "diagram architecture\ndirection horizontal\n"
      end

      for header <- ["flowchart TD", "graph TB", "flowchart BT", "graph"] do
        {ast, source, []} = convert!("#{header}\n  A --> B")
        assert ast.direction == :vertical
        refute source =~ "direction"
      end
    end

    test "comando na mesma linha do cabeçalho" do
      {ast, _, []} = convert!("graph LR; A --> B")
      assert pairs(ast) == [{"A", "B", :sync}]
    end
  end
end
