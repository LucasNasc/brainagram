defmodule Brainagram.Infrastructure.Persistence.EctoProjectRepository do
  @moduledoc """
  Implementação Postgres da porta de escrita dos projetos.

  O mapeamento cabe aqui dentro: um projeto tem três campos e nenhum value
  object que precise re-parsear nada — um `ProjectMapper` à parte seria
  cerimônia.
  """

  @behaviour Brainagram.Domain.Diagramming.Ports.ProjectRepository

  import Ecto.Query

  alias Brainagram.Domain.Diagramming.Project
  alias Brainagram.Domain.Diagramming.ValueObjects.{ProjectColor, ProjectName, Slug}
  alias Brainagram.Infrastructure.Persistence.{ProjectRecord, Repo}

  @impl true
  def insert(%Project{} = project) do
    %ProjectRecord{}
    |> ProjectRecord.changeset(to_attrs(project))
    |> Repo.insert()
    |> merge_persisted(project)
  end

  @impl true
  def update(%Project{id: nil}), do: {:error, :not_persisted}

  def update(%Project{} = project) do
    case Repo.get(ProjectRecord, project.id) do
      nil ->
        {:error, :not_found}

      record ->
        record
        |> ProjectRecord.changeset(to_attrs(project))
        |> Repo.update()
        |> merge_persisted(project)
    end
  end

  @impl true
  def delete(%Project{id: nil}), do: {:error, :not_persisted}

  def delete(%Project{id: id}) do
    case Repo.delete_all(from p in ProjectRecord, where: p.id == ^id) do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  @impl true
  def fetch_by_slug(%Slug{} = slug) do
    case Repo.get_by(ProjectRecord, slug: Slug.to_string(slug)) do
      nil -> {:error, :not_found}
      record -> to_entity(record)
    end
  end

  defp to_entity(%ProjectRecord{} = record) do
    with {:ok, slug} <- Slug.new(record.slug),
         {:ok, name} <- ProjectName.new(record.name),
         {:ok, color} <- ProjectColor.new(record.color) do
      {:ok,
       %Project{
         id: record.id,
         slug: slug,
         name: name,
         color: color,
         inserted_at: record.inserted_at,
         updated_at: record.updated_at
       }}
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

  defp merge_persisted({:ok, record}, project) do
    {:ok,
     %{project | id: record.id, inserted_at: record.inserted_at, updated_at: record.updated_at}}
  end

  defp merge_persisted({:error, %Ecto.Changeset{} = changeset}, _project) do
    if Keyword.has_key?(changeset.errors, :slug),
      do: {:error, :slug_taken},
      else: {:error, changeset}
  end
end
