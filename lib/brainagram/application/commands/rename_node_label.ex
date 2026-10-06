defmodule Brainagram.Application.Commands.RenameNodeLabel do
  @moduledoc """
  Troca o rótulo de um nó (duplo clique no canvas).

  Gesto do canvas (spec 001, §6). Como todo comando de autoria, vira uma
  edição cirúrgica do fonte persistido via `Diagram.apply_edit/2` — o texto
  continua sendo a fonte da verdade, e edição que não muda nada não gera evento.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.EditDiagram,
    fields: [slug: :string, node_id: :string, label: :string],
    required: [:slug, :node_id, :label]
end
