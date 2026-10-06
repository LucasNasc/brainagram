defmodule Brainagram.Application.Commands.DeleteDiagram do
  @moduledoc "Remove um diagrama."

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.DeleteDiagram,
    fields: [slug: :string],
    required: [:slug]
end
