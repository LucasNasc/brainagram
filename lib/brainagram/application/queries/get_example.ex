defmodule Brainagram.Application.Queries.GetExample do
  @moduledoc "Carrega um exemplo pelo slug."

  use Brainagram.Application.Query,
    handler: Brainagram.Application.QueryHandlers.GetExample,
    fields: [slug: :string],
    required: [:slug]
end
