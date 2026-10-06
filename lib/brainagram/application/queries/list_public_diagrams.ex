defmodule Brainagram.Application.Queries.ListPublicDiagrams do
  @moduledoc "Lista os diagramas públicos mais recentes."

  use Brainagram.Application.Query,
    handler: Brainagram.Application.QueryHandlers.ListPublicDiagrams,
    fields: [limit: :integer],
    required: []

  import Ecto.Changeset

  @impl true
  def changeset(changeset) do
    changeset
    |> update_change(:limit, &min(&1, 200))
    |> validate_number(:limit, greater_than: 0)
  end
end
