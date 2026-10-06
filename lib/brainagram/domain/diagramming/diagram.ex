defmodule Brainagram.Domain.Diagramming.Diagram do
  @moduledoc """
  O agregado. Entidade pura: não conhece Ecto, Phoenix, banco nem processo.

  Todas as transições retornam `{:ok, agregado, eventos}`. A convenção que faz
  esse desenho pagar: **lista de eventos vazia significa que nada mudou**. O
  handler olha para a lista e decide se vale um `UPDATE` — não há um caminho
  separado de "no-op" para alguém esquecer de tratar.

  Repare no que *não* existe aqui: um campo de título editável. Título e tipo
  são derivados do fonte (`diagram sequence "Checkout"`), então renomear por
  fora criaria exatamente a divergência entre metadado e conteúdo que a
  arquitetura se propôs a eliminar. Renomear existe, mas como edição da DSL
  (`Authoring.rename_title/2` pela `apply_edit/2`): muda-se o texto, e o
  título acompanha.

  O projeto é referência por identidade (`project`: o slug do projeto, ou
  `nil` para "sem projeto"). O diagrama não carrega o `%Project{}`.
  """

  alias Brainagram.Domain.Diagramming.Events
  alias Brainagram.Domain.Diagramming.ValueObjects.{Kind, Slug, Source, Title, Visibility}
  alias Brainagram.Shared.Clock

  @enforce_keys [:slug, :title, :kind, :source, :visibility]
  defstruct [
    :id,
    :slug,
    :title,
    :kind,
    :source,
    :visibility,
    :project,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          id: term() | nil,
          slug: Slug.t(),
          title: Title.t(),
          kind: Kind.t(),
          source: Source.t(),
          visibility: Visibility.t(),
          project: Slug.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @type result :: {:ok, t(), [struct()]} | {:error, term()}

  @doc """
  Cria um diagrama a partir do fonte da DSL.

  O fonte precisa compilar — `Source.new/1` é quem barra. Título e tipo saem
  dele; slug é gerado quando não informado; `project` é o slug do projeto
  (ou nada, para ficar sem projeto).
  """
  @spec create(map()) :: result()
  def create(attrs) when is_map(attrs) do
    with {:ok, source} <- Source.new(fetch(attrs, :source)),
         {:ok, slug} <- resolve_slug(fetch(attrs, :slug)),
         {:ok, visibility} <- Visibility.new(fetch(attrs, :visibility)),
         {:ok, project} <- project_ref(fetch(attrs, :project)) do
      now = Clock.now()

      diagram = %__MODULE__{
        slug: slug,
        title: Source.title(source),
        kind: Source.kind(source),
        source: source,
        visibility: visibility,
        project: project,
        inserted_at: now,
        updated_at: now
      }

      {:ok, diagram, [Events.created(diagram)]}
    end
  end

  @doc """
  Troca o fonte, re-derivando título e tipo.

  Fonte idêntico devolve zero eventos: salvar o que não mudou só gera ruído em
  histórico e em broadcast de colaboração.
  """
  @spec change_source(t(), String.t()) :: result()
  def change_source(%__MODULE__{} = diagram, raw) do
    with {:ok, source} <- Source.new(raw) do
      if Source.equal?(diagram.source, source) do
        {:ok, diagram, []}
      else
        updated = %{
          diagram
          | source: source,
            title: Source.title(source),
            kind: Source.kind(source),
            updated_at: Clock.now()
        }

        {:ok, updated, [Events.source_changed(updated, diagram.kind)]}
      end
    end
  end

  @doc """
  Aplica uma edição de autoria ao fonte — a transição única de todos os gestos
  do canvas (spec 001, §7).

  `edit` recebe o fonte atual e devolve o novo, seja como texto puro
  (`Dsl.Editor.replace/3`) ou no formato de `Authoring` (`{:ok, texto}`,
  `{:ok, texto, meta}`, `{:error, motivo}`). Por dentro é `change_source/2` — e
  herda a regra de que texto idêntico não gera evento: arrastar um nó e soltar
  no mesmo lugar não suja o histórico.
  """
  @spec apply_edit(t(), (String.t() ->
                           String.t()
                           | {:ok, String.t()}
                           | {:ok, String.t(), map()}
                           | {:error, term()})) ::
          result()
  def apply_edit(%__MODULE__{} = diagram, edit) when is_function(edit, 1) do
    case edit.(Source.raw(diagram.source)) do
      raw when is_binary(raw) -> change_source(diagram, raw)
      {:ok, raw} -> change_source(diagram, raw)
      {:ok, raw, _meta} -> change_source(diagram, raw)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec change_visibility(t(), Visibility.t() | String.t()) :: result()
  def change_visibility(%__MODULE__{} = diagram, visibility) do
    with {:ok, visibility} <- Visibility.new(visibility) do
      if diagram.visibility == visibility do
        {:ok, diagram, []}
      else
        updated = %{diagram | visibility: visibility, updated_at: Clock.now()}
        {:ok, updated, [Events.visibility_changed(updated)]}
      end
    end
  end

  @doc """
  Leva o diagrama para outro projeto (`nil` ou `""` tira de qualquer projeto).

  Quem garante que o projeto existe é o handler, que o carrega antes: o
  agregado só valida o formato da referência.
  """
  @spec move_to_project(t(), Slug.t() | String.t() | nil) :: result()
  def move_to_project(%__MODULE__{} = diagram, project) do
    with {:ok, project} <- project_ref(project) do
      if project == diagram.project do
        {:ok, diagram, []}
      else
        updated = %{diagram | project: project, updated_at: Clock.now()}
        {:ok, updated, [Events.moved(updated, diagram.project)]}
      end
    end
  end

  @doc """
  Duplica o diagrama sob um slug novo.

  A cópia nasce privada de propósito: bifurcar o diagrama de outra pessoa não
  deve publicar nada em nome de ninguém sem um segundo ato deliberado. E fica
  no mesmo projeto do original — é onde a pessoa estava trabalhando.
  """
  @spec fork(t(), map()) :: result()
  def fork(%__MODULE__{} = origin, attrs \\ %{}) do
    with {:ok, slug} <- resolve_slug(fetch(attrs, :slug)) do
      now = Clock.now()

      copy = %__MODULE__{
        slug: slug,
        title: origin.title,
        kind: origin.kind,
        source: origin.source,
        visibility: :private,
        project: origin.project,
        inserted_at: now,
        updated_at: now
      }

      {:ok, copy, [Events.created(copy), Events.forked(origin, copy)]}
    end
  end

  @doc "Eventos da remoção. O agregado some, então não há estado a devolver."
  @spec deletion_events(t()) :: [struct()]
  def deletion_events(%__MODULE__{} = diagram), do: [Events.deleted(diagram)]

  @spec public?(t()) :: boolean()
  def public?(%__MODULE__{visibility: visibility}), do: Visibility.public?(visibility)

  @doc "A cena renderizável. Delegado ao value object — o agregado não desenha."
  @spec scene(t()) :: Brainagram.Domain.Diagramming.Scene.t()
  def scene(%__MODULE__{source: source}), do: Source.scene(source)

  @spec slug_string(t()) :: String.t()
  def slug_string(%__MODULE__{slug: slug}), do: Slug.to_string(slug)

  @spec title_string(t()) :: String.t()
  def title_string(%__MODULE__{title: title}), do: Title.to_string(title)

  # ── privados ──────────────────────────────────────────────────────────────

  defp project_ref(nil), do: {:ok, nil}
  defp project_ref(""), do: {:ok, nil}
  defp project_ref(%Slug{} = slug), do: {:ok, slug}

  defp project_ref(value) do
    case Slug.new(value) do
      {:ok, slug} -> {:ok, slug}
      {:error, _} -> {:error, :invalid_project}
    end
  end

  defp resolve_slug(nil), do: {:ok, Slug.generate()}
  defp resolve_slug(value), do: Slug.new(value)

  defp fetch(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
