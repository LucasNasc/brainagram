defmodule Brainagram.Domain.Diagramming.Import.PlantUmlComponentTest do
  @moduledoc "Diagrama de componentes do PlantUML → arquitetura."

  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.Dsl.Parser
  alias Brainagram.Domain.Diagramming.Import
  alias Brainagram.Domain.Diagramming.Import.PlantUmlComponent
  alias Brainagram.Test.Fixtures

  defp convert!(text) do
    {:ok, %{source: source, warnings: warnings, format: :plantuml}} = Import.convert(text)
    {:ok, ast} = Parser.parse(source)
    {ast, source, warnings}
  end

  defp node(ast, id), do: Enum.find(ast.nodes, &(&1.id == id))
  defp edges(ast), do: ast.steps |> Enum.flat_map(& &1.items) |> Enum.map(&{&1.from, &1.to})

  describe "o diagrama de integrações do WPP-API" do
    setup do
      {ast, source, warnings} = convert!(Fixtures.plantuml_component_source())
      %{ast: ast, source: source, warnings: warnings}
    end

    test "vira arquitetura com título, grupos e todos os nós", %{ast: ast} do
      assert ast.kind == :architecture
      assert ast.title == "Visão Introdutória — Objetivos e Integrações"

      assert Enum.map(ast.groups, &{&1.label, &1.node_ids}) == [
               {"WPP-API (NestJS)", ["ASS", "BWS", "AES", "REDIS"]},
               {"AWS AppSync", ["RT", "APP"]}
             ]

      assert length(ast.nodes) == 8
    end

    test "rótulos com \\n viram uma linha e o tipo vem da palavra-chave ou do nome", %{ast: ast} do
      assert %{label: "AppSyncSubscriberService (Realtime WS)", kind: :service} = node(ast, "ASS")
      assert %{label: "Cache/Redis", kind: :database} = node(ast, "REDIS")
      assert %{label: "WhatsApp", kind: :external} = node(ast, "WA")
      assert %{label: "Clientes/Consumidores", kind: :actor} = node(ast, "CLIENTS")
    end

    test "as oito setas, com rótulo e sem a cor", %{ast: ast, source: source} do
      assert length(edges(ast)) == 8
      assert {"APP", "CLIENTS"} in edges(ast)
      assert source =~ "ASS -> BWS : executeAction(action, content)"
      refute source =~ "#blue"
    end

    test "notas vão para o comentário do topo, com o texto", %{warnings: warnings, source: source} do
      assert length(warnings) == 2
      assert source =~ "nota sobre ASS"
      assert source =~ "Watchdog keep-alive"
      assert source =~ "408/429 => restart"
    end
  end

  test "detecta componentes sem confundir com sequência" do
    assert PlantUmlComponent.component?(Fixtures.plantuml_component_source())
    refute PlantUmlComponent.component?("@startuml\nparticipant A\nA -> B : oi\n@enduml")
    refute PlantUmlComponent.component?("@startuml\nactor U\ndatabase DB\nU -> DB : oi\n@enduml")
  end

  test "sequência do PlantUML continua indo para sequência" do
    {ast, _source, _warnings} = convert!("@startuml\nparticipant A\nA -> B : oi\n@enduml")
    assert ast.kind == :sequence
  end

  test "formas de declaração, setas e contêineres aninhados" do
    {ast, _source, warnings} =
      convert!("""
      @startuml
      left to right direction
      actor "Usuário" as U
      node "Kubernetes" {
        package "Backend" {
          component api as "API Gateway" <<rest>>
          [Worker]
        }
        queue Kafka
        database "Orders DB" as db #lightblue
      }
      U --> api : HTTPS
      api ..> Kafka : publica
      Kafka -down-> [Worker]
      db <-- [Worker] : grava
      api -[dashed]-> db
      @enduml
      """)

    assert warnings == []
    assert %{label: "API Gateway", group: "Backend"} = node(ast, "api")
    assert %{kind: :queue, group: "Kubernetes"} = node(ast, "Kafka")
    assert %{kind: :database, label: "Orders DB"} = node(ast, "db")
    assert %{group: "Backend"} = node(ast, "Worker")

    arrows = ast.steps |> Enum.flat_map(& &1.items) |> Map.new(&{{&1.from, &1.to}, &1.arrow})

    assert arrows[{"U", "api"}] == :sync
    assert arrows[{"api", "Kafka"}] == :async
    assert arrows[{"Kafka", "Worker"}] == :sync
    assert arrows[{"Worker", "db"}] == :sync
    assert arrows[{"api", "db"}] == :async
  end

  test "seta para um grupo inteiro vira aviso" do
    {_ast, _source, warnings} =
      convert!("""
      @startuml
      package "Dados" as D {
        [Postgres]
      }
      [API] --> D
      [API] --> [Postgres]
      @enduml
      """)

    assert [{_line, "seta para o grupo `D`" <> _}] = warnings
  end
end
