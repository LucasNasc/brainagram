defmodule Brainagram.Application.Commands.ChangeEdgeArrow do
  @moduledoc """
  Troca o tipo da seta: `->`, `-->`, `->>` ou `-x`.

  Gesto do canvas (spec 001, §6). Como todo comando de autoria, vira uma
  edição cirúrgica do fonte persistido via `Diagram.apply_edit/2` — o texto
  continua sendo a fonte da verdade, e edição que não muda nada não gera evento.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.EditDiagram,
    fields: [slug: :string, edge_id: :string, arrow: :string],
    required: [:slug, :edge_id, :arrow]

  @impl true
  def changeset(changeset) do
    Ecto.Changeset.validate_inclusion(changeset, :arrow, ~w(sync return async fail))
  end
end
