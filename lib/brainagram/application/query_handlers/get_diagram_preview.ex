defmodule Brainagram.Application.QueryHandlers.GetDiagramPreview do
  @moduledoc "Lê o diagrama, compila a cena e a desenha em SVG (`Render.Svg`)."

  @behaviour Brainagram.Application.QueryHandler

  alias Brainagram.Application.Queries.{GetDiagramBySlug, GetDiagramPreview}
  alias Brainagram.Application.QueryHandlers
  alias Brainagram.Domain.Diagramming.Render.Svg

  @impl true
  def handle(%GetDiagramPreview{slug: slug}) do
    case QueryHandlers.GetDiagramBySlug.handle(%GetDiagramBySlug{slug: slug}) do
      {:ok, %{scene: nil}} ->
        {:error, :not_found}

      {:ok, detail} ->
        {:ok, %{svg: Svg.render(detail.scene, background: false), updated_at: detail.updated_at}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
