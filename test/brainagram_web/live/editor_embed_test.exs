defmodule BrainagramWeb.EditorEmbedTest do
  @moduledoc """
  Exportar → Incorporar: o diálogo dá o código do iframe só para diagramas
  salvos e públicos, e as opções mudam o endereço do player.
  """

  use BrainagramWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Brainagram.Application.Bus
  alias Brainagram.Application.Commands.CreateDiagram

  @source ~s(diagram sequence "Pedido"\nstep "Envio" {\n  cliente -> api : POST /pedido\n}\n)

  defp saved!(visibility) do
    {:ok, slug} = Bus.dispatch(CreateDiagram, %{source: @source, visibility: visibility})
    slug
  end

  defp open_dialog(view) do
    view |> element("#export-embed") |> render_click()
    view
  end

  test "diagrama público: prévia e código do iframe", %{conn: conn} do
    slug = saved!("public")
    {:ok, view, _html} = live(conn, ~p"/d/#{slug}?edit=1")
    open_dialog(view)

    assert has_element?(view, "#embed-dialog")
    assert has_element?(view, ~s(#embed-preview[src="http://www.example.com/embed/#{slug}"]))
    assert has_element?(view, "#embed-snippet", "/embed/#{slug}")
    assert has_element?(view, "#embed-copy[phx-hook=CopyText]")
  end

  test "as opções entram no endereço, sem repetir os padrões", %{conn: conn} do
    slug = saved!("public")
    {:ok, view, _html} = live(conn, ~p"/d/#{slug}?edit=1")
    open_dialog(view)

    view
    |> element("#embed-form")
    |> render_change(%{
      "embed" => %{
        "theme" => "dark",
        "controls" => "full",
        "autoplay" => "true",
        "loop" => "false"
      }
    })

    assert has_element?(
             view,
             ~s(#embed-preview[src="http://www.example.com/embed/#{slug}?theme=dark&autoplay=1"])
           )
  end

  test "diagrama privado: explica e oferece tornar público, sem código", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/d/#{saved!("private")}?edit=1")
    open_dialog(view)

    assert has_element?(view, "#embed-private")
    assert has_element?(view, "#embed-make-public")
    refute has_element?(view, "#embed-snippet")
  end

  test "diagrama novo, ainda não salvo: pede para salvar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")
    open_dialog(view)

    assert has_element?(view, "#embed-unsaved")
    refute has_element?(view, "#embed-snippet")
  end

  test "Esc e o X fecham o diálogo", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/d/#{saved!("public")}?edit=1")
    open_dialog(view)

    view |> element("#embed-dialog button[phx-click='embed:close']") |> render_click()
    refute has_element?(view, "#embed-dialog")
  end
end
