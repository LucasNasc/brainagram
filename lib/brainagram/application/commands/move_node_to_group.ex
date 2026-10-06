defmodule Brainagram.Application.Commands.MoveNodeToGroup do
  @moduledoc """
  Move a declaração do nó para dentro de um `group` (pelo rótulo) ou para fora de todos (sem `group`).

  Gesto do canvas (spec 001, §6). Como todo comando de autoria, vira uma
  edição cirúrgica do fonte persistido via `Diagram.apply_edit/2` — o texto
  continua sendo a fonte da verdade, e edição que não muda nada não gera evento.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.EditDiagram,
    fields: [slug: :string, node_id: :string, group: :string],
    required: [:slug, :node_id]
end
