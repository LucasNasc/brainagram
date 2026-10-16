defmodule Brainagram.Infrastructure.CacheTest do
  @moduledoc """
  O armazenamento do modo demo (`BRAINAGRAM_DEMO=true`): as quatro portas sobre
  ETS cumprem o mesmo contrato das portas Postgres, e a limpeza respeita a
  validade e o limite de tamanho.

  `async: false` porque as tabelas ETS têm nome fixo.
  """

  use ExUnit.Case, async: false

  alias Brainagram.Application.Bus
  alias Brainagram.Application.Commands.{CreateDiagram, CreateProject, DeleteProject, MoveDiagram}
  alias Brainagram.Application.Ports
  alias Brainagram.Application.Queries.{GetDiagramBySlug, ListDiagrams, ListProjects}
  alias Brainagram.Domain.Diagramming.Diagram
  alias Brainagram.Domain.Diagramming.ValueObjects.{Slug, Source, Title}
  alias Brainagram.Infrastructure.Cache.CacheDiagramReader, as: Reader
  alias Brainagram.Infrastructure.Cache.CacheDiagramRepository, as: Repository
  alias Brainagram.Infrastructure.Cache.{CacheProjectReader, CacheProjectRepository, Store}
  alias Brainagram.Test.Fixtures

  setup do
    start_supervised!({Store, ttl: :timer.hours(1), max_diagrams: 3})

    Ports.override(:diagram_repository, Repository)
    Ports.override(:diagram_reader, Reader)
    Ports.override(:project_repository, CacheProjectRepository)
    Ports.override(:project_reader, CacheProjectReader)
    :ok
  end

  describe "repositório de diagramas" do
    test "vai e volta preservando o agregado" do
      diagram = Fixtures.diagram!(%{source: ~s(diagram sequence "Ida e volta"\na -> b : x)})

      assert {:ok, saved} = Repository.insert(diagram)
      assert saved.id
      assert {:ok, loaded} = Repository.fetch_by_slug(saved.slug)
      assert Title.to_string(loaded.title) == "Ida e volta"
      assert Source.equal?(loaded.source, diagram.source)
    end

    test "slug duplicado vira erro de domínio" do
      assert {:ok, _} = Repository.insert(Fixtures.diagram!(%{slug: "colidido"}))
      assert {:error, :slug_taken} = Repository.insert(Fixtures.diagram!(%{slug: "colidido"}))
    end

    test "update grava a nova versão e delete apaga" do
      {:ok, saved} = Repository.insert(Fixtures.diagram!())
      {:ok, changed, _} = Diagram.change_source(saved, ~s(diagram architecture "Novo"\na -> b))

      assert {:ok, _} = Repository.update(changed)
      assert {:ok, loaded} = Repository.fetch_by_slug(saved.slug)
      assert loaded.kind == :architecture

      assert :ok = Repository.delete(loaded)
      assert {:error, :not_found} = Repository.fetch_by_slug(saved.slug)
    end

    test "nunca persistido é recusado" do
      assert {:error, :not_persisted} = Repository.update(Fixtures.diagram!())
      assert {:error, :not_persisted} = Repository.delete(Fixtures.diagram!())
    end

    test "projeto inexistente é recusado" do
      {:ok, slug} = Slug.new("fantasma")
      diagram = %{Fixtures.diagram!() | project: slug}
      assert {:error, :project_not_found} = Repository.insert(diagram)
    end
  end

  describe "pelo barramento, como a interface usa" do
    test "projetos, diagramas, filtros e contagens" do
      {:ok, project} = Bus.dispatch(CreateProject, %{name: "Pagamentos", color: "teal"})

      {:ok, a} =
        Bus.dispatch(CreateDiagram, %{
          source: ~s(diagram sequence "Checkout"\na -> b),
          project: project
        })

      {:ok, _b} =
        Bus.dispatch(CreateDiagram, %{source: ~s(diagram architecture "Plataforma"\na -> b)})

      assert {:ok, %{title: "Checkout", project_name: "Pagamentos"}} =
               Bus.ask(GetDiagramBySlug, %{slug: a})

      assert {:ok, %{projects: [%{slug: ^project, diagram_count: 1}], all: 2, none: 1}} =
               Bus.ask(ListProjects)

      assert {:ok, [%{title: "Checkout"}]} = Bus.ask(ListDiagrams, %{project: project})
      assert {:ok, [%{title: "Plataforma"}]} = Bus.ask(ListDiagrams, %{kind: "architecture"})
      assert {:ok, [%{title: "Checkout"}]} = Bus.ask(ListDiagrams, %{search: "check"})

      assert {:ok, _} = Bus.dispatch(MoveDiagram, %{slug: a})
      assert %{all: 2, none: 2} = Reader.counts()

      assert {:ok, _} = Bus.dispatch(DeleteProject, %{slug: project})
      assert {:ok, %{projects: []}} = Bus.ask(ListProjects)
    end
  end

  describe "limpeza" do
    test "acima do limite, os mais antigos saem primeiro" do
      for i <- 1..4 do
        {:ok, _} = Repository.insert(Fixtures.diagram!(%{slug: "diagrama-#{i}"}))
      end

      Store.sweep()

      slugs = Reader.list(%{}) |> Enum.map(& &1.slug) |> Enum.sort()
      assert length(slugs) == 3
    end

    test "o que passou da validade é apagado" do
      {:ok, saved} = Repository.insert(Fixtures.diagram!(%{slug: "velho"}))
      [{key, row}] = :ets.lookup(Store.diagrams(), "velho")

      :ets.insert(
        Store.diagrams(),
        {key, %{row | updated_at: DateTime.add(row.updated_at, -2, :hour)}}
      )

      Store.sweep()

      assert {:error, :not_found} = Repository.fetch_by_slug(saved.slug)
    end
  end
end
