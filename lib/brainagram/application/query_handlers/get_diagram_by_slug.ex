defmodule Brainagram.Application.QueryHandlers.GetDiagramBySlug do
  @moduledoc """
  Lê um diagrama e devolve o read model com a cena já compilada.

  A divisão de trabalho aqui é o resumo do lado de leitura: o leitor entrega
  linha de tabela, o handler chama o compilador do domínio para montar a cena.
  Em nenhum momento o agregado é reconstituído — consulta não precisa dele.
  """

  @behaviour Brainagram.Application.QueryHandler

  alias Brainagram.Application.Ports
  alias Brainagram.Application.Queries.GetDiagramBySlug
  alias Brainagram.Application.ReadModels.DiagramDetail
  alias Brainagram.Domain.Diagramming.ValueObjects.{Slug, Source}

  @impl true
  def handle(%GetDiagramBySlug{slug: raw}) do
    # O lado de leitura valida o slug pelo mesmo value object que o de escrita.
    # Sem isso, uma string fora do formato passaria batido aqui e explodiria só
    # no comando — a mesma entrada respondendo diferente conforme o caminho.
    with {:ok, slug} <- normalize(raw),
         {:ok, detail} <- Ports.diagram_reader().fetch_by_slug(slug) do
      {:ok, with_scene(detail)}
    end
  end

  defp normalize(raw) do
    case Slug.new(raw) do
      {:ok, slug} -> {:ok, Slug.to_string(slug)}
      {:error, :invalid_slug} -> {:error, :not_found}
    end
  end

  defp with_scene(%DiagramDetail{} = detail) do
    case Source.new(detail.source) do
      {:ok, source} -> %{detail | scene: Source.scene(source)}
      # Escrita valida o fonte, então isto só acontece se a DSL mudou de forma
      # incompatível depois que o registro foi salvo. Preferimos abrir o editor
      # com o texto e sem cena a devolver 500.
      {:error, _} -> %{detail | scene: nil}
    end
  end
end
