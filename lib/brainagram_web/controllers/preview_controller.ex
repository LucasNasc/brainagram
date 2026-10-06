defmodule BrainagramWeb.PreviewController do
  @moduledoc """
  A miniatura de um diagrama (`/d/:slug/preview.svg`), para os cards da área
  de gestão.

  O card pede com `?v=<updated_at>`: a URL muda quando o diagrama muda, então
  a resposta pode ficar em cache "para sempre" — rolar a lista de novo não
  recompila nada. Sem `v`, vale a revalidação por ETag.

  O SVG é gerado por `Render.Svg` (texto escapado, sem script), e ainda assim
  sai com uma CSP que não deixa nada executar caso alguém abra a URL direto.
  """

  use BrainagramWeb, :controller

  alias Brainagram.Application.Bus
  alias Brainagram.Application.Queries.GetDiagramPreview

  def show(conn, %{"slug" => slug} = params) do
    case Bus.ask(GetDiagramPreview, %{slug: slug}) do
      {:ok, %{svg: svg, updated_at: updated_at}} ->
        etag = ~s("#{slug}-#{DateTime.to_unix(updated_at)}")

        conn =
          conn
          |> put_resp_content_type("image/svg+xml")
          |> put_resp_header("etag", etag)
          |> put_resp_header(
            "content-security-policy",
            "default-src 'none'; style-src 'unsafe-inline'"
          )
          |> put_resp_header("cache-control", cache_control(params))

        if etag in get_req_header(conn, "if-none-match"),
          do: send_resp(conn, 304, ""),
          else: send_resp(conn, 200, svg)

      {:error, _reason} ->
        send_resp(conn, 404, "")
    end
  end

  defp cache_control(%{"v" => _}), do: "private, max-age=31536000, immutable"
  defp cache_control(_), do: "private, no-cache"
end
