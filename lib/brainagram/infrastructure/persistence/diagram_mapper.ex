defmodule Brainagram.Infrastructure.Persistence.DiagramMapper do
  @moduledoc """
  Tradução entre o agregado e a linha da tabela.

  A direção `registro → agregado` re-parseia o fonte, e isso é intencional: o
  `%Source{}` é um value object que só existe se compilar, então reconstituir
  um agregado a partir do banco tem que passar pela mesma porta que a escrita
  passou. Uma linha corrompida vira `{:error, ...}` explícito em vez de um
  agregado inválido circulando pelo sistema.
  """

  alias Brainagram.Domain.Diagramming.Diagram
  alias Brainagram.Domain.Diagramming.ValueObjects.{Kind, Slug, Source, Title, Visibility}
  alias Brainagram.Infrastructure.Persistence.DiagramRecord

  @spec to_entity(DiagramRecord.t()) :: {:ok, Diagram.t()} | {:error, term()}
  def to_entity(%DiagramRecord{} = record) do
    with {:ok, slug} <- Slug.new(record.slug),
         {:ok, title} <- Title.new(record.title),
         {:ok, kind} <- Kind.new(record.kind),
         {:ok, visibility} <- Visibility.new(record.visibility),
         {:ok, source} <- Source.new(record.source),
         {:ok, project} <- project(record.project_slug) do
      {:ok,
       %Diagram{
         id: record.id,
         slug: slug,
         title: title,
         kind: kind,
         source: source,
         visibility: visibility,
         project: project,
         inserted_at: record.inserted_at,
         updated_at: record.updated_at
       }}
    end
  end

  defp project(nil), do: {:ok, nil}
  defp project(slug), do: Slug.new(slug)

  @spec to_attrs(Diagram.t()) :: map()
  def to_attrs(%Diagram{} = diagram) do
    %{
      slug: Slug.to_string(diagram.slug),
      title: Title.to_string(diagram.title),
      kind: Kind.to_string(diagram.kind),
      source: Source.raw(diagram.source),
      visibility: Visibility.to_string(diagram.visibility),
      project_slug: diagram.project && Slug.to_string(diagram.project),
      inserted_at: diagram.inserted_at,
      updated_at: diagram.updated_at
    }
  end
end
