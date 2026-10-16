defmodule BrainagramWeb.DemoBannerTest do
  @moduledoc "O aviso de playground só aparece no modo demo."

  # `Application.put_env/3` é global: este arquivo não roda em paralelo.
  use BrainagramWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    on_exit(fn -> Application.delete_env(:brainagram, :demo_mode) end)
    :ok
  end

  test "fora do modo demo, não há aviso", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#demo-banner")
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.query(document, "#demo-banner") |> Enum.count() == 0
  end

  test "no modo demo, o aviso aparece em todas as telas", %{conn: conn} do
    Application.put_env(:brainagram, :demo_mode, true)

    for path <- [~p"/", ~p"/new"] do
      html = conn |> get(path) |> html_response(200)
      document = LazyHTML.from_document(html)
      assert LazyHTML.query(document, "#demo-banner") |> Enum.count() == 1
    end
  end
end
