defmodule Brainagram.Application.Commands.CreateDiagram do
  @moduledoc """
  Cria um diagrama a partir do fonte da DSL.

  Não há campo de título nem de tipo: ambos são derivados do fonte pelo
  agregado. Aceitar esses campos aqui seria abrir a porta para o metadado
  divergir do conteúdo. `project` (opcional) é o slug do projeto onde ele nasce.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.CreateDiagram,
    fields: [source: :string, slug: :string, visibility: :string, project: :string],
    required: [:source]
end
