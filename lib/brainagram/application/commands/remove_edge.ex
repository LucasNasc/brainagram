defmodule Brainagram.Application.Commands.RemoveEdge do
  @moduledoc """
  Remove uma seta.

  Gesto do canvas (spec 001, §6). Como todo comando de autoria, vira uma
  edição cirúrgica do fonte persistido via `Diagram.apply_edit/2` — o texto
  continua sendo a fonte da verdade, e edição que não muda nada não gera evento.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.EditDiagram,
    fields: [slug: :string, edge_id: :string],
    required: [:slug, :edge_id]
end
