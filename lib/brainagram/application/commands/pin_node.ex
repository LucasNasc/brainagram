defmodule Brainagram.Application.Commands.PinNode do
  @moduledoc """
  Fixa um nó numa posição do canvas — uma linha no bloco `layout` do fonte.

  Gesto do canvas (spec 001, §6). Como todo comando de autoria, vira uma
  edição cirúrgica do fonte persistido via `Diagram.apply_edit/2` — o texto
  continua sendo a fonte da verdade, e edição que não muda nada não gera evento.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.EditDiagram,
    fields: [slug: :string, node_id: :string, x: :integer, y: :integer],
    required: [:slug, :node_id, :x, :y]
end
