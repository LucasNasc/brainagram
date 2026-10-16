defmodule Brainagram.Infrastructure.Cache.CacheProjectRepository do
  @moduledoc "A porta de escrita de projetos no modo demo, sobre o `Cache.Store`."

  @behaviour Brainagram.Domain.Diagramming.Ports.ProjectRepository

  alias Brainagram.Domain.Diagramming.Project
  alias Brainagram.Domain.Diagramming.ValueObjects.{ProjectColor, ProjectName, Slug}
  alias Brainagram.Infrastructure.Cache.Store

  @impl true
  def insert(%Project{} = project) do
    attrs = to_attrs(project)

    if :ets.member(Store.projects(), attrs.slug) do
      {:error, :slug_taken}
    else
      now = Store.now()

      row =
        Map.merge(attrs, %{
          id: Store.next_id(),
          inserted_at: attrs.inserted_at || now,
          updated_at: attrs.updated_at || now
        })

      :ets.insert(Store.projects(), {row.slug, row})
      {:ok, %{project | id: row.id, inserted_at: row.inserted_at, updated_at: row.updated_at}}
    end
  end

  @impl true
  def update(%Project{id: nil}), do: {:error, :not_persisted}

  def update(%Project{} = project) do
    attrs = to_attrs(project)

    with {:ok, current} <- by_id(project.id) do
      case :ets.lookup(Store.projects(), attrs.slug) do
        [{_slug, %{id: other}}] when other != project.id ->
          {:error, :slug_taken}

        _free ->
          row =
            Map.merge(attrs, %{
              id: current.id,
              inserted_at: current.inserted_at,
              updated_at: Store.now()
            })

          if current.slug != row.slug, do: :ets.delete(Store.projects(), current.slug)
          :ets.insert(Store.projects(), {row.slug, row})
          {:ok, %{project | inserted_at: row.inserted_at, updated_at: row.updated_at}}
      end
    end
  end

  @impl true
  def delete(%Project{id: nil}), do: {:error, :not_persisted}

  def delete(%Project{id: id}) do
    with {:ok, row} <- by_id(id) do
      :ets.delete(Store.projects(), row.slug)
      :ok
    end
  end

  @impl true
  def fetch_by_slug(%Slug{} = slug) do
    with [{_slug, row}] <- :ets.lookup(Store.projects(), Slug.to_string(slug)),
         {:ok, slug} <- Slug.new(row.slug),
         {:ok, name} <- ProjectName.new(row.name),
         {:ok, color} <- ProjectColor.new(row.color) do
      {:ok,
       %Project{
         id: row.id,
         slug: slug,
         name: name,
         color: color,
         inserted_at: row.inserted_at,
         updated_at: row.updated_at
       }}
    else
      [] -> {:error, :not_found}
      error -> error
    end
  end

  defp by_id(id) do
    case :ets.match_object(Store.projects(), {:_, %{id: id}}) do
      [{_slug, row}] -> {:ok, row}
      [] -> {:error, :not_found}
    end
  end

  defp to_attrs(%Project{} = project) do
    %{
      slug: Slug.to_string(project.slug),
      name: ProjectName.to_string(project.name),
      color: ProjectColor.to_string(project.color),
      inserted_at: project.inserted_at,
      updated_at: project.updated_at
    }
  end
end
