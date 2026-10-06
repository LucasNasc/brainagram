defmodule Brainagram.Application.Commands.MoveDiagram do
  @moduledoc "Leva um diagrama para outro projeto; `project` vazio tira de qualquer projeto."

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.MoveDiagram,
    fields: [slug: :string, project: :string],
    required: [:slug]
end
