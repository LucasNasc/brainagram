defmodule Brainagram.Application.Handlers.Support do
  @moduledoc """
  O pouco que todo handler de comando repete: resolver a porta de escrita e
  carregar o agregado pelo slug.

  Fica pequeno de propósito. Um "base handler" que crescesse para orquestrar
  regra de negócio viraria um segundo domínio, paralelo e sem testes —
  é o começo do Transaction Script que o DDD existe para evitar.
  """

  alias Brainagram.Application.Ports
  alias Brainagram.Domain.Diagramming.{Diagram, Project}
  alias Brainagram.Domain.Diagramming.ValueObjects.Slug

  @spec repository() :: module()
  def repository, do: Ports.diagram_repository()

  @doc "Valida o slug e reconstitui o agregado, ou explica por que não deu."
  @spec load(String.t()) :: {:ok, Diagram.t()} | {:error, :invalid_slug | :not_found}
  def load(slug) do
    with {:ok, slug} <- Slug.new(slug) do
      repository().fetch_by_slug(slug)
    end
  end

  @spec projects() :: module()
  def projects, do: Ports.project_repository()

  @doc "Carrega um projeto pelo slug; slug fora do formato também é `:project_not_found`."
  @spec load_project(String.t()) :: {:ok, Project.t()} | {:error, :project_not_found}
  def load_project(slug) do
    with {:ok, slug} <- Slug.new(slug),
         {:ok, project} <- projects().fetch_by_slug(slug) do
      {:ok, project}
    else
      _ -> {:error, :project_not_found}
    end
  end

  @doc """
  O projeto de destino de um diagrama: `nil`/`""` é "sem projeto"; qualquer
  outro valor precisa ser um projeto que existe. Devolve o slug a gravar.
  """
  @spec ensure_project(String.t() | nil) :: {:ok, String.t() | nil} | {:error, :project_not_found}
  def ensure_project(nil), do: {:ok, nil}
  def ensure_project(""), do: {:ok, nil}

  def ensure_project(slug) do
    with {:ok, project} <- load_project(slug), do: {:ok, Project.slug_string(project)}
  end

  @doc """
  Persiste só quando o agregado de fato mudou.

  Nenhum evento significa nenhuma transição — gravar assim mesmo sujaria
  `updated_at`, o histórico e o broadcast de colaboração com ruído.
  """
  @spec persist_if_changed(Diagram.t(), Diagram.t(), [struct()]) ::
          {:ok, String.t(), [struct()]} | {:error, term()}
  def persist_if_changed(current, _updated, []), do: {:ok, Diagram.slug_string(current), []}

  def persist_if_changed(_current, updated, events) do
    with {:ok, saved} <- repository().update(updated) do
      {:ok, Diagram.slug_string(saved), events}
    end
  end
end
