defmodule Brainagram.Application.QueryHandlers.ListDiagrams do
  @moduledoc "Traduz os filtros da tela para os do leitor. Sem agregado no caminho."

  @behaviour Brainagram.Application.QueryHandler

  alias Brainagram.Application.Ports
  alias Brainagram.Application.Queries.ListDiagrams

  @impl true
  def handle(%ListDiagrams{} = query) do
    filters = %{
      project: project(query.project),
      search: query.search,
      kind: query.kind,
      sort: sort(query.sort)
    }

    {:ok, Ports.diagram_reader().list(filters)}
  end

  defp project(nil), do: nil
  defp project(""), do: nil
  defp project("none"), do: :none
  defp project(slug), do: slug

  defp sort("title"), do: :title
  defp sort("created"), do: :created
  defp sort(_), do: :updated
end
