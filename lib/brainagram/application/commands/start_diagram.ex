defmodule Brainagram.Application.Commands.StartDiagram do
  @moduledoc """
  Começa um diagrama novo pela área de gestão: nome, tipo e projeto.

  Diferente de `CreateDiagram`, que recebe o fonte pronto, aqui quem escreve o
  texto inicial é o domínio (`Templates.starter/3`) — com o título escolhido
  já no cabeçalho, então o título continua vindo do fonte. `lang` é o idioma
  do conteúdo inicial (`pt`, `en`, `zh`, `ru`, `it`, `ja` ou `hi`).
  """

  use Brainagram.Application.Command,
    handler: Brainagram.Application.Handlers.StartDiagram,
    fields: [title: :string, kind: :string, project: :string, lang: :string],
    required: [:title]

  import Ecto.Changeset

  @impl true
  def changeset(changeset) do
    changeset
    |> validate_inclusion(:kind, ~w(sequence architecture))
    |> validate_inclusion(:lang, ~w(pt en zh ru it ja hi))
    |> validate_length(:title, max: 160)
  end
end
