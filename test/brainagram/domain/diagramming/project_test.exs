defmodule Brainagram.Domain.Diagramming.ProjectTest do
  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.{Authoring, Diagram, Events, Project, Scene, Templates}
  alias Brainagram.Domain.Diagramming.ValueObjects.{ProjectName, Slug, Source}
  alias Brainagram.Test.Fixtures

  describe "Project.create/1" do
    test "nome limpo, cor padrão e slug gerado" do
      assert {:ok, project, [%Events.ProjectCreated{name: "Pagamentos", color: "violet"}]} =
               Project.create(%{name: "  Pagamentos   "})

      assert ProjectName.to_string(project.name) == "Pagamentos"
      assert %Slug{} = project.slug
    end

    test "nome em branco, longo demais e cor fora da paleta são recusados" do
      assert {:error, :blank_project_name} = Project.create(%{name: "   "})
      assert {:error, :blank_project_name} = Project.create(%{})
      assert {:error, :project_name_too_long} = Project.create(%{name: String.duplicate("a", 61)})
      assert {:error, :invalid_project_color} = Project.create(%{name: "x", color: "neon"})
    end
  end

  describe "Project.update/2" do
    setup do
      {:ok, project, _} = Project.create(%{name: "Pagamentos", color: "blue"})
      %{project: project}
    end

    test "muda nome e cor, com evento", %{project: project} do
      assert {:ok, updated, [%Events.ProjectUpdated{name: "Cobrança", color: "rose"}]} =
               Project.update(project, %{name: "Cobrança", color: "rose"})

      assert updated.color == :rose
    end

    test "campo ausente fica; nada diferente, nenhum evento", %{project: project} do
      assert {:ok, same, []} = Project.update(project, %{name: "Pagamentos"})
      assert same == project

      assert {:ok, recolored, [_]} = Project.update(project, %{color: "green"})
      assert ProjectName.to_string(recolored.name) == "Pagamentos"
    end
  end

  describe "diagrama e projeto" do
    test "move_to_project/2 muda a referência e conta de onde saiu" do
      diagram = Fixtures.diagram!()
      {:ok, target} = Slug.new("pagamentos")

      assert {:ok, moved, [%Events.DiagramMoved{project: "pagamentos", previous_project: nil}]} =
               Diagram.move_to_project(diagram, target)

      assert {:ok, ^moved, []} = Diagram.move_to_project(moved, "pagamentos")

      assert {:ok, %{project: nil}, [%Events.DiagramMoved{previous_project: "pagamentos"}]} =
               Diagram.move_to_project(moved, "")

      assert {:error, :invalid_project} = Diagram.move_to_project(moved, "!!")
    end

    test "create/1 aceita o projeto; a cópia fica no mesmo projeto" do
      assert {:ok, diagram, _} = Diagram.create(%{source: "a -> b", project: "pagamentos"})
      assert Slug.to_string(diagram.project) == "pagamentos"

      assert {:ok, copy, _} = Diagram.fork(diagram)
      assert copy.project == diagram.project
    end
  end

  describe "renomear pelo texto" do
    test "troca só o título entre aspas" do
      source = ~s(diagram sequence "Antigo"   # comentário\na -> b\n)

      assert {:ok, ~s(diagram sequence "Novo nome"   # comentário\na -> b\n)} =
               Authoring.rename_title(source, "Novo nome")
    end

    test "sem título ou sem cabeçalho, o título entra no lugar certo" do
      assert {:ok, ~s(diagram architecture "X"\na -> b)} =
               Authoring.rename_title("diagram architecture\na -> b", "X")

      assert {:ok, ~s(diagram sequence "X"\na -> b)} = Authoring.rename_title("a -> b", "X")
    end

    test "aspas viram aspas tipográficas; em branco é recusado" do
      assert {:ok, renamed} = Authoring.rename_title(~s(diagram sequence "A"), ~s(O "novo"))
      assert renamed =~ "O ”novo”"
      assert {:error, :blank_label} = Authoring.rename_title(~s(diagram sequence "A"), "  ")
    end
  end

  describe "Templates.starter/3" do
    test "os modelos compilam, com o título escolhido e o tipo certo" do
      for kind <- [:sequence, :architecture], lang <- Templates.langs() do
        assert {:ok, source} = Source.new(Templates.starter(kind, ~s(Meu "fluxo"), lang))
        assert Source.kind(source) == kind
        assert Source.scene(source).edges != []
        assert to_string(Source.title(source).value) == "Meu ”fluxo”"
      end
    end

    test "o conteúdo sai no idioma pedido" do
      assert Templates.starter(:sequence, "x", :pt) =~ "Usuário"
      assert Templates.starter(:sequence, "x", :en) =~ "User"
      assert Templates.starter(:sequence, "x", :ja) =~ "ユーザー"
      assert Templates.starter(:architecture, "x", :ru) =~ "База данных"
    end

    test "ideogramas contam quase o dobro na largura estimada" do
      assert Scene.char_units("abc") == 3.0
      assert Scene.char_units("用户") == 3.6
      assert Scene.text_width("数据库", 10) > Scene.text_width("abc", 10)
      assert Scene.char_units(nil) == 0.0
    end
  end
end
