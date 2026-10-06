defmodule Brainagram.Application.Queries.ListProjects do
  @moduledoc """
  A lateral da área de gestão: os projetos com a contagem de cada um, mais o
  total de diagramas e quantos estão sem projeto.
  """

  use Brainagram.Application.Query,
    handler: Brainagram.Application.QueryHandlers.ListProjects,
    fields: [],
    required: []
end
