defmodule Brainagram.Application.ReadModels.ProjectSummary do
  @moduledoc "Um projeto como aparece na lateral da área de gestão: com a contagem de diagramas."

  @enforce_keys [:slug, :name, :color]
  defstruct [:slug, :name, :color, diagram_count: 0, updated_at: nil]

  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          color: String.t(),
          diagram_count: non_neg_integer(),
          updated_at: DateTime.t() | nil
        }
end
