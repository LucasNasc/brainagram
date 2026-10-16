defmodule Brainagram.Infrastructure.Cache.CacheDiagramReader do
  @moduledoc """
  A porta de leitura de diagramas no modo demo. Mesmo contrato e mesmas regras
  de filtro e ordem que `EctoDiagramReader`, só que sobre as linhas do
  `Cache.Store`.
  """

  @behaviour Brainagram.Application.Ports.DiagramReader

  alias Brainagram.Application.ReadModels.{DiagramDetail, DiagramSummary}
  alias Brainagram.Infrastructure.Cache.Store

  @default_limit 200

  @impl true
  def fetch_by_slug(slug) when is_binary(slug) do
    case :ets.lookup(Store.diagrams(), slug) do
      [{_slug, row}] ->
        {:ok, struct!(DiagramDetail, row |> with_project() |> Map.drop([:id]))}

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def list_public(limit) when is_integer(limit) and limit > 0 do
    rows()
    |> Enum.filter(&(&1.visibility == "public"))
    |> Enum.sort_by(&{&1.updated_at, &1.id}, &newer?/2)
    |> Enum.take(limit)
    |> summaries()
  end

  @impl true
  def count_public, do: Enum.count(rows(), &(&1.visibility == "public"))

  @impl true
  def list(filters) when is_map(filters) do
    rows()
    |> by_project(Map.get(filters, :project))
    |> by_kind(Map.get(filters, :kind))
    |> by_search(Map.get(filters, :search))
    |> sorted(Map.get(filters, :sort, :updated))
    |> Enum.take(Map.get(filters, :limit, @default_limit))
    |> summaries()
  end

  @impl true
  def list_sources(filters) when is_map(filters) do
    rows()
    |> by_project(Map.get(filters, :project))
    |> Enum.sort_by(&{&1.inserted_at, &1.id}, &older?/2)
    |> Enum.map(fn row ->
      row
      |> with_project()
      |> Map.take([:slug, :title, :source, :visibility, :project, :project_name, :project_color])
    end)
  end

  @impl true
  def counts do
    all = rows()
    %{all: length(all), none: Enum.count(all, &is_nil(&1.project_slug))}
  end

  # ── privados ──────────────────────────────────────────────────────────────

  defp rows, do: for({_slug, row} <- :ets.tab2list(Store.diagrams()), do: row)

  defp with_project(row) do
    project =
      case row.project_slug && :ets.lookup(Store.projects(), row.project_slug) do
        [{_slug, p}] -> p
        _none -> nil
      end

    row
    |> Map.delete(:project_slug)
    |> Map.merge(%{
      project: row.project_slug,
      project_name: project && project.name,
      project_color: project && project.color
    })
  end

  defp summaries(rows) do
    Enum.map(rows, fn row ->
      struct!(
        DiagramSummary,
        row
        |> with_project()
        |> Map.take([
          :slug,
          :title,
          :kind,
          :visibility,
          :project,
          :project_name,
          :project_color,
          :inserted_at,
          :updated_at
        ])
      )
    end)
  end

  defp by_project(rows, nil), do: rows
  defp by_project(rows, :none), do: Enum.filter(rows, &is_nil(&1.project_slug))
  defp by_project(rows, slug), do: Enum.filter(rows, &(&1.project_slug == slug))

  defp by_kind(rows, kind) when kind in ["sequence", "architecture"],
    do: Enum.filter(rows, &(&1.kind == kind))

  defp by_kind(rows, _kind), do: rows

  defp by_search(rows, nil), do: rows

  defp by_search(rows, search) do
    case search |> String.trim() |> String.downcase() do
      "" -> rows
      term -> Enum.filter(rows, &String.contains?(String.downcase(&1.title), term))
    end
  end

  defp sorted(rows, :title), do: Enum.sort_by(rows, &{String.downcase(&1.title), &1.id})
  defp sorted(rows, :created), do: Enum.sort_by(rows, &{&1.inserted_at, &1.id}, &newer?/2)
  defp sorted(rows, _updated), do: Enum.sort_by(rows, &{&1.updated_at, &1.id}, &newer?/2)

  defp newer?({a, ia}, {b, ib}) do
    case DateTime.compare(a, b) do
      :gt -> true
      :lt -> false
      :eq -> ia >= ib
    end
  end

  defp older?({a, ia}, {b, ib}) do
    case DateTime.compare(a, b) do
      :lt -> true
      :gt -> false
      :eq -> ia <= ib
    end
  end
end
