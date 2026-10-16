defmodule Brainagram.Infrastructure.Cache.CacheDiagramRepository do
  @moduledoc """
  A porta de escrita de diagramas no modo demo, sobre o `Cache.Store`.

  Guarda a mesma linha que o Postgres guardaria (`DiagramMapper.to_attrs/1`) e
  reconstitui o agregado pelo mesmo `DiagramMapper.to_entity/1`: o fonte passa
  de novo pelo parser, exatamente como na leitura do banco.
  """

  @behaviour Brainagram.Domain.Diagramming.Ports.DiagramRepository

  alias Brainagram.Domain.Diagramming.Diagram
  alias Brainagram.Domain.Diagramming.ValueObjects.Slug
  alias Brainagram.Infrastructure.Cache.Store
  alias Brainagram.Infrastructure.Persistence.{DiagramMapper, DiagramRecord}

  @impl true
  def insert(%Diagram{} = diagram) do
    attrs = DiagramMapper.to_attrs(diagram)

    cond do
      :ets.member(Store.diagrams(), attrs.slug) ->
        {:error, :slug_taken}

      attrs.project_slug && not :ets.member(Store.projects(), attrs.project_slug) ->
        {:error, :project_not_found}

      true ->
        now = Store.now()

        row =
          Map.merge(attrs, %{
            id: Store.next_id(),
            inserted_at: attrs.inserted_at || now,
            updated_at: attrs.updated_at || now
          })

        :ets.insert(Store.diagrams(), {row.slug, row})
        {:ok, %{diagram | id: row.id, inserted_at: row.inserted_at, updated_at: row.updated_at}}
    end
  end

  @impl true
  def update(%Diagram{id: nil}), do: {:error, :not_persisted}

  def update(%Diagram{} = diagram) do
    attrs = DiagramMapper.to_attrs(diagram)

    with {:ok, current} <- by_id(diagram.id),
         :ok <- slug_free(attrs.slug, diagram.id),
         :ok <- project_exists(attrs.project_slug) do
      row =
        Map.merge(attrs, %{
          id: current.id,
          inserted_at: current.inserted_at,
          updated_at: Store.now()
        })

      if current.slug != row.slug, do: :ets.delete(Store.diagrams(), current.slug)
      :ets.insert(Store.diagrams(), {row.slug, row})
      {:ok, %{diagram | inserted_at: row.inserted_at, updated_at: row.updated_at}}
    end
  end

  @impl true
  def delete(%Diagram{id: nil}), do: {:error, :not_persisted}

  def delete(%Diagram{id: id}) do
    with {:ok, row} <- by_id(id) do
      :ets.delete(Store.diagrams(), row.slug)
      :ok
    end
  end

  @impl true
  def fetch_by_slug(%Slug{} = slug) do
    case :ets.lookup(Store.diagrams(), Slug.to_string(slug)) do
      [{_slug, row}] -> DiagramMapper.to_entity(struct(DiagramRecord, row))
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def detach_project(%Slug{} = project) do
    slug = Slug.to_string(project)
    now = Store.now()

    slugs =
      for {key, %{project_slug: ^slug} = row} <- :ets.tab2list(Store.diagrams()) do
        :ets.insert(Store.diagrams(), {key, %{row | project_slug: nil, updated_at: now}})
        key
      end

    {:ok, slugs}
  end

  defp by_id(id) do
    case :ets.match_object(Store.diagrams(), {:_, %{id: id}}) do
      [{_slug, row}] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end

  defp slug_free(slug, id) do
    case :ets.lookup(Store.diagrams(), slug) do
      [{_slug, %{id: ^id}}] -> :ok
      [] -> :ok
      _taken -> {:error, :slug_taken}
    end
  end

  defp project_exists(nil), do: :ok

  defp project_exists(slug) do
    if :ets.member(Store.projects(), slug), do: :ok, else: {:error, :project_not_found}
  end
end
