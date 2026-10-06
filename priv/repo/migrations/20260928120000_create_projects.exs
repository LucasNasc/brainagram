defmodule Brainagram.Repo.Migrations.CreateProjects do
  @moduledoc """
  Projetos: pastas para separar os diagramas.

  O diagrama aponta para o projeto pelo **slug** (`project_slug`), que é a
  identidade que o domínio conhece — o `id` inteiro é detalhe do banco.

  `on_delete: :nilify_all` é rede de proteção, não a regra: excluir um projeto
  deixa os diagramas sem projeto, e quem faz isso de fato é o handler, pela
  porta do repositório. A constraint garante que nenhum diagrama fique
  apontando para um projeto que não existe mais, venha a exclusão de onde vier.
  """

  use Ecto.Migration

  def change do
    create table(:projects) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :color, :string, null: false, default: "violet"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:slug])

    alter table(:diagrams) do
      add :project_slug,
          references(:projects, column: :slug, type: :string, on_delete: :nilify_all)
    end

    create index(:diagrams, [:project_slug, :updated_at])
  end
end
