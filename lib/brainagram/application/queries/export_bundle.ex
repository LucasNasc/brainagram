defmodule Brainagram.Application.Queries.ExportBundle do
  @moduledoc """
  Exporta diagramas num pacote (`Bundle`): um projeto (`project` = slug), os
  sem projeto (`"none"`) ou todos (vazio). Devolve `%{json, filename, count}`.
  """

  use Brainagram.Application.Query,
    handler: Brainagram.Application.QueryHandlers.ExportBundle,
    fields: [project: :string],
    required: []
end
