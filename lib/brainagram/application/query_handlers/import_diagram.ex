defmodule Brainagram.Application.QueryHandlers.ImportDiagram do
  @moduledoc """
  Delegado ao domínio: `Import.convert/2`, e depois `Layout.Untangle` se
  pedido. Devolve `%{source, warnings, format, organized}` — `organized` traz
  as métricas de antes e depois, ou `nil` quando não houve arrumação.
  """

  @behaviour Brainagram.Application.QueryHandler

  alias Brainagram.Application.Queries.ImportDiagram
  alias Brainagram.Domain.Diagramming.Import
  alias Brainagram.Domain.Diagramming.Layout.Untangle

  @impl true
  def handle(%ImportDiagram{text: text, format: format, organize: organize}) do
    with {:ok, result} <- Import.convert(text, format_atom(format)) do
      {:ok, organize(result, organize == true)}
    end
  end

  # Só arquitetura se organiza; sequência (ou nada a melhorar) volta como veio.
  defp organize(result, false), do: Map.put(result, :organized, nil)

  defp organize(result, true) do
    case Untangle.run(result.source) do
      {:ok, %{improved: true} = r} ->
        %{result | source: r.source} |> Map.put(:organized, Map.take(r, [:before, :after]))

      _ ->
        Map.put(result, :organized, nil)
    end
  end

  defp format_atom("mermaid"), do: :mermaid
  defp format_atom("plantuml"), do: :plantuml
  defp format_atom("brainagram"), do: :brainagram
  defp format_atom(_), do: :auto
end
