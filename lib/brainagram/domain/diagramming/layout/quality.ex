defmodule Brainagram.Domain.Diagramming.Layout.Quality do
  @moduledoc """
  Quão legível está uma cena, medido em coisas que o olho sente.

  Na arquitetura:

    * `crossings` — pontos onde duas setas se cruzam;
    * `node_hits` — setas que passam por cima de uma caixa que não é nem a
      origem nem o destino delas (a pior coisa para quem segue um caminho);
    * `group_hits` — setas que atravessam um grupo sem ter nada a ver com ele;
    * `bends` — quinas no caminho;
    * `length` — comprimento total das setas, em px.

  Na sequência as mensagens são horizontais e não se cruzam; o que atrapalha é
  mensagem que salta por cima de outras raias. `node_hits` conta esses saltos
  (quantas raias ficam entre origem e destino) e `length` soma a extensão.

  `score/1` pesa tudo num número só: menor é melhor. Os pesos dizem a
  prioridade — atravessar caixa é pior que cruzar seta, que é pior que dobrar,
  que é pior que ser um pouco mais longa.
  """

  alias Brainagram.Domain.Diagramming.Scene

  @type t :: %{
          crossings: non_neg_integer(),
          node_hits: non_neg_integer(),
          group_hits: non_neg_integer(),
          bends: non_neg_integer(),
          length: non_neg_integer()
        }

  @weights %{crossings: 100, node_hits: 250, group_hits: 40, bends: 4}
  @length_weight 0.05

  @spec measure(Scene.t()) :: t()
  def measure(%Scene{kind: :sequence} = scene) do
    lanes =
      scene.nodes |> Enum.sort_by(& &1.cx) |> Enum.map(& &1.id) |> Enum.with_index() |> Map.new()

    {hits, length} =
      Enum.reduce(scene.edges, {0, 0}, fn edge, {hits, length} ->
        case {lanes[edge.from], lanes[edge.to]} do
          {a, b} when is_integer(a) and is_integer(b) ->
            {hits + max(abs(a - b) - 1, 0), length + abs((edge.x2 || 0) - (edge.x1 || 0))}

          _ ->
            {hits, length}
        end
      end)

    %{crossings: 0, node_hits: hits, group_hits: 0, bends: 0, length: round(length)}
  end

  def measure(%Scene{} = scene) do
    lines = Enum.map(scene.edges, &{&1, polyline(&1.path)})
    boxes = Map.new(scene.nodes, &{&1.id, &1})
    group_of = Map.new(scene.nodes, &{&1.id, Map.get(&1, :group)})

    %{
      crossings: crossings(lines),
      node_hits: node_hits(lines, boxes),
      group_hits: group_hits(lines, scene.groups, group_of),
      bends: Enum.sum(Enum.map(scene.edges, &bends(&1.path))),
      length: lines |> Enum.map(fn {_e, pts} -> polyline_length(pts) end) |> Enum.sum() |> round()
    }
  end

  @doc "Um número só para comparar arrumações: menor é melhor."
  @spec score(t()) :: float()
  def score(metrics) do
    Enum.reduce(@weights, metrics.length * @length_weight, fn {key, w}, acc ->
      acc + Map.fetch!(metrics, key) * w
    end)
  end

  # ── caminhos ──────────────────────────────────────────────────────────────

  # Os caminhos vêm do próprio layout, sempre absolutos: M, L, C e Q. Curvas
  # viram polilinha com poucos pontos — suficiente para achar cruzamentos.
  @doc false
  def polyline(path) do
    tokens = Regex.scan(~r/[MLCQ]|-?\d+(?:\.\d+)?/, path) |> List.flatten()
    walk(tokens, nil, [])
  end

  defp walk([], _cur, acc), do: Enum.reverse(acc)

  defp walk(["M", x, y | rest], _cur, acc) do
    p = {num(x), num(y)}
    walk(rest, p, [p | acc])
  end

  defp walk(["L", x, y | rest], _cur, acc) do
    p = {num(x), num(y)}
    walk(rest, p, [p | acc])
  end

  defp walk(["C", x1, y1, x2, y2, x, y | rest], cur, acc) do
    {c1, c2, p} = {{num(x1), num(y1)}, {num(x2), num(y2)}, {num(x), num(y)}}
    pts = for i <- 1..10, do: cubic(cur, c1, c2, p, i / 10)
    walk(rest, p, Enum.reverse(pts) ++ acc)
  end

  defp walk(["Q", x1, y1, x, y | rest], cur, acc) do
    {c, p} = {{num(x1), num(y1)}, {num(x), num(y)}}
    pts = for i <- 1..4, do: quad(cur, c, p, i / 4)
    walk(rest, p, Enum.reverse(pts) ++ acc)
  end

  defp walk([_ | rest], cur, acc), do: walk(rest, cur, acc)

  defp num(s), do: String.to_float(if String.contains?(s, "."), do: s, else: s <> ".0")

  defp cubic({x0, y0}, {x1, y1}, {x2, y2}, {x3, y3}, t) do
    u = 1 - t

    {u * u * u * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3,
     u * u * u * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3}
  end

  defp quad({x0, y0}, {x1, y1}, {x2, y2}, t) do
    u = 1 - t
    {u * u * x0 + 2 * u * t * x1 + t * t * x2, u * u * y0 + 2 * u * t * y1 + t * t * y2}
  end

  defp segments(pts), do: Enum.zip(pts, tl(pts))

  defp polyline_length([_ | _] = pts),
    do: pts |> segments() |> Enum.map(fn {a, b} -> dist(a, b) end) |> Enum.sum()

  defp polyline_length(_), do: 0

  defp bends(path), do: Regex.scan(~r/Q/, path) |> length()

  # ── cruzamentos ───────────────────────────────────────────────────────────

  # Dois caminhos que saem do mesmo nó se tocam na origem: isso não é
  # cruzamento. Só conta o encontro longe das pontas de ambos.
  defp crossings(lines) do
    indexed = lines |> Enum.map(fn {e, pts} -> {e, pts, bbox(pts)} end) |> Enum.with_index()

    for {{_a, pa, ba}, i} <- indexed,
        {{_b, pb, bb}, j} <- indexed,
        i < j,
        overlap?(ba, bb),
        reduce: 0 do
      acc -> acc + pair_crossings(pa, pb)
    end
  end

  defp pair_crossings(pa, pb) do
    ends = [hd(pa), List.last(pa), hd(pb), List.last(pb)]

    points =
      for {a1, a2} <- segments(pa),
          {b1, b2} <- segments(pb),
          p = intersection(a1, a2, b1, b2),
          p != nil,
          Enum.all?(ends, &(dist(&1, p) > 6)),
          do: p

    points
    |> Enum.reduce([], fn p, kept ->
      if Enum.any?(kept, &(dist(&1, p) < 4)), do: kept, else: [p | kept]
    end)
    |> length()
  end

  defp intersection({x1, y1}, {x2, y2}, {x3, y3}, {x4, y4}) do
    d = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)

    if abs(d) < 1.0e-9 do
      nil
    else
      t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / d
      u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / d
      if t > 0 and t < 1 and u > 0 and u < 1, do: {x1 + t * (x2 - x1), y1 + t * (y2 - y1)}
    end
  end

  # ── setas por cima de caixas e grupos ─────────────────────────────────────

  defp node_hits(lines, boxes) do
    for {edge, pts} <- lines,
        {id, box} <- boxes,
        id not in [edge.from, edge.to],
        passes_through?(pts, shrink(box, 3)),
        reduce: 0 do
      acc -> acc + 1
    end
  end

  # Grupo atravessado por uma seta que não sai nem chega em nenhum membro dele.
  defp group_hits(lines, groups, group_of) do
    for {edge, pts} <- lines,
        group <- groups,
        group.label not in [group_of[edge.from], group_of[edge.to]],
        passes_through?(pts, shrink(group, 4)),
        reduce: 0 do
      acc -> acc + 1
    end
  end

  defp passes_through?(pts, box) do
    pts
    |> segments()
    |> Enum.any?(fn {a, b} ->
      steps = max(1, ceil(dist(a, b) / 6))
      Enum.any?(0..steps, fn i -> inside?(lerp(a, b, i / steps), box) end)
    end)
  end

  defp shrink(%{x: x, y: y, w: w, h: h}, by),
    do: %{x: x + by, y: y + by, w: w - 2 * by, h: h - 2 * by}

  defp inside?({px, py}, box),
    do: px > box.x and px < box.x + box.w and py > box.y and py < box.y + box.h

  defp lerp({x1, y1}, {x2, y2}, t), do: {x1 + (x2 - x1) * t, y1 + (y2 - y1) * t}

  defp dist({x1, y1}, {x2, y2}), do: :math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))

  defp bbox(pts) do
    {xs, ys} = Enum.unzip(pts)
    {Enum.min(xs), Enum.min(ys), Enum.max(xs), Enum.max(ys)}
  end

  defp overlap?({ax1, ay1, ax2, ay2}, {bx1, by1, bx2, by2}),
    do: ax1 <= bx2 and bx1 <= ax2 and ay1 <= by2 and by1 <= ay2
end
