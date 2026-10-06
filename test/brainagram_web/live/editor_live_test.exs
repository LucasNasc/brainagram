defmodule BrainagramWeb.EditorLiveTest do
  use BrainagramWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Brainagram.Application.Bus
  alias Brainagram.Application.Commands.CreateDiagram
  alias Brainagram.Application.Queries.{GetDiagramBySlug, ListPublicDiagrams}

  test "monta com o primeiro exemplo do catálogo", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/new")

    assert html =~ "Brainagram"
    assert html =~ "Checkout com pagamento assíncrono"
    assert render(view) =~ "Passos"
  end

  test "editar recompila a cena pela query RenderScene", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")

    html =
      view
      |> element("form[phx-change=edit]")
      |> render_change(%{"source" => ~s(diagram sequence "Novo"\na -> b : oi)})

    assert html =~ "Novo"
    assert html =~ "Sem erros"
  end

  test "erro de sintaxe mostra a linha e preserva a última cena válida", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")

    html =
      view
      |> element("form[phx-change=edit]")
      |> render_change(%{"source" => "diagram sequence \"X\"\nlinha invalida"})

    assert html =~ "Linha 2"
    assert html =~ "não entendi esta linha"
    assert html =~ "Checkout com pagamento assíncrono"
  end

  test "trocar de exemplo", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")

    html = view |> element("button[phx-value-slug=arquitetura]") |> render_click()

    assert html =~ "Plataforma"
    assert view |> element(".ba-editor__kindbadge") |> render() =~ "Arquitetura"
  end

  test "salvar despacha CreateDiagram e navega para o link", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")

    view
    |> element("form[phx-change=edit]")
    |> render_change(%{"source" => ~s(diagram sequence "Salvo"\na -> b)})

    view |> element("button[phx-click=save]") |> render_click()

    assert {:ok, [summary]} = Bus.ask(ListPublicDiagrams, %{})
    assert summary.title == "Salvo"
    assert summary.kind == "sequence"
    assert_patch(view, ~p"/d/#{summary.slug}")
  end

  test "abrir um diagrama salvo pelo slug", %{conn: conn} do
    {:ok, slug} =
      Bus.dispatch(CreateDiagram, %{source: ~s(diagram sequence "Persistido"\nx -> y)})

    {:ok, _view, html} = live(conn, ~p"/d/#{slug}")

    assert html =~ "Persistido"
    assert html =~ "Público"
  end

  test "alternar visibilidade despacha o comando", %{conn: conn} do
    {:ok, slug} = Bus.dispatch(CreateDiagram, %{source: ~s(diagram sequence "Visível"\nx -> y)})
    {:ok, view, _html} = live(conn, ~p"/d/#{slug}")

    view |> element("button[phx-click=toggle-visibility]") |> render_click()

    assert {:ok, detail} = Bus.ask(GetDiagramBySlug, %{slug: slug})
    assert detail.visibility == "private"
  end

  test "duplicar cria uma cópia e leva o usuário para ela", %{conn: conn} do
    {:ok, slug} = Bus.dispatch(CreateDiagram, %{source: ~s(diagram sequence "Original"\nx -> y)})
    {:ok, view, _html} = live(conn, ~p"/d/#{slug}")

    view |> element("button[phx-click=fork]") |> render_click()

    assert_patch(view)
    assert {:ok, original} = Bus.ask(GetDiagramBySlug, %{slug: slug})
    assert original.visibility == "public"
  end

  test "salvar sem alteração não quebra nada", %{conn: conn} do
    {:ok, slug} = Bus.dispatch(CreateDiagram, %{source: ~s(diagram sequence "Estável"\nx -> y)})
    {:ok, view, _html} = live(conn, ~p"/d/#{slug}")

    html = view |> element("button[phx-click=save]") |> render_click()

    assert html =~ "Estável" or render(view) =~ "Estável"
  end

  test "exportar oferece SVG, PNG e GIF animado", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")

    assert has_element?(view, "#export-menu [data-bg-control=export-svg]")
    assert has_element?(view, "#export-menu [data-bg-control=export-png]")
    assert has_element?(view, "#export-menu #export-gif[data-bg-control=export-gif]")
  end

  test "slug inexistente redireciona para a raiz", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/d/nao-existe")
    assert flash["error"] =~ "não encontrado"
  end
end
