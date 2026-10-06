defmodule BrainagramWeb.ExportController do
  @moduledoc """
  Downloads da área de gestão:

    * `GET /d/:slug/download` — o diagrama como `.brain` (o fonte da DSL);
    * `GET /export?project=…` — um pacote `.json` com os diagramas de um
      projeto (`project=slug`), dos sem projeto (`none`) ou de todos (vazio).

  Os dois voltam pela importação (`ImportDiagrams`), aqui ou em outra
  instalação do Brainagram.
  """

  use BrainagramWeb, :controller

  alias Brainagram.Application.Bus
  alias Brainagram.Application.Queries.{ExportBundle, GetDiagramBySlug}
  alias Brainagram.Shared.Text

  def diagram(conn, %{"slug" => slug}) do
    case Bus.ask(GetDiagramBySlug, %{slug: slug}) do
      {:ok, detail} ->
        name = Text.slugify(detail.title || slug)
        name = if name == "", do: slug, else: name

        send_download(conn, {:binary, detail.source},
          filename: "#{name}.brain",
          content_type: "text/plain; charset=utf-8"
        )

      {:error, _} ->
        send_resp(conn, 404, "")
    end
  end

  def bundle(conn, params) do
    case Bus.ask(ExportBundle, %{project: params["project"]}) do
      {:ok, %{json: json, filename: filename}} ->
        send_download(conn, {:binary, json}, filename: filename, content_type: "application/json")

      {:error, _} ->
        send_resp(conn, 404, "")
    end
  end
end
