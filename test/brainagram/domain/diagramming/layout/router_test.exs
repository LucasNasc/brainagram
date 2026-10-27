defmodule Brainagram.Domain.Diagramming.Layout.RouterTest do
  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.Layout.{Quality, Router}
  alias Brainagram.Domain.Diagramming.Scene

  defp box(id, x, y, w \\ 156),
    do: {id, %{id: id, x: x, y: y, w: w, h: 68, cx: x + div(w, 2), cy: y + 34, group: nil}}

  defp routed_scene(boxes, edges) do
    routed = Router.route(boxes, edges)

    %Scene{
      kind: :architecture,
      nodes: Map.values(boxes),
      edges: Enum.map(edges, &Map.merge(&1, routed[&1.id])),
      groups: []
    }
  end

  # Os pontos por onde a rota passa (sem os cantos arredondados): cada trecho
  # entre dois deles é horizontal ou vertical.
  defp orthogonal?(path) do
    path
    |> String.replace(~r/Q -?\d+ -?\d+ /, "")
    |> then(&Regex.scan(~r/[ML] (-?\d+) (-?\d+)/, &1))
    |> Enum.map(fn [_, x, y] -> {String.to_integer(x), String.to_integer(y)} end)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [{x1, y1}, {x2, y2}] -> abs(x1 - x2) <= 12 or abs(y1 - y2) <= 12 end)
  end

  test "desvia de uma caixa que está no caminho" do
    boxes = Map.new([box("a", 100, 0), box("meio", 100, 200), box("b", 100, 400)])
    edges = [%{id: "e1", from: "a", to: "b"}]

    scene = routed_scene(boxes, edges)

    assert %{node_hits: 0} = Quality.measure(scene)
    assert orthogonal?(hd(scene.edges).path)
  end

  test "caixas alinhadas ligam com uma reta, sem quina" do
    boxes = Map.new([box("a", 100, 0), box("b", 104, 200, 150)])
    %{"e1" => geometry} = Router.route(boxes, [%{id: "e1", from: "a", to: "b"}])

    refute geometry.path =~ "Q"
    assert geometry.x1 == geometry.x2
  end

  test "prefer: :horizontal sai pela lateral; o padrão sai pela base" do
    boxes = Map.new([box("a", 0, 0), box("b", 400, 200)])
    edges = [%{id: "e1", from: "a", to: "b"}]

    assert %{"e1" => %{x1: 156, x2: 400}} =
             Router.route(boxes, edges, [], %{}, prefer: :horizontal)

    assert %{"e1" => %{y1: 68, y2: 200}} = Router.route(boxes, edges)
  end

  test "várias setas no mesmo lado entram por portas diferentes, na ordem das origens" do
    boxes = Map.new([box("a", 0, 0), box("b", 300, 0), box("alvo", 150, 300)])
    edges = [%{id: "e1", from: "a", to: "alvo"}, %{id: "e2", from: "b", to: "alvo"}]

    routed = Router.route(boxes, edges)

    assert routed["e1"].x2 < routed["e2"].x2
  end

  test "duas setas que precisam se cruzar se cruzam uma vez só" do
    boxes = Map.new([box("a", 0, 0), box("b", 400, 0), box("c", 0, 300), box("d", 400, 300)])
    edges = [%{id: "e1", from: "a", to: "d"}, %{id: "e2", from: "b", to: "c"}]

    assert %{crossings: 1, node_hits: 0} = Quality.measure(routed_scene(boxes, edges))
  end
end
