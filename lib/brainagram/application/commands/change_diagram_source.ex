defmodule Brainagram.Application.Commands.ChangeDiagramSource do
  @moduledoc """
  Substitui o fonte de um diagrama existente.

  É o comando de maior volume do sistema — é o que roda quando alguém salva
  depois de editar. Fonte idêntico ao atual não gera evento nem `UPDATE`.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.ChangeDiagramSource,
    fields: [slug: :string, source: :string],
    required: [:slug, :source]
end
