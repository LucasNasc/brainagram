defmodule BrainagramWeb.LoadingFeedbackTest do
  @moduledoc """
  A espera por uma resposta do servidor mostra a marca: o impulso caminhando
  pelo "b". O CSS revela o loader quando o LiveView marca o
  carregamento; aqui se confere que ele está no lugar certo.
  """

  use BrainagramWeb.ConnCase

  import Phoenix.LiveViewTest

  @arch "diagram architecture\n\nservice api \"API\"\ndatabase db \"Banco\"\n\napi -> db : SQL\n"

  test "reorganizar o diagrama acende o loader do canvas", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")
    view |> element("form[phx-change=edit]") |> render_change(%{"source" => @arch})

    assert has_element?(view, "#canvas-busy.ba-loader[role=status]", "Reorganizando o diagrama")
    assert has_element?(view, "#canvas-busy animateMotion")

    for id <- ["#untangle-layout", "#switch-direction"] do
      click = view |> element(id) |> render() |> attribute("phx-click")
      assert click =~ ~s("loading":"#canvas-busy")
    end
  end

  test "importar mostra o loader no diálogo e o b no botão", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")
    view |> element("#open-import") |> render_click()

    assert has_element?(view, "#import-form .ba-loader--overlay", "Importando o diagrama")
    assert has_element?(view, "#import-submit .ba-busy-mark")
  end

  test "salvar troca o ícone pelo b enquanto espera", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")
    assert has_element?(view, "#save-button .ba-busy-mark")
  end

  defp attribute(html, name) do
    [value] = html |> LazyHTML.from_fragment() |> LazyHTML.attribute(name)
    value
  end
end
