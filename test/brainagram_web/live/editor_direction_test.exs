defmodule BrainagramWeb.EditorDirectionTest do
  @moduledoc "O botão de direção do canvas: mostra para onde leva."

  use BrainagramWeb.ConnCase

  import Phoenix.LiveViewTest

  @source "diagram architecture\n\nservice api \"API\"\ndatabase db \"Banco\"\n\napi -> db : SQL\n"

  test "em pé oferece Horizontal; deitado, oferece Vertical", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")
    view |> element("form[phx-change=edit]") |> render_change(%{"source" => @source})

    assert view |> element("#switch-direction") |> render() =~ "Horizontal"

    view |> element("#switch-direction") |> render_click()
    assert view |> element("#switch-direction") |> render() =~ "Vertical"
    assert view |> element("#source") |> render() =~ "direction horizontal"

    view |> element("#switch-direction") |> render_click()
    assert view |> element("#switch-direction") |> render() =~ "Horizontal"
    refute view |> element("#source") |> render() =~ "direction"
  end

  test "sequência não tem o botão", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")

    view
    |> element("form[phx-change=edit]")
    |> render_change(%{"source" => "diagram sequence\na -> b\n"})

    refute has_element?(view, "#switch-direction")
  end
end
