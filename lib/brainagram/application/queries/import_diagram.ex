defmodule Brainagram.Application.Queries.ImportDiagram do
  @moduledoc """
  Converte um diagrama de Mermaid ou PlantUML para a DSL, sem persistir.

  O resultado vira o texto do editor (e pode ser desfeito como qualquer outra
  edição); salvar continua sendo um passo explícito. `format` é `auto` (padrão),
  `mermaid`, `plantuml` ou `brainagram` (um `.brain` exportado daqui).

  Com `organize: true`, um diagrama de arquitetura já sai com as setas
  organizadas (`Layout.Untangle`) — é o caso comum de quem importa um
  PlantUML de componentes com setas cruzadas.
  """

  use Brainagram.Application.Query,
    handler: Brainagram.Application.QueryHandlers.ImportDiagram,
    fields: [text: :string, format: :string, organize: :boolean],
    required: [:text]

  @impl true
  def changeset(changeset) do
    Ecto.Changeset.validate_inclusion(changeset, :format, ~w(auto mermaid plantuml brainagram))
  end
end
