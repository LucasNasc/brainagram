defmodule Brainagram.Application.Commands.AddNode do
  @moduledoc """
  Declara um nó novo (arrastar em área vazia). Com `x`/`y`, ele já nasce fixado ali.

  Gesto do canvas (spec 001, §6). Como todo comando de autoria, vira uma
  edição cirúrgica do fonte persistido via `Diagram.apply_edit/2` — o texto
  continua sendo a fonte da verdade, e edição que não muda nada não gera evento.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.EditDiagram,
    fields: [
      slug: :string,
      label: :string,
      kind: :string,
      group: :string,
      x: :integer,
      y: :integer
    ],
    required: [:slug]
end
