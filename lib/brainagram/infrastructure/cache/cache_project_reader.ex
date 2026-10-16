defmodule Brainagram.Infrastructure.Cache.CacheProjectReader do
  @moduledoc "A leitura de projetos no modo demo: a lista da lateral, com a contagem de diagramas."

  @behaviour Brainagram.Application.Ports.ProjectReader

  alias Brainagram.Application.ReadModels.ProjectSummary
  alias Brainagram.Infrastructure.Cache.Store

  @impl true
  def list do
    counts = counts()

    Store.projects()
    |> :ets.tab2list()
    |> Enum.map(fn {_slug, row} -> row end)
    |> Enum.sort_by(&{String.downcase(&1.name), &1.id})
    |> Enum.map(&summary(&1, counts))
  end

  @impl true
  def fetch_by_slug(slug) when is_binary(slug) do
    case :ets.lookup(Store.projects(), slug) do
      [{_slug, row}] -> {:ok, summary(row, counts())}
      [] -> {:error, :not_found}
    end
  end

  defp counts do
    Store.diagrams()
    |> :ets.tab2list()
    |> Enum.frequencies_by(fn {_slug, d} -> d.project_slug end)
  end

  defp summary(row, counts) do
    struct!(ProjectSummary, %{
      slug: row.slug,
      name: row.name,
      color: row.color,
      diagram_count: Map.get(counts, row.slug, 0),
      updated_at: row.updated_at
    })
  end
end
