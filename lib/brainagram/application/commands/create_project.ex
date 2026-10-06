defmodule Brainagram.Application.Commands.CreateProject do
  @moduledoc "Cria um projeto — uma pasta com nome e cor para separar diagramas."

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.CreateProject,
    fields: [name: :string, color: :string, slug: :string],
    required: [:name]
end
