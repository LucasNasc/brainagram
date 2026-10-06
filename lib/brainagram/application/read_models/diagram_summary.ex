defmodule Brainagram.Application.ReadModels.DiagramSummary do
  @moduledoc """
  Um diagrama como aparece numa listagem.

  Não traz o fonte de propósito: listar 50 diagramas não deve arrastar 50
  blocos de texto pela rede para exibir três campos. O projeto vem já com
  nome e cor (um `join` no leitor), para o card não precisar de outra consulta.
  """

  @enforce_keys [:slug, :title, :kind]
  defstruct [
    :slug,
    :title,
    :kind,
    :visibility,
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
          project: String.t() | nil,
          project_name: String.t() | nil,
          project_color: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t()
        }
end
