defmodule Brainagram.Application.QueryHandlers.ExportBundle do
  @moduledoc "Lê os diagramas do escopo com o fonte e monta o pacote."

  @behaviour Brainagram.Application.QueryHandler

  alias Brainagram.Application.{Bundle, Ports}
  alias Brainagram.Application.Queries.ExportBundle
  alias Brainagram.Shared.Clock

  @impl true
  def handle(%ExportBundle{project: project}) do
    with {:ok, filter, scope} <- scope(project) do
      rows = Ports.diagram_reader().list_sources(%{project: filter})
      now = Clock.now()

      {:ok,
       %{
         json: Bundle.encode(rows, now),
         filename: Bundle.filename(scope, now),
         count: length(rows)
       }}
    end
  end

  defp scope(nil), do: {:ok, nil, "todos"}
  defp scope(""), do: {:ok, nil, "todos"}
  defp scope("none"), do: {:ok, :none, "sem-projeto"}

  defp scope(slug) do
    case Ports.project_reader().fetch_by_slug(slug) do
      {:ok, project} -> {:ok, slug, project.name}
      {:error, _} -> {:error, :project_not_found}
    end
  end
end
