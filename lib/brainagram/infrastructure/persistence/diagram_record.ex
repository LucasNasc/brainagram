defmodule Brainagram.Infrastructure.Persistence.DiagramRecord do
  @moduledoc """
  O schema Ecto — e **só** o schema.

  Aqui não existe regra de negócio: nada de derivar título, gerar slug ou
  decidir visibilidade. Tudo isso já aconteceu no agregado antes de a linha
  chegar aqui. O changeset carrega apenas o que o banco precisa saber: tipos,
  obrigatoriedade e as restrições que só o Postgres consegue garantir de fato
  (unicidade sob concorrência).

  A separação custa um mapper. Em troca, o domínio compila e roda sem Ecto, o
  que significa teste de regra de negócio sem banco — o retorno aparece já na
  primeira dúzia de testes.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "diagrams" do
    field :slug, :string
    field :title, :string
    field :kind, :string
    field :source, :string
    field :visibility, :string
    field :project_slug, :string

    timestamps(type: :utc_datetime)
  end

  @fields [:slug, :title, :kind, :source, :visibility, :project_slug, :inserted_at, :updated_at]

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, @fields)
    |> validate_required([:slug, :title, :kind, :source, :visibility])
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:project_slug)
  end
end
