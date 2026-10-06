defmodule Brainagram.Infrastructure.Persistence.EctoDiagramReader do
  @moduledoc """
  Implementação Postgres da porta de leitura.

  É onde o CQRS deixa de ser vocabulário e vira código: as consultas projetam
  direto nos campos que a tela usa (`select:`), sem carregar o schema completo
  e sem reconstituir agregado. A listagem, por exemplo, nunca traz a coluna
  `source` — exibir 50 títulos não deve arrastar 50 blocos de DSL pela rede.

  O projeto entra por `left join`: nome e cor vêm na mesma linha, e diagrama
  sem projeto continua na lista.

  Quando um read model materializado fizer sentido (feed público com contadores,
  por exemplo), ele entra aqui, atrás deste mesmo contrato. Nada acima muda.
  """

  @behaviour Brainagram.Application.Ports.DiagramReader

  import Ecto.Query

  alias Brainagram.Application.ReadModels.{DiagramDetail, DiagramSummary}
  alias Brainagram.Infrastructure.Persistence.{DiagramRecord, ProjectRecord, Repo}

  @default_limit 200

  @impl true
  def fetch_by_slug(slug) when is_binary(slug) do
    query =
      from [diagram: d, project: p] in with_project(),
        where: d.slug == ^slug,
        select: %{
          slug: d.slug,
          title: d.title,
          kind: d.kind,
          visibility: d.visibility,
          source: d.source,
          project: d.project_slug,
          project_name: p.name,
          project_color: p.color,
          inserted_at: d.inserted_at,
          updated_at: d.updated_at
        }

    case Repo.one(query) do
      nil -> {:error, :not_found}
      row -> {:ok, struct!(DiagramDetail, row)}
    end
  end

  @impl true
  def list_public(limit) when is_integer(limit) and limit > 0 do
    with_project()
    |> where([d], d.visibility == "public")
    |> order_by([d], desc: d.updated_at)
    |> limit(^limit)
    |> summaries()
  end

  @impl true
  def count_public do
    Repo.aggregate(from(d in DiagramRecord, where: d.visibility == "public"), :count, :id)
  end

  @impl true
  def list(filters) when is_map(filters) do
    with_project()
    |> by_project(Map.get(filters, :project))
    |> by_kind(Map.get(filters, :kind))
    |> by_search(Map.get(filters, :search))
    |> sorted(Map.get(filters, :sort, :updated))
    |> limit(^Map.get(filters, :limit, @default_limit))
    |> summaries()
  end

  @impl true
  def list_sources(filters) when is_map(filters) do
    with_project()
    |> by_project(Map.get(filters, :project))
    |> order_by([diagram: d], asc: d.inserted_at, asc: d.id)
    |> select([diagram: d, project: p], %{
      slug: d.slug,
      title: d.title,
      source: d.source,
      visibility: d.visibility,
      project: d.project_slug,
      project_name: p.name,
      project_color: p.color
    })
    |> Repo.all()
  end

  @impl true
  def counts do
    query =
      from d in DiagramRecord,
        select: %{
          all: count(d.id),
          none: filter(count(d.id), is_nil(d.project_slug))
        }

    Repo.one(query)
  end

  # ── privados ──────────────────────────────────────────────────────────────

  defp with_project do
    from d in DiagramRecord,
      as: :diagram,
      left_join: p in ProjectRecord,
      as: :project,
      on: p.slug == d.project_slug
  end

  defp summaries(query) do
    query
    |> select([diagram: d, project: p], %{
      slug: d.slug,
      title: d.title,
      kind: d.kind,
      visibility: d.visibility,
      project: d.project_slug,
      project_name: p.name,
      project_color: p.color,
      inserted_at: d.inserted_at,
      updated_at: d.updated_at
    })
    |> Repo.all()
    |> Enum.map(&struct!(DiagramSummary, &1))
  end

  defp by_project(query, nil), do: query
  defp by_project(query, :none), do: where(query, [d], is_nil(d.project_slug))
  defp by_project(query, slug), do: where(query, [d], d.project_slug == ^slug)

  defp by_kind(query, kind) when kind in ["sequence", "architecture"],
    do: where(query, [d], d.kind == ^kind)

  defp by_kind(query, _kind), do: query

  defp by_search(query, nil), do: query

  defp by_search(query, search) do
    case String.trim(search) do
      "" ->
        query

      term ->
        pattern = "%" <> String.replace(term, ~r/([\\%_])/, "\\\\\\1") <> "%"
        where(query, [d], ilike(d.title, ^pattern))
    end
  end

  defp sorted(query, :title),
    do: order_by(query, [d], asc: fragment("lower(?)", d.title), asc: d.id)

  defp sorted(query, :created), do: order_by(query, [d], desc: d.inserted_at, desc: d.id)
  defp sorted(query, _updated), do: order_by(query, [d], desc: d.updated_at, desc: d.id)
end
