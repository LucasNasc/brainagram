defmodule Brainagram.Infrastructure.ProjectsPersistenceTest do
  @moduledoc """
  Projetos contra o Postgres real: o `join` que traz nome e cor para o card,
  os filtros da área de gestão, a contagem por projeto e a chave estrangeira.
  """

  use Brainagram.DataCase, async: true

  alias Brainagram.Domain.Diagramming.{Diagram, Project}
  alias Brainagram.Domain.Diagramming.ValueObjects.{ProjectName, Slug}
  alias Brainagram.Infrastructure.Persistence.EctoDiagramReader, as: Reader
  alias Brainagram.Infrastructure.Persistence.EctoDiagramRepository, as: Diagrams
  alias Brainagram.Infrastructure.Persistence.EctoProjectReader, as: ProjectReader
  alias Brainagram.Infrastructure.Persistence.EctoProjectRepository, as: Projects

  defp project!(name, color \\ "violet") do
    {:ok, project, _} = Project.create(%{name: name, color: color})
    {:ok, saved} = Projects.insert(project)
    saved
  end

  defp diagram!(title, attrs \\ %{}) do
    kind = Map.get(attrs, :kind, "sequence")
    source = ~s(diagram #{kind} "#{title}"\na -> b : oi)
    {:ok, diagram, _} = Diagram.create(Map.merge(%{source: source}, Map.delete(attrs, :kind)))
    {:ok, saved} = Diagrams.insert(diagram)
    saved
  end

  defp slug(%Project{} = p), do: Project.slug_string(p)
  defp titles(list), do: Enum.map(list, & &1.title)

  describe "repositório de projetos" do
    test "vai e volta; renomear grava" do
      saved = project!("Pagamentos", "teal")

      assert {:ok, loaded} = Projects.fetch_by_slug(saved.slug)
      assert ProjectName.to_string(loaded.name) == "Pagamentos"
      assert loaded.color == :teal

      {:ok, renamed, _} = Project.update(loaded, %{name: "Cobrança"})
      assert {:ok, _} = Projects.update(renamed)
      assert {:ok, %{name: %{value: "Cobrança"}}} = Projects.fetch_by_slug(saved.slug)
    end

    test "delete remove" do
      saved = project!("Temporário")
      assert :ok = Projects.delete(saved)
      assert {:error, :not_found} = Projects.fetch_by_slug(saved.slug)
    end
  end

  describe "diagramas nos projetos" do
    test "o diagrama grava e lê o projeto; projeto inexistente é recusado pelo banco" do
      project = project!("Pagamentos")
      saved = diagram!("Checkout", %{project: slug(project)})

      assert {:ok, loaded} = Diagrams.fetch_by_slug(saved.slug)
      assert Slug.to_string(loaded.project) == slug(project)

      {:ok, orphan, _} = Diagram.create(%{source: "a -> b", project: "fantasma"})
      assert {:error, :project_not_found} = Diagrams.insert(orphan)
    end

    test "detach_project tira todos do projeto e devolve quem saiu" do
      project = project!("Pagamentos")
      a = diagram!("A", %{project: slug(project)})
      b = diagram!("B")

      assert {:ok, [moved]} = Diagrams.detach_project(project.slug)
      assert moved == Diagram.slug_string(a)
      assert {:ok, %{project: nil}} = Diagrams.fetch_by_slug(a.slug)
      assert {:ok, %{project: nil}} = Diagrams.fetch_by_slug(b.slug)
    end

    test "excluir o projeto direto no banco também deixa os diagramas sem projeto" do
      project = project!("Pagamentos")
      a = diagram!("A", %{project: slug(project)})

      assert :ok = Projects.delete(project)
      assert {:ok, %{project: nil}} = Diagrams.fetch_by_slug(a.slug)
    end
  end

  describe "leitores" do
    setup do
      pay = project!("Pagamentos", "teal")
      ops = project!("Operação", "amber")

      diagram!("Checkout", %{project: slug(pay)})
      diagram!("Estorno", %{project: slug(pay), kind: "architecture"})
      diagram!("Deploy", %{project: slug(ops)})
      diagram!("Rascunho solto")

      %{pay: pay, ops: ops}
    end

    test "projetos em ordem alfabética, com a contagem de cada um", %{pay: pay} do
      projects = ProjectReader.list()

      assert [%{name: "Operação", diagram_count: 1}, %{name: "Pagamentos", diagram_count: 2}] =
               Enum.filter(projects, &(&1.name in ["Operação", "Pagamentos"]))

      assert {:ok, %{name: "Pagamentos", color: "teal"}} = ProjectReader.fetch_by_slug(slug(pay))
    end

    test "contagem geral e sem projeto" do
      assert %{all: all, none: none} = Reader.counts()
      assert all >= 4 and none >= 1
    end

    test "filtra por projeto, sem projeto, tipo e busca", %{pay: pay} do
      assert titles(Reader.list(%{project: slug(pay), sort: :title})) == ["Checkout", "Estorno"]
      assert "Rascunho solto" in titles(Reader.list(%{project: :none}))
      refute "Checkout" in titles(Reader.list(%{project: :none}))

      assert titles(Reader.list(%{project: slug(pay), kind: "architecture"})) == ["Estorno"]
      assert titles(Reader.list(%{search: "ESTOR"})) == ["Estorno"]
      # curinga do LIKE digitado pela pessoa é texto, não padrão
      assert Reader.list(%{search: "%"}) == []
    end

    test "o card já vem com nome e cor do projeto, e sem o fonte", %{pay: pay} do
      [summary | _] = Reader.list(%{project: slug(pay)})

      assert summary.project == slug(pay)
      assert summary.project_name == "Pagamentos"
      assert summary.project_color == "teal"
      refute Map.has_key?(summary, :source)
    end

    test "o detalhe traz o projeto para o editor", %{ops: ops} do
      [deploy] = Reader.list(%{project: slug(ops)})

      assert {:ok, %{project_name: "Operação", project_color: "amber"}} =
               Reader.fetch_by_slug(deploy.slug)
    end
  end
end
