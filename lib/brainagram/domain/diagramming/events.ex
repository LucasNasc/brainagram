defmodule Brainagram.Domain.Diagramming.Events do
  @moduledoc """
  Eventos de domínio e seus construtores.

  Eventos carregam tipos primitivos, não value objects. É deliberado: eles
  atravessam o `Phoenix.PubSub` (e um dia um broker), então precisam ser
  baratos de serializar e estáveis no tempo. Value object é para dentro do
  domínio; evento é contrato para fora.
  """

  alias Brainagram.Domain.Diagramming.{Diagram, Project}

  alias Brainagram.Domain.Diagramming.ValueObjects.{
    Kind,
    ProjectColor,
    ProjectName,
    Slug,
    Title,
    Visibility
  }

  defmodule DiagramCreated do
    @moduledoc false
    @enforce_keys [:slug, :title, :kind, :visibility, :occurred_at]
    defstruct [:slug, :title, :kind, :visibility, :occurred_at]

    @type t :: %__MODULE__{
            slug: String.t(),
            title: String.t(),
            kind: String.t(),
            visibility: String.t(),
            occurred_at: DateTime.t()
          }
  end

  defmodule DiagramSourceChanged do
    @moduledoc false
    @enforce_keys [:slug, :title, :kind, :previous_kind, :occurred_at]
    defstruct [:slug, :title, :kind, :previous_kind, :occurred_at]

    @type t :: %__MODULE__{
            slug: String.t(),
            title: String.t(),
            kind: String.t(),
            previous_kind: String.t(),
            occurred_at: DateTime.t()
          }
  end

  defmodule DiagramVisibilityChanged do
    @moduledoc false
    @enforce_keys [:slug, :visibility, :occurred_at]
    defstruct [:slug, :visibility, :occurred_at]

    @type t :: %__MODULE__{slug: String.t(), visibility: String.t(), occurred_at: DateTime.t()}
  end

  defmodule DiagramForked do
    @moduledoc false
    @enforce_keys [:slug, :origin_slug, :occurred_at]
    defstruct [:slug, :origin_slug, :occurred_at]

    @type t :: %__MODULE__{slug: String.t(), origin_slug: String.t(), occurred_at: DateTime.t()}
  end

  defmodule DiagramDeleted do
    @moduledoc false
    @enforce_keys [:slug, :occurred_at]
    defstruct [:slug, :occurred_at]

    @type t :: %__MODULE__{slug: String.t(), occurred_at: DateTime.t()}
  end

  defmodule DiagramMoved do
    @moduledoc false
    @enforce_keys [:slug, :project, :previous_project, :occurred_at]
    defstruct [:slug, :project, :previous_project, :occurred_at]

    @type t :: %__MODULE__{
            slug: String.t(),
            project: String.t() | nil,
            previous_project: String.t() | nil,
            occurred_at: DateTime.t()
          }
  end

  defmodule ProjectCreated do
    @moduledoc false
    @enforce_keys [:project, :name, :color, :occurred_at]
    defstruct [:project, :name, :color, :occurred_at]

    @type t :: %__MODULE__{
            project: String.t(),
            name: String.t(),
            color: String.t(),
            occurred_at: DateTime.t()
          }
  end

  defmodule ProjectUpdated do
    @moduledoc false
    @enforce_keys [:project, :name, :color, :occurred_at]
    defstruct [:project, :name, :color, :occurred_at]

    @type t :: %__MODULE__{
            project: String.t(),
            name: String.t(),
            color: String.t(),
            occurred_at: DateTime.t()
          }
  end

  defmodule ProjectDeleted do
    @moduledoc false
    @enforce_keys [:project, :occurred_at]
    defstruct [:project, :occurred_at]

    @type t :: %__MODULE__{project: String.t(), occurred_at: DateTime.t()}
  end

  @type t ::
          DiagramCreated.t()
          | DiagramSourceChanged.t()
          | DiagramVisibilityChanged.t()
          | DiagramForked.t()
          | DiagramDeleted.t()
          | DiagramMoved.t()
          | ProjectCreated.t()
          | ProjectUpdated.t()
          | ProjectDeleted.t()

  @spec created(Diagram.t()) :: DiagramCreated.t()
  def created(%Diagram{} = diagram) do
    %DiagramCreated{
      slug: Slug.to_string(diagram.slug),
      title: Title.to_string(diagram.title),
      kind: Kind.to_string(diagram.kind),
      visibility: Visibility.to_string(diagram.visibility),
      occurred_at: diagram.updated_at
    }
  end

  @spec source_changed(Diagram.t(), Kind.t()) :: DiagramSourceChanged.t()
  def source_changed(%Diagram{} = diagram, previous_kind) do
    %DiagramSourceChanged{
      slug: Slug.to_string(diagram.slug),
      title: Title.to_string(diagram.title),
      kind: Kind.to_string(diagram.kind),
      previous_kind: Kind.to_string(previous_kind),
      occurred_at: diagram.updated_at
    }
  end

  @spec visibility_changed(Diagram.t()) :: DiagramVisibilityChanged.t()
  def visibility_changed(%Diagram{} = diagram) do
    %DiagramVisibilityChanged{
      slug: Slug.to_string(diagram.slug),
      visibility: Visibility.to_string(diagram.visibility),
      occurred_at: diagram.updated_at
    }
  end

  @spec forked(Diagram.t(), Diagram.t()) :: DiagramForked.t()
  def forked(%Diagram{} = origin, %Diagram{} = copy) do
    %DiagramForked{
      slug: Slug.to_string(copy.slug),
      origin_slug: Slug.to_string(origin.slug),
      occurred_at: copy.inserted_at
    }
  end

  @spec deleted(Diagram.t()) :: DiagramDeleted.t()
  def deleted(%Diagram{} = diagram) do
    %DiagramDeleted{
      slug: Slug.to_string(diagram.slug),
      occurred_at: Brainagram.Shared.Clock.now()
    }
  end

  @spec moved(Diagram.t(), Slug.t() | nil) :: DiagramMoved.t()
  def moved(%Diagram{} = diagram, previous) do
    %DiagramMoved{
      slug: Slug.to_string(diagram.slug),
      project: slug_or_nil(diagram.project),
      previous_project: slug_or_nil(previous),
      occurred_at: diagram.updated_at
    }
  end

  @doc "Um diagrama que saiu do projeto porque o projeto foi excluído."
  @spec detached(String.t(), Slug.t()) :: DiagramMoved.t()
  def detached(diagram_slug, %Slug{} = project) do
    %DiagramMoved{
      slug: diagram_slug,
      project: nil,
      previous_project: Slug.to_string(project),
      occurred_at: Brainagram.Shared.Clock.now()
    }
  end

  @spec project_created(Project.t()) :: ProjectCreated.t()
  def project_created(%Project{} = project) do
    %ProjectCreated{
      project: Slug.to_string(project.slug),
      name: ProjectName.to_string(project.name),
      color: ProjectColor.to_string(project.color),
      occurred_at: project.updated_at
    }
  end

  @spec project_updated(Project.t()) :: ProjectUpdated.t()
  def project_updated(%Project{} = project) do
    %ProjectUpdated{
      project: Slug.to_string(project.slug),
      name: ProjectName.to_string(project.name),
      color: ProjectColor.to_string(project.color),
      occurred_at: project.updated_at
    }
  end

  @spec project_deleted(Project.t()) :: ProjectDeleted.t()
  def project_deleted(%Project{} = project) do
    %ProjectDeleted{
      project: Slug.to_string(project.slug),
      occurred_at: Brainagram.Shared.Clock.now()
    }
  end

  defp slug_or_nil(nil), do: nil
  defp slug_or_nil(slug), do: Slug.to_string(slug)

  @doc """
  Tópico de broadcast do evento.

  Um tópico por diagrama (`diagram:abc123`) mais um tópico global
  (`diagrams`). O primeiro é o que a edição colaborativa vai usar; o segundo
  serve a listagens e métricas — a área de gestão escuta ele. Eventos de
  projeto vão só para o global.
  """
  @spec topics(t()) :: [String.t()]
  def topics(%{project: _, name: _}), do: ["diagrams"]
  def topics(%ProjectDeleted{}), do: ["diagrams"]
  def topics(%{slug: slug}), do: ["diagram:" <> slug, "diagrams"]
end
