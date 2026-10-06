defmodule Brainagram.Infrastructure.Persistence.ProjectRecord do
  @moduledoc "O schema Ecto dos projetos — só o schema, como o `DiagramRecord`."

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "projects" do
    field :slug, :string
    field :name, :string
    field :color, :string

    timestamps(type: :utc_datetime)
  end

  @fields [:slug, :name, :color, :inserted_at, :updated_at]

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(record, attrs) do
    record
    |> cast(attrs, @fields)
    |> validate_required([:slug, :name, :color])
    |> unique_constraint(:slug)
  end
end
