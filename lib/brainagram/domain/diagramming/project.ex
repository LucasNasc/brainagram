defmodule Brainagram.Domain.Diagramming.Project do
  @moduledoc """
  O agregado dos projetos: uma pasta com nome e cor, onde a pessoa separa os
  diagramas ("Plataforma de pagamentos", "Onboarding", "RFCs de 2026").

  O projeto não conhece os diagramas. É o diagrama que aponta para o projeto
  (pelo slug), como toda referência entre agregados: por identidade, nunca
  por objeto. Assim criar, renomear ou colorir um projeto nunca carrega
  cinquenta diagramas junto.

  Mesma convenção do `Diagram`: toda transição devolve `{:ok, agregado,
  eventos}` e lista vazia quer dizer que nada mudou.
  """

  alias Brainagram.Domain.Diagramming.Events
  alias Brainagram.Domain.Diagramming.ValueObjects.{ProjectColor, ProjectName, Slug}
  alias Brainagram.Shared.Clock

  @enforce_keys [:slug, :name, :color]
  defstruct [:id, :slug, :name, :color, :inserted_at, :updated_at]

  @type t :: %__MODULE__{
          id: term() | nil,
          slug: Slug.t(),
          name: ProjectName.t(),
          color: ProjectColor.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @type result :: {:ok, t(), [struct()]} | {:error, term()}

  @spec create(map()) :: result()
  def create(attrs) when is_map(attrs) do
    with {:ok, name} <- ProjectName.new(fetch(attrs, :name)),
         {:ok, color} <- ProjectColor.new(fetch(attrs, :color)),
         {:ok, slug} <- resolve_slug(fetch(attrs, :slug)) do
      now = Clock.now()

      project = %__MODULE__{
        slug: slug,
        name: name,
        color: color,
        inserted_at: now,
        updated_at: now
      }

      {:ok, project, [Events.project_created(project)]}
    end
  end

  @doc """
  Muda nome e/ou cor. Campo ausente (`nil`) fica como está; nada diferente do
  atual, nenhum evento.
  """
  @spec update(t(), map()) :: result()
  def update(%__MODULE__{} = project, attrs) when is_map(attrs) do
    with {:ok, name} <- keep_or(fetch(attrs, :name), project.name, &ProjectName.new/1),
         {:ok, color} <- keep_or(fetch(attrs, :color), project.color, &ProjectColor.new/1) do
      if name == project.name and color == project.color do
        {:ok, project, []}
      else
        updated = %{project | name: name, color: color, updated_at: Clock.now()}
        {:ok, updated, [Events.project_updated(updated)]}
      end
    end
  end

  @doc "Eventos da remoção. Os diagramas do projeto ficam, sem projeto."
  @spec deletion_events(t()) :: [struct()]
  def deletion_events(%__MODULE__{} = project), do: [Events.project_deleted(project)]

  @spec slug_string(t()) :: String.t()
  def slug_string(%__MODULE__{slug: slug}), do: Slug.to_string(slug)

  # ── privados ──────────────────────────────────────────────────────────────

  defp keep_or(nil, current, _new), do: {:ok, current}
  defp keep_or(value, _current, new), do: new.(value)

  defp resolve_slug(nil), do: {:ok, Slug.generate()}
  defp resolve_slug(value), do: Slug.new(value)

  defp fetch(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
