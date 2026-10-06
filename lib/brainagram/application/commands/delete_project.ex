defmodule Brainagram.Application.Commands.DeleteProject do
  @moduledoc """
  Exclui um projeto. Os diagramas dele **não** são apagados: ficam sem
  projeto, e a pessoa decide depois o que fazer com cada um.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.DeleteProject,
    fields: [slug: :string],
    required: [:slug]
end
