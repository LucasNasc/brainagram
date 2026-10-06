defmodule Brainagram.Application.QueryHandlers.RenderScene do
  @moduledoc """
  Compila fonte em cena. Sem banco, sem efeito colateral.

  O erro devolvido preserva a lista inteira de problemas de sintaxe — é o que o
  editor precisa para marcar todas as linhas de uma vez, em vez de revelar um
  erro por tentativa.
  """

  @behaviour Brainagram.Application.QueryHandler

  alias Brainagram.Application.Queries.RenderScene
  alias Brainagram.Domain.Diagramming.ValueObjects.Source

  @impl true
  def handle(%RenderScene{source: raw}) do
    with {:ok, source} <- Source.new(raw) do
      {:ok, Source.scene(source)}
    end
  end
end
