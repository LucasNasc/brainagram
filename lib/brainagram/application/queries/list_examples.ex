defmodule Brainagram.Application.Queries.ListExamples do
  @moduledoc "Lista os diagramas de exemplo oferecidos no editor."

  use Brainagram.Application.Query,
    handler: Brainagram.Application.QueryHandlers.ListExamples,
    fields: [],
    required: []
end
