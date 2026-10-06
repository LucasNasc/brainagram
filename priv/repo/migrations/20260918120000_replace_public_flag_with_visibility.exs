defmodule Brainagram.Repo.Migrations.ReplacePublicFlagWithVisibility do
  @moduledoc """
  Troca o boolean `public` por uma coluna `visibility`.

  O domínio modela visibilidade como enum justamente porque um terceiro estado
  (`:unlisted` — acessível por link, fora da listagem) já está no roadmap. Um
  boolean obrigaria uma migração de dados no pior momento possível: junto com a
  feature. A tabela passa a espelhar o modelo agora, enquanto custa barato.
  """

  use Ecto.Migration

  def up do
    alter table(:diagrams) do
      add :visibility, :string, null: false, default: "public"
    end

    execute "UPDATE diagrams SET visibility = CASE WHEN public THEN 'public' ELSE 'private' END"

    drop_if_exists index(:diagrams, [:public, :updated_at])

    alter table(:diagrams) do
      remove :public
    end

    create index(:diagrams, [:visibility, :updated_at])
  end

  def down do
    alter table(:diagrams) do
      add :public, :boolean, null: false, default: true
    end

    execute "UPDATE diagrams SET public = (visibility = 'public')"

    drop_if_exists index(:diagrams, [:visibility, :updated_at])

    alter table(:diagrams) do
      remove :visibility
    end

    create index(:diagrams, [:public, :updated_at])
  end
end
