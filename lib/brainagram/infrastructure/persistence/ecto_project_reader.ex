defmodule Brainagram.Infrastructure.Persistence.EctoProjectReader do
  @moduledoc """
  Implementação Postgres da leitura de projetos: a lista da lateral, com a
  contagem de diagramas de cada um numa consulta só.
  """

  @behaviour Brainagram.Application.Ports.ProjectReader

  import Ecto.Query

  alias Brainagram.Application.ReadModels.ProjectSummary
  alias Brainagram.Infrastructure.Persistence.{DiagramRecord, ProjectRecord, Repo}

  @impl true
  def list do
    base()
    |> order_by([p], asc: fragment("lower(?)", p.name), asc: p.id)
    |> Repo.all()
    |> Enum.map(&struct!(ProjectSummary, &1))
  end

  @impl true
  def fetch_by_slug(slug) when is_binary(slug) do
    case base() |> where([p], p.slug == ^slug) |> Repo.one() do
      nil -> {:error, :not_found}
      row -> {:ok, struct!(ProjectSummary, row)}
    end
  end

  defp base do
    from p in ProjectRecord,
      left_join: d in DiagramRecord,
      on: d.project_slug == p.slug,
      group_by: p.id,
      select: %{
        slug: p.slug,
        name: p.name,
        color: p.color,
        diagram_count: count(d.id),
        updated_at: p.updated_at
      }
  end
end
