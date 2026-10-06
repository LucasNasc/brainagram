defmodule Brainagram.Application.Commands.RenameDiagram do
  @moduledoc """
  Renomeia um diagrama pela área de gestão.

  Não contradiz a regra de que o título vem do fonte: renomear **é** editar o
  fonte — troca o texto entre aspas de `diagram <tipo> "<título>"`, pelo
  mesmo trilho de edição cirúrgica dos gestos do canvas.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.EditDiagram,
    fields: [slug: :string, title: :string],
    required: [:slug, :title]
end
