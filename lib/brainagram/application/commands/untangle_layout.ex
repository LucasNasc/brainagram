defmodule Brainagram.Application.Commands.UntangleLayout do
  @moduledoc """
  "Organizar setas": reorganiza os componentes de um diagrama de arquitetura
  para que as setas se cruzem o mínimo possível (`Layout.Untangle`).

  A arrumação encontrada vai para o bloco `layout` do fonte, como posições
  fixadas — o texto continua sendo a fonte da verdade, e `ClearLayoutHints`
  volta ao automático. Sem melhora possível, o fonte não muda e nenhum evento
  é publicado.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.EditDiagram,
    fields: [slug: :string],
    required: [:slug]
end
