defmodule BrainagramWeb.HealthCheckTest do
  use BrainagramWeb.ConnCase, async: true

  test "GET /health responde 200 ok sem sessão", %{conn: conn} do
    conn = get(conn, "/health")

    assert response(conn, 200) == "ok"
    assert response_content_type(conn, :text)
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "HEAD /health também responde", %{conn: conn} do
    assert conn |> head("/health") |> response(200)
  end

  test "outras rotas seguem para o roteador", %{conn: conn} do
    assert conn |> get(~p"/") |> html_response(200)
  end
end
