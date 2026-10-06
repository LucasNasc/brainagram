defmodule Brainagram.Application.Commands.UpdateProject do
  @moduledoc "Renomeia e/ou troca a cor de um projeto. Campo ausente fica como está."

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.UpdateProject,
    fields: [slug: :string, name: :string, color: :string],
    required: [:slug]
end
