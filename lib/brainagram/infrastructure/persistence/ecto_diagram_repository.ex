defmodule Brainagram.Infrastructure.Persistence.EctoDiagramRepository do
  @moduledoc """
  Implementação Postgres da porta de escrita.

  Detalhe que vale explicar: no retorno do `insert`/`update` o agregado **não**
  é reconstruído a partir do registro salvo. Só o `id` e os timestamps são
  costurados de volta no agregado que já estava em mãos. Reconstruir obrigaria
  a re-parsear a DSL sem necessidade — e o `%Source{}` recém-validado já está
  ali, íntegro.
  """

  @behaviour Brainagram.Domain.Diagramming.Ports.DiagramRepository

  import Ecto.Query

  alias Brainagram.Domain.Diagramming.Diagram
  alias Brainagram.Domain.Diagramming.ValueObjects.Slug
  alias Brainagram.Infrastructure.Persistence.{DiagramMapper, DiagramRecord, Repo}

  @impl true
  def insert(%Diagram{} = diagram) do
    %DiagramRecord{}
    |> DiagramRecord.changeset(DiagramMapper.to_attrs(diagram))
    |> Repo.insert()
    |> merge_persisted(diagram)
  end

  @impl true
  def update(%Diagram{id: nil}), do: {:error, :not_persisted}

  def update(%Diagram{} = diagram) do
    case Repo.get(DiagramRecord, diagram.id) do
      nil ->
        {:error, :not_found}

      record ->
        record
        |> DiagramRecord.changeset(DiagramMapper.to_attrs(diagram))
        |> Repo.update()
        |> merge_persisted(diagram)
    end
  end

  @impl true
  def delete(%Diagram{id: nil}), do: {:error, :not_persisted}

  def delete(%Diagram{id: id}) do
    case Repo.delete_all(from r in DiagramRecord, where: r.id == ^id) do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  @impl true
  def fetch_by_slug(%Slug{} = slug) do
    case Repo.get_by(DiagramRecord, slug: Slug.to_string(slug)) do
      nil -> {:error, :not_found}
      record -> DiagramMapper.to_entity(record)
    end
  end

  @impl true
  def detach_project(%Slug{} = project) do
    slug = Slug.to_string(project)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {_count, rows} =
      Repo.update_all(
        from(r in DiagramRecord, where: r.project_slug == ^slug, select: r.slug),
        set: [project_slug: nil, updated_at: now]
      )

    {:ok, rows}
  end

  defp merge_persisted({:ok, record}, %Diagram{} = diagram) do
    {:ok,
     %{
       diagram
       | id: record.id,
         inserted_at: record.inserted_at,
         updated_at: record.updated_at
     }}
  end

  defp merge_persisted({:error, %Ecto.Changeset{} = changeset}, _diagram) do
    cond do
      Keyword.has_key?(changeset.errors, :slug) -> {:error, :slug_taken}
      Keyword.has_key?(changeset.errors, :project_slug) -> {:error, :project_not_found}
      true -> {:error, changeset}
    end
  end
end
