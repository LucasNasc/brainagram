defmodule Brainagram.Application.Commands.ForkDiagram do
  @moduledoc """
  Duplica um diagrama sob um slug novo.

  Substitui o "renomear" que normalmente apareceria num CRUD: quando o texto é
  a fonte da verdade, bifurcar é a operação que as pessoas realmente querem —
  partir do diagrama de alguém e seguir por conta própria.
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.ForkDiagram,
    fields: [slug: :string],
    required: [:slug]
end
