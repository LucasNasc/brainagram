defmodule BrainagramWeb.EditorModesTest do
  @moduledoc """
  Apresentação × edição, trabalho não salvo e o que os passos contam — o que a
  crítica de design do editor pediu (o público pesa o mesmo que o autor).
  """

  use BrainagramWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Brainagram.Application.Bus
  alias Brainagram.Application.Commands.{ChangeDiagramVisibility, CreateDiagram}

  @source ~s(diagram sequence "Pedido"\n\nactor cliente "Cliente"\nservice api "API"\n\nstep "Envia" {\n  cliente -> api : POST /pedido\n  api --> cliente : 201\n}\n)

  defp saved!(source \\ @source) do
    {:ok, slug} = Bus.dispatch(CreateDiagram, %{source: source})
    slug
  end

  describe "apresentação" do
    test "Editar abre o editor e Apresentar volta, sem perder o texto", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/d/#{saved!()}")

      view |> element("#edit-diagram") |> render_click()
      assert has_element?(view, "#editor[data-presenting=false]")

      view
      |> element("form[phx-change=edit]")
      |> render_change(%{"source" => String.replace(@source, "POST", "PUT")})

      view |> element("#present-diagram") |> render_click()
      assert has_element?(view, "#editor[data-presenting=true]")
      assert has_element?(view, "[data-bg-msg]", "PUT /pedido")
    end

    test "a tecla P (present:toggle) alterna o modo", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/d/#{saved!()}")

      render_hook(view, "present:toggle", %{})
      assert has_element?(view, "#editor[data-presenting=false]")
      render_hook(view, "present:toggle", %{})
      assert has_element?(view, "#editor[data-presenting=true]")
    end

    test "/new abre no editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new")
      assert has_element?(view, "#editor[data-presenting=false]")
      assert has_element?(view, "#present-diagram")
    end

    test "salvar no editor continua no editor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/d/#{saved!()}?edit=1")

      view
      |> element("form[phx-change=edit]")
      |> render_change(%{"source" => String.replace(@source, "201", "202")})

      view |> element("#save-button") |> render_click()
      assert_patch(view)
      assert has_element?(view, "#editor[data-presenting=false]")
    end
  end

  describe "trabalho não salvo" do
    test "editar marca alterações não salvas e destaca o Salvar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/d/#{saved!()}?edit=1")

      assert has_element?(view, "#editor[data-dirty=false]")
      refute has_element?(view, "#unsaved-marker")
      refute has_element?(view, "#save-button.ba-btn--primary")

      view
      |> element("form[phx-change=edit]")
      |> render_change(%{"source" => String.replace(@source, "201", "200")})

      assert has_element?(view, "#editor[data-dirty=true]")
      assert has_element?(view, "#unsaved-marker")
      assert has_element?(view, "#save-button.ba-btn--primary")
      # sair pelo logo ou pela trilha pede confirmação
      assert has_element?(view, "#back-to-dashboard[data-confirm]")
      assert has_element?(view, "#breadcrumb-project[data-confirm]")
    end

    test "carregar um exemplo num diagrama novo não conta como alteração", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new")

      view |> element("button[phx-value-slug=arquitetura]") |> render_click()

      assert has_element?(view, "#editor[data-dirty=false]")
    end

    test "trocar um diagrama salvo por exemplo e torná-lo público pedem confirmação", %{
      conn: conn
    } do
      slug = saved!()
      {:ok, _} = Bus.dispatch(ChangeDiagramVisibility, %{slug: slug, visibility: "private"})
      {:ok, view, _html} = live(conn, ~p"/d/#{slug}?edit=1")

      assert has_element?(view, "button[phx-value-slug=arquitetura][data-confirm]")
      assert has_element?(view, "#visibility-toggle[data-confirm]")
    end
  end

  describe "passos e código" do
    test "os passos mostram só os tópicos; as mensagens ficam para leitor de tela", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/d/#{saved!()}")

      assert has_element?(view, "#steps-pane .ba-sr [data-bg-msg]", "Cliente → API")
      assert has_element?(view, "#steps-pane .ba-sr [data-bg-msg]", "POST /pedido")
      refute has_element?(view, "#steps-pane button [data-bg-msg]")
      assert has_element?(view, "#steps-pane [data-bg-step-bar]")
      # o anúncio do passo para leitor de tela fica fora da gaveta
      assert has_element?(view, "#editor > p.ba-sr[aria-live=polite][data-bg-display=step]")
    end

    test "erro de sintaxe: selo vira botão e o código fica aria-invalid", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new")

      view
      |> element("form[phx-change=edit]")
      |> render_change(%{"source" => "diagram sequence \"X\"\nlinha invalida"})

      assert has_element?(view, "button#goto-error")
      assert has_element?(view, "#source[aria-invalid=true][aria-describedby=source-errors]")
      assert has_element?(view, "#source-errors", "Cada linha declara um nó")
    end

    test "o código não quebra linhas e tem a calha de números", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new")

      assert has_element?(view, "#source[wrap=off]")
      assert has_element?(view, "#source-gutter[aria-hidden=true]")
    end
  end
end
