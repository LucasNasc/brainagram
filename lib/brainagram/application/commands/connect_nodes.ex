defmodule Brainagram.Application.Commands.ConnectNodes do
  @moduledoc """
  Nova seta entre dois nós, no passo indicado (ou no último).

  Gesto do canvas (spec 001, §6). Como todo comando de autoria, vira uma
  edição cirúrgica do fonte persistido via `Diagram.apply_edit/2` — o texto
  continua sendo a fonte da verdade, e edição que não muda nada não gera evento.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.EditDiagram,
    fields: [
      slug: :string,
      from: :string,
      to: :string,
      arrow: :string,
      label: :string,
      step: :integer
    ],
    required: [:slug, :from, :to]

  @impl true
  def changeset(changeset) do
    Ecto.Changeset.validate_inclusion(changeset, :arrow, ~w(sync return async fail))
  end
end
