defmodule Brainagram.Domain.Diagramming.ImportTest do
  @moduledoc """
  Fase E da spec 001: importar o acervo de quem já usa Mermaid ou PlantUML.

  Aceite: 20 diagramas Mermaid no estilo do mundo real importados; ≥ 90% sem
  intervenção manual, e os demais com comentário explicando o que faltou.
  """

  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.Dsl.Parser
  alias Brainagram.Domain.Diagramming.Import
  alias Brainagram.Test.Fixtures

  @mermaid [
    login: """
    sequenceDiagram
        participant U as Usuário
        participant A as App
        participant S as Auth Service
        U->>A: credenciais
        A->>S: POST /token
        S-->>A: JWT
        A-->>U: sessão iniciada
    """,
    docs_basic: """
    sequenceDiagram
        Alice->>John: Hello John, how are you?
        John-->>Alice: Great!
        Alice-)John: See you later!
    """,
    actors: """
    sequenceDiagram
        actor Cliente
        participant Loja
        Cliente->>Loja: escolhe produto
        Loja-->>Cliente: preço
    """,
    notes: """
    sequenceDiagram
        participant API
        participant DB
        Note right of API: valida o payload
        API->>DB: INSERT
        Note over API,DB: transação
        DB-->>API: ok
        Note left of API: loga
    """,
    loop: """
    sequenceDiagram
        participant W as Worker
        participant Q as Fila
        loop a cada mensagem
            W->>Q: consome
            Q-->>W: payload
        end
    """,
    alt: """
    sequenceDiagram
        Cliente->>API: GET /pedido/42
        alt pedido existe
            API-->>Cliente: 200
        else não existe
            API-->>Cliente: 404
        end
    """,
    opt: """
    sequenceDiagram
        API->>Cache: GET chave
        opt cache vazio
            API->>DB: SELECT
            DB-->>API: linhas
            API->>Cache: SET chave
        end
        API-->>Cliente: resposta
    """,
    activations: """
    sequenceDiagram
        Alice->>+John: Hello John
        John->>+Mary: pergunta
        Mary-->>-John: resposta
        John-->>-Alice: tudo certo
    """,
    failures: """
    sequenceDiagram
        Gateway->>Pagamento: cobra
        Pagamento-xGateway: timeout
        Gateway--xFila: descarta
    """,
    async: """
    sequenceDiagram
        Pedido-)Estoque: reserva
        Pedido--)Email: confirmação
    """,
    title: """
    sequenceDiagram
        title Checkout
        Loja->>PSP: autoriza
        PSP-->>Loja: ok
    """,
    front_matter: """
    ---
    title: Cadastro
    ---
    sequenceDiagram
        Form->>API: POST /usuarios
        API-->>Form: 201
    """,
    typed: """
    sequenceDiagram
        participant api as API
        participant pg@{ "type" : "database" } as Postgres
        participant mq@{ "type" : "queue" } as RabbitMQ
        api->>pg: INSERT
        api-)mq: publica
    """,
    boxes: """
    sequenceDiagram
        box Aqua Frontend
        participant Web
        participant Mobile
        end
        box Backend
        participant API
        end
        Web->>API: GET
        Mobile->>API: GET
    """,
    critical: """
    sequenceDiagram
        Serviço->>DB: conecta
        critical conexão
            DB-->>Serviço: ok
        option falha de rede
            Serviço->>Serviço: tenta de novo
        end
    """,
    break_block: """
    sequenceDiagram
        Consumidor->>API: pedido
        break estoque zerado
            API-->>Consumidor: 409
        end
    """,
    comments: """
    %% fluxo de login
    sequenceDiagram
        %% participantes
        A->>B: um
        %% fim
        B-->>A: dois
    """,
    autonumber: """
    sequenceDiagram
        autonumber
        activate API
        Cliente->>API: pedido #42
        API-->>Cliente: ok
        deactivate API
    """,
    par: """
    sequenceDiagram
        Pedido->>Loja: fecha
        par avisa todo mundo
            Loja->>Email: envia
        and
            Loja->>SMS: envia
        end
    """,
    rect: """
    sequenceDiagram
        rect rgb(191, 223, 255)
        Cliente->>API: GET
        API-->>Cliente: 200
        end
    """
  ]

  describe "Mermaid" do
    test "aceite: 20 diagramas, ≥ 90% sem intervenção e o resto com comentário" do
      results =
        for {name, text} <- @mermaid do
          assert {:ok, %{source: source, warnings: warnings, format: :mermaid}} =
                   Import.convert(text),
                 "#{name} não importou"

          assert {:ok, _} = Parser.parse(source), "#{name} não compila"
          assert Fixtures.scene!(source).edges != [], "#{name} perdeu as mensagens"

          if warnings != [], do: assert(source =~ ~r/^# \d+ constru/, "#{name} sem comentário")
          {name, warnings}
        end

      assert length(results) == 20
      clean = Enum.count(results, fn {_name, warnings} -> warnings == [] end)
      assert clean / 20 >= 0.9, "só #{clean}/20 sem intervenção"
    end

    test "participantes, rótulos e setas chegam com o tipo certo" do
      {:ok, %{source: source}} = Import.convert(@mermaid[:login])

      assert source =~ ~s(participant U "Usuário")
      assert source =~ "U -> A : credenciais"
      assert source =~ "S --> A : JWT"
    end

    test "loop/alt viram passos; else abre o passo seguinte" do
      {:ok, %{source: source}} = Import.convert(@mermaid[:alt])
      {:ok, ast} = Parser.parse(source)

      assert Enum.map(ast.steps, & &1.label) == ["GET /pedido/42", "pedido existe", "não existe"]
    end

    test "tipo pelo @{type} e grupos pelo box" do
      {:ok, %{source: typed}} = Import.convert(@mermaid[:typed])
      assert typed =~ ~r/database\s+pg\s+"Postgres"/
      assert typed =~ ~r/queue\s+mq\s+"RabbitMQ"/

      {:ok, %{source: boxes}} = Import.convert(@mermaid[:boxes])
      assert boxes =~ ~s(group "Frontend" {)
      assert boxes =~ ~s(group "Backend" {)
    end

    test "# no texto não vira comentário da DSL" do
      {:ok, %{source: source}} = Import.convert(@mermaid[:autonumber])
      assert source =~ "Cliente -> API : pedido ＃42"
    end

    test "par vira comentário, mas as mensagens de dentro ficam" do
      {:ok, %{source: source, warnings: [{3, warning}]}} = Import.convert(@mermaid[:par])

      assert warning =~ "par"
      assert source =~ "# 1 construção não convertida do Mermaid original:\n#   linha 3:"
      assert source =~ "Loja -> Email : envia"
      assert source =~ "Loja -> SMS : envia"
    end

    test "o que não é diagrama de sequência não importa" do
      assert {:error, :nothing_to_import} = Import.convert("flowchart LR\n A --> B", :mermaid)
    end
  end

  describe "PlantUML" do
    @plantuml """
    @startuml
    title Checkout
    ' comentário
    actor Cliente
    participant "Loja Online" as loja
    database Pedidos as db
    queue Eventos
    skinparam monochrome true

    == Pedido ==
    Cliente -> loja : finaliza compra
    loja -> db : INSERT pedido
    db --> loja : id
    loja ->> Eventos : pedido_criado

    == Pagamento ==
    alt aprovado
      loja -> PSP : cobra
      PSP --> loja : ok
    else recusado
      PSP ->x loja : recusa
    end
    loja <-- PSP : recibo
    note over loja, db : idempotente
    note right of Cliente
      recebe e-mail
      de confirmação
    end note
    @enduml
    """

    test "converte participantes, seções, blocos e notas" do
      assert {:ok, %{source: source, warnings: [], format: :plantuml}} = Import.convert(@plantuml)
      {:ok, ast} = Parser.parse(source)

      assert ast.title == "Checkout"
      assert Enum.find(ast.nodes, &(&1.id == "loja")).label == "Loja Online"
      assert Enum.find(ast.nodes, &(&1.id == "db")).kind == :database
      assert Enum.find(ast.nodes, &(&1.id == "Eventos")).kind == :queue

      assert source =~ "loja ->> Eventos : pedido_criado"
      assert source =~ "PSP -x loja : recusa"
      assert source =~ "PSP --> loja : recibo"
      assert source =~ "note right of Cliente : recebe e-mail de confirmação"
      assert Enum.map(ast.steps, & &1.label) == ["Pedido", "aprovado", "recusado", "recibo"]
    end

    test "o que não converte vira comentário" do
      text = "@startuml\nA -> B : um\n...\nref over A, B : outro diagrama\n@enduml"
      assert {:ok, %{source: source, warnings: warnings}} = Import.convert(text)
      assert length(warnings) == 2
      assert source =~ "# 2 construções não convertidas do PlantUML original:"
    end
  end

  test "detecta o formato" do
    assert Import.detect("@startuml\nA -> B\n@enduml") == :plantuml
    assert Import.detect("sequenceDiagram\nA->>B: oi") == :mermaid
    assert Import.detect("texto qualquer") == nil
    assert {:error, :unsupported_format} = Import.convert("texto qualquer")
  end
end
