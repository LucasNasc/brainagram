defmodule Brainagram.Application.ProjectsTest do
  @moduledoc "Comandos da área de gestão, com os repositórios em memória."

  use ExUnit.Case, async: true

  alias Brainagram.Application.Bus

  alias Brainagram.Application.Commands.{
    CreateDiagram,
    CreateProject,
    DeleteProject,
    ForkDiagram,
    MoveDiagram,
    RenameDiagram,
    StartDiagram,
    UpdateProject
  }

  alias Brainagram.Domain.Diagramming.{Diagram, Events, Project}
  alias Brainagram.Domain.Diagramming.ValueObjects.{ProjectName, Slug}
  alias Brainagram.Test.InMemoryDiagramRepository, as: Diagrams
  alias Brainagram.Test.InMemoryProjectRepository, as: Projects

  setup do
    Diagrams.install()
    :ok
  end

  defp diagram(slug), do: Enum.find(Diagrams.all(), &(Diagram.slug_string(&1) == slug))
  defp project(slug), do: Enum.find(Projects.all(), &(Project.slug_string(&1) == slug))
  defp project_of(slug), do: diagram(slug).project && Slug.to_string(diagram(slug).project)

  defp flush do
    receive do
      {:domain_event, _} -> flush()
    after
      0 -> :ok
    end
  end

  describe "projetos" do
    test "criar, renomear, recolorir" do
      assert {:ok, slug} = Bus.dispatch(CreateProject, %{name: "Pagamentos", color: "teal"})
      assert_received {:domain_event, %Events.ProjectCreated{project: ^slug}}

      assert {:ok, ^slug} = Bus.dispatch(UpdateProject, %{slug: slug, name: "Cobrança"})
      assert ProjectName.to_string(project(slug).name) == "Cobrança"
      assert project(slug).color == :teal
    end

    test "atualizar sem mudar nada não publica" do
      {:ok, slug} = Bus.dispatch(CreateProject, %{name: "A"})
      flush()

      assert {:ok, ^slug} = Bus.dispatch(UpdateProject, %{slug: slug, name: "A"})
      refute_received {:domain_event, _}
    end

    test "nome inválido e projeto inexistente viram erro de domínio" do
      # em branco, a própria mensagem barra; longo demais, o agregado
      assert {:error, %Ecto.Changeset{}} = Bus.dispatch(CreateProject, %{name: " "})

      assert {:error, :project_name_too_long} =
               Bus.dispatch(CreateProject, %{name: String.duplicate("a", 61)})

      assert {:error, :project_not_found} =
               Bus.dispatch(UpdateProject, %{slug: "nada-aqui", name: "x"})

      assert {:error, :project_not_found} = Bus.dispatch(DeleteProject, %{slug: "nada-aqui"})
    end

    test "excluir o projeto não apaga os diagramas: eles ficam sem projeto" do
      {:ok, project} = Bus.dispatch(CreateProject, %{name: "Pagamentos"})
      {:ok, a} = Bus.dispatch(CreateDiagram, %{source: "a -> b", project: project})
      {:ok, b} = Bus.dispatch(CreateDiagram, %{source: "c -> d"})
      flush()

      assert {:ok, ^project} = Bus.dispatch(DeleteProject, %{slug: project})

      assert project(project) == nil
      assert length(Diagrams.all()) == 2
      assert project_of(a) == nil
      assert project_of(b) == nil

      assert_received {:domain_event, %Events.DiagramMoved{slug: ^a, previous_project: ^project}}
      assert_received {:domain_event, %Events.ProjectDeleted{project: ^project}}
      refute_received {:domain_event, %Events.DiagramMoved{slug: ^b}}
    end
  end

  describe "diagramas nos projetos" do
    setup do
      {:ok, project} = Bus.dispatch(CreateProject, %{name: "Pagamentos"})
      %{project: project}
    end

    test "começar um diagrama: modelo do tipo, título no fonte, no projeto", %{project: project} do
      assert {:ok, slug} =
               Bus.dispatch(StartDiagram, %{
                 title: "Checkout",
                 kind: "architecture",
                 project: project,
                 lang: "en"
               })

      saved = diagram(slug)
      assert Diagram.title_string(saved) == "Checkout"
      assert saved.kind == :architecture
      assert project_of(slug) == project
    end

    test "tipo e idioma fora da lista são recusados na mensagem" do
      assert {:error, %Ecto.Changeset{}} =
               Bus.dispatch(StartDiagram, %{title: "x", kind: "mindmap"})

      assert {:error, :project_not_found} =
               Bus.dispatch(StartDiagram, %{title: "x", project: "sumiu-daqui"})
    end

    test "mover entre projetos e para fora de qualquer um", %{project: project} do
      {:ok, slug} = Bus.dispatch(CreateDiagram, %{source: "a -> b"})

      assert {:ok, ^slug} = Bus.dispatch(MoveDiagram, %{slug: slug, project: project})
      assert project_of(slug) == project

      assert {:ok, ^slug} = Bus.dispatch(MoveDiagram, %{slug: slug, project: ""})
      assert project_of(slug) == nil

      assert {:error, :project_not_found} =
               Bus.dispatch(MoveDiagram, %{slug: slug, project: "nao-existe"})
    end

    test "renomear edita o cabeçalho do fonte", %{project: project} do
      {:ok, slug} = Bus.dispatch(StartDiagram, %{title: "Antigo", project: project})

      assert {:ok, ^slug} = Bus.dispatch(RenameDiagram, %{slug: slug, title: "Novo"})
      assert Diagram.title_string(diagram(slug)) == "Novo"
      assert diagram(slug).source.raw =~ ~s(diagram sequence "Novo")
    end

    test "duplicar mantém o projeto", %{project: project} do
      {:ok, slug} = Bus.dispatch(StartDiagram, %{title: "A", project: project})
      assert {:ok, copy} = Bus.dispatch(ForkDiagram, %{slug: slug})
      assert project_of(copy) == project
    end
  end
end
