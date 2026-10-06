defmodule Brainagram.Domain.Diagramming.Layout.QualityTest do
  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.Layout.Quality
  alias Brainagram.Domain.Diagramming.Scene

  defp box(id, x, y), do: %{id: id, x: x, y: y, w: 100, h: 60, cx: x + 50, cy: y + 30, group: nil}
  defp edge(id, from, to, path), do: %{id: id, from: from, to: to, path: path}

  defp scene(nodes, edges, groups \\ []),
    do: %Scene{kind: :architecture, nodes: nodes, edges: edges, groups: groups}

  test "polyline lê M, L, Q e C" do
    assert [{+0.0, +0.0}, {10.0, +0.0} | _] = Quality.polyline("M 0 0 L 10 0 Q 20 0 20 10")
    assert List.last(Quality.polyline("M 0 0 C 0 10 10 10 10 20")) == {10.0, 20.0}
  end

  test "duas setas em X contam um cruzamento" do
    nodes = [box("a", 0, 0), box("b", 300, 300), box("c", 300, 0), box("d", 0, 300)]

    edges = [
      edge("e1", "a", "b", "M 50 60 L 350 300"),
      edge("e2", "c", "d", "M 350 60 L 50 300")
    ]

    assert %{crossings: 1, node_hits: 0} = Quality.measure(scene(nodes, edges))
  end

  test "setas que só se tocam na origem não se cruzam" do
    nodes = [box("a", 0, 0), box("b", 0, 300), box("c", 300, 300)]

    edges = [
      edge("e1", "a", "b", "M 50 60 L 50 300"),
      edge("e2", "a", "c", "M 50 60 L 350 300")
    ]

    assert %{crossings: 0} = Quality.measure(scene(nodes, edges))
  end

  test "seta por cima de uma caixa alheia conta como node_hit" do
    nodes = [box("a", 0, 0), box("meio", 0, 150), box("b", 0, 300)]
    edges = [edge("e1", "a", "b", "M 50 60 L 50 300")]

    assert %{node_hits: 1} = Quality.measure(scene(nodes, edges))
  end

  test "seta que atravessa um grupo sem membro envolvido conta como group_hit" do
    nodes = [box("a", 0, 0), box("b", 0, 300)]
    groups = [%{id: "g", label: "G", x: -20, y: 120, w: 200, h: 120}]
    edges = [edge("e1", "a", "b", "M 50 60 L 50 300")]

    assert %{group_hits: 1} = Quality.measure(scene(nodes, edges, groups))
  end

  test "score: um cruzamento pesa mais que um caminho mais longo" do
    tangled = %{crossings: 1, node_hits: 0, group_hits: 0, bends: 0, length: 100}
    longer = %{crossings: 0, node_hits: 0, group_hits: 0, bends: 2, length: 900}

    assert Quality.score(longer) < Quality.score(tangled)
  end
end
