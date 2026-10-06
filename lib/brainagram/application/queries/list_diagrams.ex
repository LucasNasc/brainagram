defmodule Brainagram.Application.Queries.ListDiagrams do
  @moduledoc """
  Os diagramas da área de gestão, sem o fonte.

    * `project`: slug de um projeto, `"none"` para os sem projeto, vazio para
      todos;
    * `search`: trecho do título;
    * `kind`: `"sequence"` ou `"architecture"`;
    * `sort`: `"updated"` (padrão), `"created"` ou `"title"`.
  """

  use Brainagram.Application.Query,
    handler: Brainagram.Application.QueryHandlers.ListDiagrams,
    fields: [project: :string, search: :string, kind: :string, sort: :string],
    required: []

  import Ecto.Changeset

  @impl true
  def changeset(changeset) do
    changeset
    |> validate_inclusion(:kind, ~w(sequence architecture))
    |> validate_inclusion(:sort, ~w(updated created title))
    |> validate_length(:search, max: 160)
  end
end
