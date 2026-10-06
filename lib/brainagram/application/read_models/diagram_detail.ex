defmodule Brainagram.Application.ReadModels.DiagramDetail do
  @moduledoc """
  Um diagrama aberto no editor: metadados, fonte e a cena já compilada.

  A cena é montada pelo handler da query, não pelo leitor. O leitor entrega
  dados da tabela; compilar é regra de domínio, e é a camada de aplicação que
  decide chamá-la.
  """

  alias Brainagram.Domain.Diagramming.Scene

  @enforce_keys [:slug, :title, :kind, :source]
  defstruct [
    :slug,
    :title,
    :kind,
    :visibility,
    :source,
    :scene,
    :project,
    :project_name,
    :project_color,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          slug: String.t(),
          title: String.t(),
          kind: String.t(),
          visibility: String.t(),
          source: String.t(),
          scene: Scene.t() | nil,
          project: String.t() | nil,
          project_name: String.t() | nil,
          project_color: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }
end
