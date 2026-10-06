defmodule Brainagram.Application.QueryHandlers.EditSource do
  @moduledoc """
  Gesto → texto novo → cena. Sem banco, sem evento.

  Devolve `%{source, scene, meta}`: o texto que o editor passa a mostrar, a cena
  que o canvas desenha e o que o gesto criou (`node_id`, `edge_id`, a linha do
  cursor depois de mover um passo) para a interface apontar em seguida.
  """

  @behaviour Brainagram.Application.QueryHandler

  alias Brainagram.Application.Queries.EditSource
  alias Brainagram.Domain.Diagramming.Authoring
  alias Brainagram.Domain.Diagramming.ValueObjects.Source

  @impl true
  def handle(%EditSource{source: raw, op: op, params: params}) do
    edited =
      case Authoring.run(raw, op, params || %{}) do
        {:ok, text} -> {:ok, text, %{}}
        other -> other
      end

    with {:ok, text, meta} <- edited,
         {:ok, source} <- Source.new(text) do
      {:ok, %{source: text, scene: Source.scene(source), meta: meta}}
    end
  end
end
