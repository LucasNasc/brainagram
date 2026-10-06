defmodule Brainagram.Test.InMemoryDiagramRepository do
  @moduledoc """
  Repositório em memória para testar regra de negócio sem banco.

  O estado vive no dicionário do processo de teste, então os testes continuam
  `async: true`. A existência deste módulo é a prova de que a porta vale o
  custo: um handler inteiro se testa em microssegundos, e a suíte de domínio
  não precisa de Postgres de pé.
  """

  @behaviour Brainagram.Domain.Diagramming.Ports.DiagramRepository

  alias Brainagram.Domain.Diagramming.Diagram
  alias Brainagram.Domain.Diagramming.ValueObjects.Slug

  @key {__MODULE__, :store}

  @doc "Instala este repositório, o de projetos e o publicador de eventos no processo atual."
  @spec install() :: :ok
  def install do
    Process.put(@key, %{})
    Brainagram.Application.Ports.override(:diagram_repository, __MODULE__)
    Brainagram.Test.InMemoryProjectRepository.install()

    Brainagram.Application.Ports.override(
      :event_bus,
      Brainagram.Test.RecordingEventBus
    )

    :ok
  end

  @doc "Semeia um agregado já persistido, pulando o comando de criação."
  @spec seed(Diagram.t()) :: Diagram.t()
  def seed(%Diagram{} = diagram) do
    {:ok, saved} = insert(diagram)
    saved
  end

  @spec all() :: [Diagram.t()]
  def all, do: store() |> Map.values()

  @impl true
  def insert(%Diagram{} = diagram) do
    slug = Diagram.slug_string(diagram)

    if Map.has_key?(store(), slug) do
      {:error, :slug_taken}
    else
      saved = %{diagram | id: System.unique_integer([:positive])}
      put(Map.put(store(), slug, saved))
      {:ok, saved}
    end
  end

  @impl true
  def update(%Diagram{id: nil}), do: {:error, :not_persisted}

  def update(%Diagram{} = diagram) do
    slug = Diagram.slug_string(diagram)

    if Map.has_key?(store(), slug) do
      put(Map.put(store(), slug, diagram))
      {:ok, diagram}
    else
      {:error, :not_found}
    end
  end

  @impl true
  def delete(%Diagram{} = diagram) do
    slug = Diagram.slug_string(diagram)

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
      {:ok, diagram} -> {:ok, diagram}
      :error -> {:error, :not_found}
    end
  end

  @impl true
  def detach_project(%Slug{} = project) do
    moved =
      for {slug, %Diagram{project: ^project} = diagram} <- store() do
        put(Map.put(store(), slug, %{diagram | project: nil}))
        slug
      end

    {:ok, moved}
  end

  defp store, do: Process.get(@key, %{})
  defp put(store), do: Process.put(@key, store)
end
