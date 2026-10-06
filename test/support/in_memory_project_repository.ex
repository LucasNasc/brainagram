defmodule Brainagram.Test.InMemoryProjectRepository do
  @moduledoc """
  Projetos em memória, no dicionário do processo de teste — o par do
  `InMemoryDiagramRepository`. `InMemoryDiagramRepository.install/0` instala
  os dois.
  """

  @behaviour Brainagram.Domain.Diagramming.Ports.ProjectRepository

  alias Brainagram.Domain.Diagramming.Project
  alias Brainagram.Domain.Diagramming.ValueObjects.Slug

  @key {__MODULE__, :store}

  @spec install() :: :ok
  def install do
    Process.put(@key, %{})
    Brainagram.Application.Ports.override(:project_repository, __MODULE__)
  end

  @spec all() :: [Project.t()]
  def all, do: store() |> Map.values()

  @impl true
  def insert(%Project{} = project) do
    slug = Project.slug_string(project)

    if Map.has_key?(store(), slug) do
      {:error, :slug_taken}
    else
      saved = %{project | id: System.unique_integer([:positive])}
      put(Map.put(store(), slug, saved))
      {:ok, saved}
    end
  end

  @impl true
  def update(%Project{id: nil}), do: {:error, :not_persisted}

  def update(%Project{} = project) do
    slug = Project.slug_string(project)

    if Map.has_key?(store(), slug) do
      put(Map.put(store(), slug, project))
      {:ok, project}
    else
      {:error, :not_found}
    end
  end

  @impl true
  def delete(%Project{} = project) do
    slug = Project.slug_string(project)

    if Map.has_key?(store(), slug) do
      put(Map.delete(store(), slug))
      :ok
    else
      {:error, :not_found}
    end
  end

  @impl true
  def fetch_by_slug(%Slug{} = slug) do
    case Map.fetch(store(), Slug.to_string(slug)) do
      {:ok, project} -> {:ok, project}
      :error -> {:error, :not_found}
    end
  end

  defp store, do: Process.get(@key, %{})
  defp put(store), do: Process.put(@key, store)
end
