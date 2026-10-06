defmodule Brainagram.Repo.Migrations.CreateDiagrams do
  use Ecto.Migration

  def change do
    create table(:diagrams) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :kind, :string, null: false, default: "sequence"
      add :source, :text, null: false
      add :public, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:diagrams, [:slug])
    create index(:diagrams, [:public, :updated_at])
  end
end
