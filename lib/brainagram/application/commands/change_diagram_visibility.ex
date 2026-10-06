defmodule Brainagram.Application.Commands.ChangeDiagramVisibility do
  @moduledoc "Publica ou despublica um diagrama."

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.ChangeDiagramVisibility,
    fields: [slug: :string, visibility: :string],
    required: [:slug, :visibility]
end
