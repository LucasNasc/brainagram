defmodule Brainagram.Domain.Diagramming.Layout.Router do
  @moduledoc """
  Roteamento ortogonal que desvia de caixas.

  O roteador por corredores do layout automático foi feito para as faixas de
  grupo em colunas. Quando as posições vêm de fora — arrastadas à mão ou
  escolhidas pelo "Organizar setas" — ele não sabe onde ficam os vãos. Este
  roteia sobre qualquer geometria:

    1. **Portas espalhadas.** Várias setas no mesmo lado de uma caixa entram por
       pontos diferentes, ordenados pela posição da outra ponta — as setas não
       convergem num ponto só nem se cruzam na porta.
    2. **Grade de rotas.** As linhas candidatas são as bordas (com folga) das
       caixas, as portas e os eixos dos vãos. Toda rota anda nessa grade, então
       só dobra em ângulo reto e nunca atravessa uma caixa.
    3. **A\\* com custo de legibilidade.** Comprimento, mais um custo por quina,
       por cruzar uma seta já roteada, por correr em cima de outra e por passar
       dentro de um grupo que não é da seta. As setas curtas são roteadas
       primeiro e as longas contornam.

  O resultado usa o mesmo formato de caminho do layout automático (polilinha
  com cantos arredondados), então o canvas e a exportação não mudam nada.
  """

  alias Brainagram.Domain.Diagramming.Scene

  @clearance 10
  @stub 16
  @corner 12
  @bend_cost 36.0
  @cross_cost 160.0
  @overlap_cost 3.0
  @group_cost 1.2
  @margin 36
  @lane 18

  @type box :: %{id: String.t(), x: number(), y: number(), w: number(), h: number()}

  @doc """
  Roteia `edges` (`%{id, from, to}`) entre as caixas `boxes` (`%{id => box}`),
  evitando também os chips de título dos `groups`. Devolve `%{id => geometria}`
  com `path`, `x1`, `y1`, `x2`, `y2`, `label_x`, `label_y` e `label_anchor`.

  `prefer: :horizontal` (o layout deitado) faz a seta sair pela lateral sempre
  que as caixas não se sobrepõem na horizontal; o padrão, `:vertical`, prefere
  a base e o topo.
  """
  @spec route(
          %{String.t() => box()},
          [map()],
          [map()],
          %{String.t() => String.t() | nil},
          keyword()
        ) :: %{String.t() => map()}
  def route(boxes, edges, groups \\ [], group_of \\ %{}, opts \\ []) do
    routable = Enum.filter(edges, &((&1.from != &1.to and boxes[&1.from]) && boxes[&1.to]))
    ports = ports(routable, boxes, Keyword.get(opts, :prefer, :vertical))

    solid = Enum.map(Map.values(boxes), &inflate(&1, @clearance))
    obstacles = solid ++ Enum.map(groups, &chip_obstacle/1)

    grid = grid(obstacles, ports, boxes)

    routable
    |> Enum.sort_by(fn e -> {manhattan(ports[e.id].from_stub, ports[e.id].to_stub), e.id} end)
    |> Enum.reduce({%{}, %{segments: %{}, points: %{}}}, fn edge, {acc, used} ->
      p = ports[edge.id]
      foreign = foreign_groups(groups, group_of, edge)

      # sem caminho que respeite os títulos dos grupos, passa por cima de
      # um; sem caminho nenhum, um degrau ortogonal — nunca uma diagonal
      points =
        with nil <- astar(grid, obstacles, p.from_stub, p.to_stub, used, foreign),
             nil <- astar(grid, solid, p.from_stub, p.to_stub, used, foreign) do
          step(p.from_stub, p.to_stub)
        end

      full = simplify([p.from_port | points] ++ [p.to_port])
      label = Map.get(edge, :label)
      {Map.put(acc, edge.id, geometry(full, label, boxes)), mark(used, grid, full)}
    end)
    |> elem(0)
  end

  # ── portas ────────────────────────────────────────────────────────────────

  # Lado de saída e de entrada pela posição relativa das caixas: para baixo sai
  # pela base e entra pelo topo; para cima, o contrário; na mesma altura, pelas
  # laterais. Deitado, a ordem das perguntas se inverte.
  defp ports(edges, boxes, prefer) do
    sides =
      edges
      |> Map.new(fn e -> {e.id, sides(boxes[e.from], boxes[e.to], prefer)} end)
      |> spread_decision_exits(edges, boxes)

    # Cada lado de cada caixa: as setas dali, ordenadas pela outra ponta.
    slots =
      edges
      |> Enum.flat_map(fn e ->
        {out_side, in_side} = sides[e.id]
        [{{e.from, out_side}, {e.id, :from, e.to}}, {{e.to, in_side}, {e.id, :to, e.from}}]
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.flat_map(fn {{node, side}, entries} ->
        box = boxes[node]

        entries
        |> Enum.sort_by(fn {id, _end, other} -> {along(side, boxes[other]), id} end)
        |> Enum.with_index()
        |> Enum.map(fn {{id, end_, _other}, i} ->
          {{id, end_}, port_point(box, side, i, length(entries))}
        end)
      end)
      |> Map.new()

    crowd = Enum.frequencies_by(edges, fn e -> {e.from, elem(sides[e.id], 0)} end)

    crowd =
      Enum.reduce(edges, crowd, fn e, acc ->
        Map.update(acc, {e.to, elem(sides[e.id], 1)}, 1, &(&1 + 1))
      end)

    Map.new(edges, fn e ->
      {out_side, in_side} = sides[e.id]

      {from, to} =
        snap(
          {slots[{e.id, :from}], boxes[e.from], out_side, crowd[{e.from, out_side}]},
          {slots[{e.id, :to}], boxes[e.to], in_side, crowd[{e.to, in_side}]}
        )

      {e.id,
       %{
         from_port: from,
         from_stub: stub(from, out_side),
         to_port: to,
         to_stub: stub(to, in_side)
       }}
    end)
  end

  # Porta sozinha no seu lado não precisa ficar no meio: alinha com a outra
  # ponta, e a seta sai reta em vez de dar um degrau de poucos pixels. Com as
  # duas sozinhas, as duas vão para o ponto comum mais perto do meio.
  # Lados perpendiculares (a saída lateral de um losango) não têm eixo comum
  # para alinhar: cada ponta fica na sua porta.
  defp snap({a, _box_a, side_a, _n_a}, {b, _box_b, side_b, _n_b})
       when side_a in [:top, :bottom] != side_b in [:top, :bottom],
       do: {a, b}

  defp snap({a, box_a, side_a, n_a}, {b, box_b, side_b, n_b}) do
    axis = if side_a in [:top, :bottom], do: 0, else: 1
    {lo_a, hi_a} = side_range(box_a, side_a)
    {lo_b, hi_b} = side_range(box_b, side_b)
    ca = elem(a, axis)
    cb = elem(b, axis)

    target =
      cond do
        n_a == 1 and n_b == 1 and max(lo_a, lo_b) <= min(hi_a, hi_b) ->
          r(clamp((ca + cb) / 2, max(lo_a, lo_b), min(hi_a, hi_b)))

        n_a == 1 and cb >= lo_a and cb <= hi_a ->
          {cb, cb}

        n_b == 1 and ca >= lo_b and ca <= hi_b ->
          {ca, ca}

        true ->
          nil
      end

    case target do
      nil -> {a, b}
      {ta, tb} -> {put_elem(a, axis, ta), put_elem(b, axis, tb)}
      t -> {put_elem(a, axis, t), put_elem(b, axis, t)}
    end
  end

  defp side_range(%{kind: :decision} = box, side) do
    {x, y} = tip(box, side)
    if side in [:top, :bottom], do: {x, x}, else: {y, y}
  end

  defp side_range(box, side) when side in [:top, :bottom], do: {box.x + 14, box.x + box.w - 14}
  defp side_range(box, _side), do: {box.y + 10, box.y + box.h - 10}

  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)

  defp along(side, box) when side in [:top, :bottom], do: box.x + box.w / 2
  defp along(_side, box), do: box.y + box.h / 2

  # Pontos distribuídos no lado, sem encostar nos cantos arredondados.
  # O losango só encosta na caixa no meio de cada lado: toda seta entra e sai
  # pela ponta.
  defp port_point(%{kind: :decision} = box, side, _i, _n), do: tip(box, side)

  defp port_point(box, side, i, n) do
    t = (i + 1) / (n + 1)

    case side do
      :top -> {r(box.x + 14 + (box.w - 28) * t), r(box.y)}
      :bottom -> {r(box.x + 14 + (box.w - 28) * t), r(box.y + box.h)}
      :left -> {r(box.x), r(box.y + 10 + (box.h - 20) * t)}
      :right -> {r(box.x + box.w), r(box.y + 10 + (box.h - 20) * t)}
    end
  end

  defp tip(box, :top), do: {r(box.x + box.w / 2), r(box.y)}
  defp tip(box, :bottom), do: {r(box.x + box.w / 2), r(box.y + box.h)}
  defp tip(box, :left), do: {r(box.x), r(box.y + box.h / 2)}
  defp tip(box, :right), do: {r(box.x + box.w), r(box.y + box.h / 2)}

  defp stub({x, y}, :top), do: {x, y - @stub}
  defp stub({x, y}, :bottom), do: {x, y + @stub}
  defp stub({x, y}, :left), do: {x - @stub, y}
  defp stub({x, y}, :right), do: {x + @stub, y}

  # ── grade ─────────────────────────────────────────────────────────────────

  defp grid(obstacles, ports, boxes) do
    stubs = Enum.flat_map(Map.values(ports), &[&1.from_stub, &1.to_stub])

    {min_x, min_y, max_x, max_y} = extent(Map.values(boxes))

    xs =
      (Enum.flat_map(obstacles, &[&1.x, &1.x + &1.w]) ++
         Enum.map(stubs, &elem(&1, 0)) ++ [min_x - @margin, max_x + @margin])
      |> with_channels()

    ys =
      (Enum.flat_map(obstacles, &[&1.y, &1.y + &1.h]) ++
         Enum.map(stubs, &elem(&1, 1)) ++ [min_y - @margin, max_y + @margin])
      |> with_channels()

    %{xs: List.to_tuple(xs), ys: List.to_tuple(ys), xi: index(xs), yi: index(ys)}
  end

  # Os vãos largos ganham linhas candidatas — o eixo e faixas paralelas — para
  # que duas rotas no mesmo vão corram lado a lado em vez de uma sobre a outra.
  defp with_channels(values) do
    sorted = values |> Enum.map(&r/1) |> Enum.uniq() |> Enum.sort()

    lanes =
      sorted
      |> Enum.zip(tl(sorted))
      |> Enum.filter(fn {a, b} -> b - a > 36 end)
      |> Enum.flat_map(fn {a, b} ->
        # o eixo do vão e, se couber, faixas paralelas a cada @lane px
        n = max(1, floor((b - a) / @lane) - 1)
        for i <- 1..n, do: r(a + (b - a) * i / (n + 1))
      end)

    (sorted ++ lanes) |> Enum.uniq() |> Enum.sort()
  end

  defp index(values), do: values |> Enum.with_index() |> Map.new()

  defp extent(boxes) do
    {Enum.min(Enum.map(boxes, & &1.x)), Enum.min(Enum.map(boxes, & &1.y)),
     Enum.max(Enum.map(boxes, &(&1.x + &1.w))), Enum.max(Enum.map(boxes, &(&1.y + &1.h)))}
  end

  # ── A* ────────────────────────────────────────────────────────────────────

  @dirs [{1, 0}, {-1, 0}, {0, 1}, {0, -1}]

  defp astar(grid, obstacles, from, to, used, foreign) do
    with {:ok, start} <- cell(grid, from),
         {:ok, goal} <- cell(grid, to) do
      h = fn c -> manhattan(point(grid, c), to) end
      open = :gb_sets.singleton({h.(start), 0, {start, nil}})
      search(grid, obstacles, goal, open, %{{start, nil} => 0.0}, %{}, used, foreign, h, 1)
    else
      _ -> nil
    end
  end

  defp search(grid, obstacles, goal, open, costs, came, used, foreign, h, counter) do
    if :gb_sets.is_empty(open) do
      nil
    else
      {{_f, _n, {c, dir} = state}, open} = :gb_sets.take_smallest(open)
      g = Map.fetch!(costs, state)

      if c == goal do
        rebuild(grid, came, state, [])
      else
        {open, costs, came, counter} =
          Enum.reduce(@dirs, {open, costs, came, counter}, fn d, acc ->
            expand(grid, obstacles, used, foreign, h, state, c, dir, g, d, acc)
          end)

        search(grid, obstacles, goal, open, costs, came, used, foreign, h, counter)
      end
    end
  end

  defp expand(
         grid,
         obstacles,
         used,
         foreign,
         h,
         state,
         {cx, cy},
         dir,
         g,
         {dx, dy} = d,
         {open, costs, came, counter} = acc
       ) do
    next = {cx + dx, cy + dy}

    cond do
      dir != nil and d == opposite(dir) ->
        acc

      not in_grid?(grid, next) ->
        acc

      true ->
        a = point(grid, {cx, cy})
        b = point(grid, next)

        if blocked?(a, b, obstacles) do
          acc
        else
          step =
            g + dist(a, b) + turn(dir, d) + crossing(used, a, d) + overlap(used, a, b) +
              inside_foreign(foreign, a, b)

          key = {next, d}

          if step < Map.get(costs, key, :infinity) do
            {:gb_sets.add({step + h.(next), counter, key}, open), Map.put(costs, key, step),
             Map.put(came, key, state), counter + 1}
          else
            acc
          end
        end
    end
  end

  defp rebuild(grid, came, {c, _dir} = state, acc) do
    acc = [point(grid, c) | acc]

    case Map.get(came, state) do
      nil -> acc
      prev -> rebuild(grid, came, prev, acc)
    end
  end

  defp opposite({dx, dy}), do: {-dx, -dy}
  defp turn(nil, _d), do: 0.0
  defp turn(d, d), do: 0.0
  defp turn(_, _), do: @bend_cost

  defp cell(grid, {x, y}) do
    case {grid.xi[r(x)], grid.yi[r(y)]} do
      {xi, yi} when is_integer(xi) and is_integer(yi) -> {:ok, {xi, yi}}
      _ -> :error
    end
  end

  defp in_grid?(grid, {xi, yi}),
    do: xi >= 0 and yi >= 0 and xi < tuple_size(grid.xs) and yi < tuple_size(grid.ys)

  defp point(grid, {xi, yi}), do: {elem(grid.xs, xi), elem(grid.ys, yi)}

  # Segmento entre linhas vizinhas da grade: bloqueado se o meio dele cai
  # dentro de um obstáculo (as bordas dos obstáculos são linhas da grade).
  defp blocked?({ax, ay}, {bx, by}, obstacles) do
    m = {(ax + bx) / 2, (ay + by) / 2}
    Enum.any?(obstacles, &strictly_inside?(m, &1))
  end

  # Cruzar uma rota já traçada num ponto da grade custa caro; correr em cima
  # dela custa por pixel.
  defp crossing(used, a, {dx, _dy}) do
    orientation = if dx != 0, do: :h, else: :v
    other = if orientation == :h, do: :v, else: :h
    if MapSet.member?(Map.get(used.points, a, MapSet.new()), other), do: @cross_cost, else: 0.0
  end

  defp overlap(used, a, b) do
    if Map.has_key?(used.segments, seg_key(a, b)), do: dist(a, b) * @overlap_cost, else: 0.0
  end

  defp inside_foreign([], _a, _b), do: 0.0

  defp inside_foreign(groups, {ax, ay} = a, {bx, by} = b) do
    m = {(ax + bx) / 2, (ay + by) / 2}
    if Enum.any?(groups, &strictly_inside?(m, &1)), do: dist(a, b) * @group_cost, else: 0.0
  end

  # Marca cada passo da grade por onde a rota passou: o ponto (com a direção)
  # para cobrar cruzamento, o trecho para cobrar sobreposição.
  defp mark(used, grid, points) do
    points
    |> Enum.zip(tl(points))
    |> Enum.flat_map(&grid_steps(grid, &1))
    |> Enum.reduce(used, fn {a, b, orientation}, u ->
      pts =
        Enum.reduce([a, b], u.points, fn p, acc ->
          Map.update(acc, p, MapSet.new([orientation]), &MapSet.put(&1, orientation))
        end)

      %{u | points: pts, segments: Map.put(u.segments, seg_key(a, b), true)}
    end)
  end

  # Um trecho reto quebrado nos passos da grade que ele percorre. As pontas
  # (portas) podem não estar na grade; ficam de fora, e não fazem falta.
  defp grid_steps(grid, {{ax, ay}, {bx, by}}) do
    {lines, fixed, orientation, lo, hi} =
      if ay == by,
        do: {grid.xs, ay, :h, min(ax, bx), max(ax, bx)},
        else: {grid.ys, ax, :v, min(ay, by), max(ay, by)}

    stops = lines |> Tuple.to_list() |> Enum.filter(&(&1 >= lo and &1 <= hi))

    stops
    |> Enum.zip(Enum.drop(stops, 1))
    |> Enum.map(fn {c, d} ->
      if orientation == :h,
        do: {{c, fixed}, {d, fixed}, :h},
        else: {{fixed, c}, {fixed, d}, :v}
    end)
  end

  defp seg_key(a, b), do: if(a <= b, do: {a, b}, else: {b, a})

  defp foreign_groups(groups, group_of, edge) do
    mine = [group_of[edge.from], group_of[edge.to]]

    groups
    |> Enum.reject(&(&1.label in mine))
    |> Enum.map(&inflate(&1, -4))
  end

  # Um losango tem uma ponta por lado. Quando duas respostas (sim / não)
  # sairiam pela mesma ponta, a que vai mais reto fica nela e as outras vão
  # para as pontas de lado, conforme a posição do destino, como num fluxograma.
  defp spread_decision_exits(sides, edges, boxes) do
    edges
    |> Enum.filter(&match?(%{kind: :decision}, boxes[&1.from]))
    |> Enum.group_by(&{&1.from, elem(sides[&1.id], 0)})
    |> Enum.reduce(sides, fn
      {_key, [_single]}, acc ->
        acc

      {{from, side}, group}, acc ->
        a = boxes[from]
        [_straight | others] = Enum.sort_by(group, &{off_axis(a, boxes[&1.to], side), &1.id})

        others
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {e, i}, acc2 ->
          {_out, in_side} = acc2[e.id]
          Map.put(acc2, e.id, {side_exit(a, boxes[e.to], side, i), in_side})
        end)
    end)
  end

  # Quanto o destino foge do eixo da ponta: o mais alinhado fica com ela.
  defp off_axis(a, b, side) when side in [:left, :right],
    do: abs(b.y + b.h / 2 - (a.y + a.h / 2))

  defp off_axis(a, b, _side), do: abs(b.x + b.w / 2 - (a.x + a.w / 2))

  # Ponta lateral para o destino; empatado, alterna para não somar duas setas.
  defp side_exit(a, b, side, i) when side in [:left, :right] do
    dy = b.y + b.h / 2 - (a.y + a.h / 2)

    cond do
      dy < 0 -> :top
      dy > 0 -> :bottom
      rem(i, 2) == 0 -> :top
      true -> :bottom
    end
  end

  defp side_exit(a, b, _side, i) do
    dx = b.x + b.w / 2 - (a.x + a.w / 2)

    cond do
      dx < 0 -> :left
      dx > 0 -> :right
      rem(i, 2) == 0 -> :right
      true -> :left
    end
  end

  defp sides(a, b, :horizontal) do
    cond do
      b.x >= a.x + a.w -> {:right, :left}
      b.x + b.w <= a.x -> {:left, :right}
      b.y >= a.y + a.h / 2 -> {:bottom, :top}
      true -> {:top, :bottom}
    end
  end

  defp sides(a, b, _vertical) do
    cond do
      b.y >= a.y + a.h -> {:bottom, :top}
      b.y + b.h <= a.y -> {:top, :bottom}
      b.x >= a.x + a.w / 2 -> {:right, :left}
      true -> {:left, :right}
    end
  end

  # ── saída ─────────────────────────────────────────────────────────────────

  defp geometry(points, label, boxes) do
    {x1, y1} = hd(points)
    {x2, y2} = List.last(points)
    {lx, ly, anchor} = label_spot(points, label, Map.values(boxes))

    %{
      path: rounded(points),
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      label_x: lx,
      label_y: ly,
      label_anchor: anchor
    }
  end

  # O rótulo vai no meio do trecho mais longo, que é onde costuma haver espaço.
  # Se ali ele cobriria uma caixa, tenta o outro lado do trecho e depois os
  # trechos mais curtos; sem lugar livre, fica no mais longo.
  defp label_spot(points, label, boxes) do
    candidates =
      points
      |> Enum.zip(tl(points))
      |> Enum.sort_by(fn {a, b} -> -dist(a, b) end)
      |> Enum.flat_map(fn {{ax, ay}, {bx, by}} ->
        if ay == by,
          do: [{r((ax + bx) / 2), ay, "middle"}],
          else: [{ax + 8, r((ay + by) / 2), "start"}, {ax - 8, r((ay + by) / 2), "end"}]
      end)

    case label do
      nil -> hd(candidates)
      text -> Enum.find(candidates, hd(candidates), &(not covers_box?(&1, text, boxes)))
    end
  end

  # A mesma caixa de fundo que o renderer desenha atrás do rótulo.
  defp covers_box?({x, y, anchor}, text, boxes) do
    w = Scene.text_width(text, 12) + 12

    left =
      case anchor do
        "middle" -> x - w / 2
        "end" -> x - w + 6
        _ -> x - 6
      end

    tag = %{x: left, y: y - 13, w: w, h: 18}
    Enum.any?(boxes, &overlap?(tag, &1))
  end

  defp overlap?(a, b),
    do: a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h

  # Tira pontos repetidos e colineares: sobram só as quinas.
  defp simplify(points) do
    points
    |> Enum.dedup()
    |> Enum.reduce([], fn
      p, [b, a | rest] = acc -> if collinear?(a, b, p), do: [p, a | rest], else: [p | acc]
      p, acc -> [p | acc]
    end)
    |> Enum.reverse()
  end

  defp collinear?({ax, ay}, {bx, by}, {cx, cy}),
    do: (ax == bx and bx == cx) or (ay == by and by == cy)

  @doc "Polilinha com cantos arredondados — o mesmo desenho das rotas automáticas."
  @spec rounded([{number(), number()}]) :: String.t()
  def rounded([a]), do: "M #{pt(a)}"
  def rounded([a, b]), do: "M #{pt(a)} L #{pt(b)}"

  def rounded(points) do
    middle =
      points
      |> Enum.slice(1..-2//1)
      |> Enum.with_index(1)
      |> Enum.map_join(" ", fn {corner, i} ->
        prev = Enum.at(points, i - 1)
        next = Enum.at(points, i + 1)
        rr = min(@corner, min(dist(prev, corner), dist(corner, next)) / 2)
        "L #{pt(towards(corner, prev, rr))} Q #{pt(corner)} #{pt(towards(corner, next, rr))}"
      end)

    "M #{pt(hd(points))} #{middle} L #{pt(List.last(points))}"
  end

  defp towards({x, y}, {tx, ty}, rr) do
    d = dist({x, y}, {tx, ty})
    if d == 0, do: {x, y}, else: {x + (tx - x) / d * rr, y + (ty - y) / d * rr}
  end

  defp pt({x, y}), do: "#{r(x)} #{r(y)}"

  # ── geometria ─────────────────────────────────────────────────────────────

  defp inflate(%{x: x, y: y, w: w, h: h}, by),
    do: %{x: x - by, y: y - by, w: w + 2 * by, h: h + 2 * by}

  # O chip do título de um grupo (canto de cima à esquerda) é zona proibida:
  # seta não passa por cima do nome do grupo.
  # Baixo o bastante para não engolir a saída de uma seta que entra pelo topo
  # de um membro da primeira linha do grupo.
  defp chip_obstacle(group) do
    w = Scene.char_units(group.label) * 7.2 + 30
    %{x: group.x, y: group.y, w: w, h: 22}
  end

  defp step({ax, ay} = a, {bx, by} = b) do
    mid = r((ay + by) / 2)
    [a, {ax, mid}, {bx, mid}, b]
  end

  defp strictly_inside?({px, py}, o),
    do: px > o.x and px < o.x + o.w and py > o.y and py < o.y + o.h

  defp manhattan({ax, ay}, {bx, by}), do: abs(ax - bx) + abs(ay - by)
  defp dist({ax, ay}, {bx, by}), do: :math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))
  defp r(n), do: round(n)
end
