defmodule Brainagram.Application.ReadModels.Example do
  @moduledoc "Um diagrama de exemplo oferecido no editor."

  @enforce_keys [:slug, :name, :source]
  defstruct [:slug, :name, :source]

  @type t :: %__MODULE__{slug: String.t(), name: String.t(), source: String.t()}
end
