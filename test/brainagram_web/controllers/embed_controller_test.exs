defmodule BrainagramWeb.EmbedControllerTest do
  @moduledoc """
  O player embutível (`/embed/:slug`): só diagramas públicos, liberado para
  iframes de outros sites, sem sessão nem cookie, com cache. O resto do app
  continua impedindo ser exibido em iframe de outro site.
  """

  # `Application.put_env/3` (embed desligado) é global: sem paralelismo.
  use BrainagramWeb.ConnCase, async: false

  alias Brainagram.Application.Bus
  alias Brainagram.Application.Commands.CreateDiagram

  @source ~s(diagram sequence "Pedido"\nstep "Envio" {\n  cliente -> api : POST /pedido\n}\n)

  setup do
    on_exit(fn -> Application.put_env(:brainagram, :embed, enabled: true, origins: []) end)
    {:ok, public} = Bus.dispatch(CreateDiagram, %{source: @source, visibility: "public"})
    {:ok, private} = Bus.dispatch(CreateDiagram, %{source: @source, visibility: "private"})
    %{public: public, private: private}
  end

  defp header(conn, name), do: conn |> get_resp_header(name) |> List.first()

  defp query(conn, selector) do
    conn |> html_response(conn.status) |> LazyHTML.from_document() |> LazyHTML.query(selector)
  end

  describe "diagrama público" do
    test "abre o player, liberado para iframes, sem cookie", %{conn: conn, public: slug} do
      conn = get(conn, ~p"/embed/#{slug}")

      assert conn.status == 200
      assert header(conn, "content-security-policy") =~ "frame-ancestors *"
      assert header(conn, "x-frame-options") == nil
      assert get_resp_header(conn, "set-cookie") == []
      assert header(conn, "cache-control") =~ "public"
      assert Enum.count(query(conn, "#bg-scene")) == 1
      assert Enum.count(query(conn, "#embed-stage")) == 1
      assert Enum.count(query(conn, "#embed-bar")) == 1
    end

    test "o mesmo ETag responde 304", %{conn: conn, public: slug} do
      etag = conn |> get(~p"/embed/#{slug}") |> header("etag")

      conn = build_conn() |> put_req_header("if-none-match", etag) |> get(~p"/embed/#{slug}")
      assert conn.status == 304
    end

    test "as opções da URL valem, e valores estranhos voltam ao padrão", %{
      conn: conn,
      public: slug
    } do
      conn = get(conn, ~p"/embed/#{slug}?theme=dark&controls=none&autoplay=1&step=2")
      assert Enum.count(query(conn, ~s(html[data-theme="dark"]))) == 1
      assert Enum.count(query(conn, ~s(body[data-autoplay="true"][data-step="2"]))) == 1
      assert Enum.count(query(conn, "#embed-bar")) == 0

      conn = get(build_conn(), ~p"/embed/#{slug}?theme=<script>&controls=x&step=-1")
      assert Enum.count(query(conn, "html[data-theme]")) == 0
      assert Enum.count(query(conn, ~s(body[data-controls="full"][data-step="1"]))) == 1
    end

    test "o idioma vem de ?lang= ou do navegador", %{conn: conn, public: slug} do
      conn = get(conn, ~p"/embed/#{slug}?lang=ja")
      assert Enum.count(query(conn, ~s(html[lang="ja"]))) == 1

      conn =
        build_conn()
        |> put_req_header("accept-language", "it-IT,it;q=0.9")
        |> get(~p"/embed/#{slug}")

      assert Enum.count(query(conn, ~s(html[lang="it"]))) == 1
    end
  end

  describe "fora do ar" do
    test "privado e inexistente respondem o mesmo 404 neutro", %{conn: conn, private: slug} do
      private = get(conn, ~p"/embed/#{slug}")
      missing = get(build_conn(), ~p"/embed/nao-existe")

      assert private.status == 404
      assert missing.status == 404
      assert Enum.count(query(private, "#embed-unavailable")) == 1
      assert private.resp_body == missing.resp_body
    end

    test "BRAINAGRAM_EMBED=false desliga todos os embeds", %{conn: conn, public: slug} do
      Application.put_env(:brainagram, :embed, enabled: false, origins: [])
      assert get(conn, ~p"/embed/#{slug}").status == 404
    end

    test "a lista de sites permitidos vai para o frame-ancestors", %{conn: conn, public: slug} do
      Application.put_env(:brainagram, :embed,
        enabled: true,
        origins: ["https://docs.exemplo.com"]
      )

      assert get(conn, ~p"/embed/#{slug}") |> header("content-security-policy") =~
               "frame-ancestors https://docs.exemplo.com"
    end
  end

  test "o resto do app continua sem poder ser exibido em iframe de outro site", %{conn: conn} do
    assert get(conn, ~p"/") |> header("content-security-policy") =~ "frame-ancestors 'self'"
  end
end
