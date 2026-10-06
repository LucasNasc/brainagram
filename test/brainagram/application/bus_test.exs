defmodule Brainagram.Application.BusTest do
  @moduledoc """
  Testes de comando e query com repositório em memória.

  Nenhum destes toca o banco: as portas são trocadas no processo do teste. É o
  que permite `async: true` numa suíte que exercita escrita, leitura e eventos.
  """

  use ExUnit.Case, async: true

  alias Brainagram.Application.Bus

  alias Brainagram.Application.Commands.{
    ChangeDiagramSource,
    ChangeDiagramVisibility,
    CreateDiagram,
    DeleteDiagram,
    ForkDiagram
  }

  alias Brainagram.Application.Commands.{
    AddNode,
    ChangeEdgeArrow,
    ClearLayoutHints,
    ConnectNodes,
    MoveNodeToGroup,
    PinNode,
    RelabelEdge,
    RemoveEdge,
    RemoveNode,
    RenameNodeLabel,
    UntangleLayout
  }

  alias Brainagram.Application.Queries.{EditSource, ImportDiagram}
  alias Brainagram.Application.Queries.{GetExample, ListExamples, RenderScene}
  alias Brainagram.Domain.Diagramming.{Diagram, Events}
  alias Brainagram.Test.Fixtures
  alias Brainagram.Test.InMemoryDiagramRepository, as: Repo

  @valid ~s(diagram sequence "Checkout"\nuser -> api : POST /orders)

  setup do
    Repo.install()
    :ok
  end

  describe "validação da mensagem" do
    test "comando sem campo obrigatório falha antes de chegar ao handler" do
      assert {:error, %Ecto.Changeset{} = changeset} = Bus.dispatch(CreateDiagram, %{})
      assert %{source: ["can't be blank"]} = Bus.validation_errors(changeset)
      assert Repo.all() == []
    end

    test "aceita chaves em átomo e em string" do
      assert {:ok, _slug} = Bus.dispatch(CreateDiagram, %{"source" => @valid})
      assert {:ok, _slug} = Bus.dispatch(CreateDiagram, %{source: @valid})
    end
  end

  describe "CreateDiagram" do
    test "cria, devolve o slug e publica o evento" do
      assert {:ok, slug} = Bus.dispatch(CreateDiagram, %{source: @valid})
      assert is_binary(slug)

      assert_received {:domain_event, %Events.DiagramCreated{title: "Checkout", kind: "sequence"}}
    end

    test "o agregado não vaza para fora da camada de aplicação" do
      assert {:ok, result} = Bus.dispatch(CreateDiagram, %{source: @valid})
      refute is_struct(result)
    end

    test "fonte inválido não cria nada nem publica evento" do
      assert {:error, {:syntax, _}} = Bus.dispatch(CreateDiagram, %{source: "nada disso"})
      assert Repo.all() == []
      refute_received {:domain_event, _}
    end

    test "slug repetido é recusado pelo repositório" do
      assert {:ok, _} = Bus.dispatch(CreateDiagram, %{source: @valid, slug: "duplicado"})

      assert {:error, :slug_taken} =
               Bus.dispatch(CreateDiagram, %{source: @valid, slug: "duplicado"})
    end
  end

  describe "ChangeDiagramSource" do
    setup do
      {:ok, slug} = Bus.dispatch(CreateDiagram, %{source: @valid, slug: "alvo"})
      flush()
      %{slug: slug}
    end

    test "grava e publica quando o fonte muda", %{slug: slug} do
      novo = ~s(diagram architecture "Plataforma"\napi -> db)

      assert {:ok, ^slug} = Bus.dispatch(ChangeDiagramSource, %{slug: slug, source: novo})
      assert_received {:domain_event, %Events.DiagramSourceChanged{kind: "architecture"}}
    end

    test "fonte idêntico não publica evento", %{slug: slug} do
      assert {:ok, ^slug} = Bus.dispatch(ChangeDiagramSource, %{slug: slug, source: @valid})
      refute_received {:domain_event, _}
    end

    test "slug inexistente", %{} do
      assert {:error, :not_found} =
               Bus.dispatch(ChangeDiagramSource, %{slug: "nao-existe", source: @valid})
    end

    test "slug fora do formato é recusado antes de ir ao banco" do
      assert {:error, :invalid_slug} =
               Bus.dispatch(ChangeDiagramSource, %{slug: "A B", source: @valid})
    end
  end

  describe "ChangeDiagramVisibility e ForkDiagram" do
    setup do
      {:ok, slug} = Bus.dispatch(CreateDiagram, %{source: @valid, slug: "publicado"})
      flush()
      %{slug: slug}
    end

    test "despublica", %{slug: slug} do
      assert {:ok, ^slug} =
               Bus.dispatch(ChangeDiagramVisibility, %{slug: slug, visibility: "private"})

      assert_received {:domain_event, %Events.DiagramVisibilityChanged{visibility: "private"}}
    end

    test "bifurca sob slug novo e privado", %{slug: slug} do
      assert {:ok, copia} = Bus.dispatch(ForkDiagram, %{slug: slug})
      refute copia == slug

      assert_received {:domain_event, %Events.DiagramCreated{visibility: "private"}}
      assert_received {:domain_event, %Events.DiagramForked{origin_slug: "publicado"}}
      assert length(Repo.all()) == 2
    end

    test "remove e publica DiagramDeleted", %{slug: slug} do
      assert {:ok, ^slug} = Bus.dispatch(DeleteDiagram, %{slug: slug})
      assert_received {:domain_event, %Events.DiagramDeleted{slug: ^slug}}
      assert Repo.all() == []
    end
  end

  describe "queries" do
    test "RenderScene compila sem tocar no repositório" do
      assert {:ok, scene} = Bus.ask(RenderScene, %{source: @valid})
      assert scene.kind == :sequence
      assert Repo.all() == []
    end

    test "RenderScene devolve todos os erros de sintaxe de uma vez" do
      assert {:error, {:syntax, errors}} =
               Bus.ask(RenderScene, %{source: "linha ruim um\nlinha ruim dois"})

      assert Enum.map(errors, & &1.line) == [1, 2]
    end

    test "query de leitura não publica evento" do
      assert {:ok, _} = Bus.ask(RenderScene, %{source: @valid})
      refute_received {:domain_event, _}
    end

    test "ListExamples e GetExample" do
      assert {:ok, [_ | _] = examples} = Bus.ask(ListExamples)
      primeiro = List.first(examples)

      assert {:ok, example} = Bus.ask(GetExample, %{slug: primeiro.slug})
      assert example.source == primeiro.source
      assert {:error, :not_found} = Bus.ask(GetExample, %{slug: "inexistente"})
    end
  end

  describe "comandos de autoria (spec 001, §6)" do
    @arch """
    diagram architecture "Plataforma"
    # comentário que tem que sobreviver
    service  api "API"
    database pg  "PostgreSQL"

    group "Dados" {
      queue mq "RabbitMQ"
    }

    step "Leitura" {
      api -> pg : SELECT
    }
    """

    setup do
      {:ok, slug} = Bus.dispatch(CreateDiagram, %{source: @arch, slug: "autoria"})
      flush()
      %{slug: slug}
    end

    # O leitor de produção é Ecto; aqui o estado está no repositório em memória.
    defp stored(slug), do: Enum.find(Repo.all(), &(Diagram.slug_string(&1) == slug))
    defp source_of(slug), do: stored(slug).source.raw
    defp first_edge(slug), do: hd(Diagram.scene(stored(slug)).edges).id

    test "RenameNodeLabel grava, publica e preserva o resto", %{slug: slug} do
      assert {:ok, ^slug} =
               Bus.dispatch(RenameNodeLabel, %{slug: slug, node_id: "pg", label: "Postgres"})

      assert source_of(slug) == String.replace(@arch, ~s("PostgreSQL"), ~s("Postgres"))
      assert_received {:domain_event, %Events.DiagramSourceChanged{slug: ^slug}}
    end

    test "RelabelEdge e ChangeEdgeArrow", %{slug: slug} do
      edge = first_edge(slug)
      assert {:ok, _} = Bus.dispatch(RelabelEdge, %{slug: slug, edge_id: edge, label: "SELECT *"})

      assert {:ok, _} =
               Bus.dispatch(ChangeEdgeArrow, %{slug: slug, edge_id: edge, arrow: "async"})

      assert source_of(slug) =~ "api ->> pg : SELECT *"
    end

    test "ChangeEdgeArrow valida o tipo na fronteira", %{slug: slug} do
      assert {:error, %Ecto.Changeset{}} =
               Bus.dispatch(ChangeEdgeArrow, %{slug: slug, edge_id: "e1", arrow: "=>"})
    end

    test "AddNode e ConnectNodes", %{slug: slug} do
      assert {:ok, _} =
               Bus.dispatch(AddNode, %{
                 slug: slug,
                 label: "Cache",
                 kind: "database",
                 x: 400,
                 y: 80
               })

      assert {:ok, _} =
               Bus.dispatch(ConnectNodes, %{slug: slug, from: "api", to: "cache", label: "GET"})

      source = source_of(slug)
      assert source =~ ~s(database cache "Cache")
      assert source =~ "api -> cache : GET"
      assert source =~ "cache at (400, 80)"
    end

    test "PinNode, depois ClearLayoutHints devolve o texto original", %{slug: slug} do
      assert {:ok, _} = Bus.dispatch(PinNode, %{slug: slug, node_id: "pg", x: 420, y: 680})
      assert source_of(slug) =~ "pg at (420, 680)"

      assert {:ok, _} = Bus.dispatch(ClearLayoutHints, %{slug: slug})
      assert source_of(slug) == @arch
    end

    test "UntangleLayout grava a arrumação; repetir não grava nem publica" do
      {:ok, slug} =
        Bus.dispatch(CreateDiagram, %{
          source: Fixtures.tangled_architecture_source(),
          slug: "emaranhado"
        })

      assert {:ok, ^slug} = Bus.dispatch(UntangleLayout, %{slug: slug})
      assert source_of(slug) =~ "layout {"
      flush()

      assert {:ok, ^slug} = Bus.dispatch(UntangleLayout, %{slug: slug})
      refute_received {:domain_event, _}
    end

    test "arrastar e soltar no mesmo lugar não grava nem publica", %{slug: slug} do
      {:ok, _} = Bus.dispatch(PinNode, %{slug: slug, node_id: "pg", x: 10, y: 10})
      flush()

      assert {:ok, ^slug} = Bus.dispatch(PinNode, %{slug: slug, node_id: "pg", x: 10, y: 10})
      refute_received {:domain_event, _}
    end

    test "MoveNodeToGroup, RemoveEdge e RemoveNode", %{slug: slug} do
      assert {:ok, _} =
               Bus.dispatch(MoveNodeToGroup, %{slug: slug, node_id: "pg", group: "Dados"})

      assert source_of(slug) =~ ~s(  queue mq "RabbitMQ"
  database pg  "PostgreSQL"
}
)

      assert {:ok, _} = Bus.dispatch(RemoveEdge, %{slug: slug, edge_id: first_edge(slug)})
      refute source_of(slug) =~ "SELECT"

      assert {:ok, _} = Bus.dispatch(RemoveNode, %{slug: slug, node_id: "mq"})
      refute source_of(slug) =~ "RabbitMQ"
      assert source_of(slug) =~ "# comentário que tem que sobreviver"
    end

    test "gesto sobre nó inexistente falha sem gravar", %{slug: slug} do
      assert {:error, :unknown_node} = Bus.dispatch(RemoveNode, %{slug: slug, node_id: "nada"})
      assert source_of(slug) == @arch
      refute_received {:domain_event, _}
    end
  end

  describe "EditSource e ImportDiagram" do
    test "EditSource devolve o texto novo, a cena e o que foi criado, sem gravar" do
      assert {:ok, %{source: source, scene: scene, meta: %{node_id: "cache"}}} =
               Bus.ask(EditSource, %{
                 source: @valid,
                 op: "add_node",
                 params: %{"label" => "Cache"}
               })

      assert source =~ ~s(participant cache "Cache")
      assert Enum.any?(scene.nodes, &(&1.id == "cache"))
      assert Repo.all() == []
      refute_received {:domain_event, _}
    end

    test "EditSource recusa operação desconhecida na fronteira" do
      assert {:error, %Ecto.Changeset{}} = Bus.ask(EditSource, %{source: @valid, op: "explodir"})
    end

    test "ImportDiagram converte componentes do PlantUML e organiza as setas se pedido" do
      text = Fixtures.plantuml_component_source()

      assert {:ok, %{source: plain, organized: nil}} = Bus.ask(ImportDiagram, %{text: text})
      assert plain =~ "diagram architecture"
      refute plain =~ "layout {"

      assert {:ok, %{source: organized, organized: %{before: before, after: after_}}} =
               Bus.ask(ImportDiagram, %{text: text, organize: true})

      assert organized =~ "layout {"
      assert after_.crossings < before.crossings
    end

    test "ImportDiagram converte Mermaid" do
      assert {:ok, %{source: source, format: :mermaid}} =
               Bus.ask(ImportDiagram, %{text: "sequenceDiagram
A->>B: oi"})

      assert source =~ "A -> B : oi"
    end
  end

  defp flush do
    receive do
      {:domain_event, _} -> flush()
    after
      0 -> :ok
    end
  end
end
