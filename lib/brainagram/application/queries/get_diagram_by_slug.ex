defmodule Brainagram.Application.Queries.GetDiagramBySlug do
  @moduledoc "Carrega um diagrama para edição ou visualização, com a cena já compilada."

  use Brainagram.Application.Query,
    handler: Brainagram.Application.QueryHandlers.GetDiagramBySlug,
    fields: [slug: :string],
    required: [:slug]
end
