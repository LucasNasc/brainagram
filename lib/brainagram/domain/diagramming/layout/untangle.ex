defmodule Brainagram.Domain.Diagramming.Layout.Untangle do
  @moduledoc """
  "Organizar setas": procura a arrumação dos componentes em que as setas menos
  se cruzam e a grava no bloco `layout` do texto.

  Diagramas que vêm do Mermaid ou do PlantUML costumam ter as setas
  entrelaçadas: a ordem das declarações foi pensada para ler, não para
  desenhar. O layout automático parte dessa ordem e melhora localmente; aqui a
  busca é global e medida no desenho.

  ## O que pode mudar

  A arrumação é a do automático — camadas de cima para baixo, cada grupo numa
  faixa vertical própria — e a busca mexe em três coisas:

    * a ordem das faixas (grupos e nós soltos) da esquerda para a direita;
    * a ordem dos nós dentro de cada faixa, camada a camada;
    * a camada de um nó, desde que toda seta continue descendo.

  Depois da ordem, as caixas são alinhadas às vizinhas — a seta que liga duas
  caixas alinhadas é reta, sem quina.

  ## Como mede

  A busca avalia milhares de arrumações com uma medida rápida (setas como
  segmentos retos: cruzamentos, caixas atravessadas, grupos atravessados,
  comprimento). As melhores são então desenhadas de verdade — roteadas pelo
  `Router` e medidas por `Layout.Quality` — e só vence uma que seja melhor que
  o desenho atual. Sem melhora, o texto não muda.

  O resultado é determinístico: o mesmo texto sempre dá a mesma arrumação.
  """

  alias Brainagram.Domain.Diagramming.Dsl.{Ast, Edge, Parser}
  alias Brainagram.Domain.Diagramming.Layout
  alias Brainagram.Domain.Diagramming.Layout.{Hints, Quality}

  @top 92
  @margin 56
  @node_gap 40
  @layer_gap 128
  @column_gap 72
  @group_pad 22
  @align_passes 6

  @max_evaluations 6_000
  @finalists 12
  @area_weight 0.0003

  @type result :: %{
          source: String.t(),
          before: Quality.t(),
          after: Quality.t(),
          improved: boolean()
        }

  @doc """
  Organiza `source` (que precisa compilar e ser de arquitetura). Devolve o
  texto novo e as métricas de antes e depois; sem melhora, o próprio texto.
  """
  @spec run(String.t()) :: {:ok, result()} | {:error, term()}
  def run(source) when is_binary(source) do
    with {:ok, ast} <- parse(source),
         :ok <- architecture(ast) do
      before = ast |> Layout.build() |> Quality.measure()
      untangle(source, ast, before)
    end
  end

  defp untangle(source, %Ast{nodes: nodes}, before) when length(nodes) < 2,
    do: {:ok, unchanged(source, before)}

  defp untangle(source, ast, before) do
    ctx = context(ast)
    starts = starts(ctx)
    per_start = div(@max_evaluations, length(starts))

    # cada partida tem o seu orçamento: em paralelo e ainda determinístico
    finalists =
      starts
      |> concurrently(&climb(ctx, &1, per_start))
      |> Enum.concat()
      |> Enum.uniq_by(fn {_score, arrangement} -> arrangement end)
      |> Enum.sort_by(fn {score, _} -> score end)
      |> Enum.take(@finalists)

    best =
      finalists
      |> concurrently(fn {_proxy, arrangement} -> render(source, ctx, arrangement) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.min_by(fn {score, _source, _metrics} -> score end, fn -> nil end)

    case best do
      {score, edited, metrics} ->
        if score < Quality.score(before) - 0.5,
          do: {:ok, %{source: edited, before: before, after: metrics, improved: true}},
          else: {:ok, unchanged(source, before)}

      nil ->
        {:ok, unchanged(source, before)}
    end
  end

  defp concurrently(items, fun) do
    items
    |> Task.async_stream(fun, timeout: :infinity, ordered: true)
    |> Enum.map(fn {:ok, value} -> value end)
  end

  defp unchanged(source, before),
    do: %{source: source, before: before, after: before, improved: false}

  defp architecture(%Ast{kind: :architecture}), do: :ok
  defp architecture(_ast), do: {:error, :not_architecture}

  # ── contexto: o que não muda durante a busca ──────────────────────────────

  defp context(ast) do
    # o automático puro (sem fixações) dá as camadas e a ordem de partida
    auto = Layout.build(%{ast | pins: []})

    ys = auto.nodes |> Enum.map(& &1.y) |> Enum.uniq() |> Enum.sort()
    layer_of_y = ys |> Enum.with_index() |> Map.new()

    edges =
      ast.steps
      |> Enum.flat_map(& &1.items)
      |> Enum.filter(&match?(%Edge{}, &1))
      |> Enum.reject(&(&1.from == &1.to))
      |> Enum.map(&%{id: &1.id, from: &1.from, to: &1.to})

    neighbours =
      Enum.reduce(edges, %{}, fn e, acc ->
        acc
        |> Map.update(e.from, [e.to], &[e.to | &1])
        |> Map.update(e.to, [e.from], &[e.from | &1])
      end)

    %{
      auto: auto,
      sizes: Map.new(auto.nodes, &{&1.id, %{w: &1.w, h: &1.h}}),
      group_of: Map.new(auto.nodes, &{&1.id, &1.group}),
      layer: Map.new(auto.nodes, &{&1.id, layer_of_y[&1.y]}),
      x: Map.new(auto.nodes, &{&1.id, &1.x}),
      edges: edges,
      neighbours: neighbours,
      preds: Enum.group_by(edges, & &1.to, & &1.from),
      succs: Enum.group_by(edges, & &1.from, & &1.to)
    }
  end

  # ── a arrumação ───────────────────────────────────────────────────────────

  # %{bands: [rótulo | {:loose, id}], rows: %{{rótulo, camada} => [ids]}, layer: %{id => camada}}
  #
  # Nó solto é uma faixa própria: pode ir para qualquer lugar entre os grupos.
  # Faixas soltas vizinhas dividem a mesma coluna na hora de desenhar.
  defp starts(ctx) do
    nodes = Enum.sort_by(ctx.auto.nodes, &{ctx.layer[&1.id], &1.x})

    rows =
      nodes
      |> Enum.filter(& &1.group)
      |> Enum.group_by(&{&1.group, ctx.layer[&1.id]}, & &1.id)

    bands =
      nodes
      |> Enum.sort_by(& &1.x)
      |> Enum.map(fn n -> n.group || {:loose, n.id} end)
      |> Enum.uniq()

    initial = %{bands: bands, rows: rows, layer: ctx.layer}
    [initial, %{initial | bands: Enum.reverse(bands)}]
  end

  defp climb(ctx, start, evaluations) do
    budget = :counters.new(1, [])
    :counters.put(budget, 1, evaluations)
    score = proxy(ctx, start)
    do_climb(ctx, {score, start}, budget, [{score, start}])
  end

  # Subida de encosta com a primeira melhora: cada passada tenta todos os
  # vizinhos da arrumação atual; guarda o caminho para a final.
  defp do_climb(ctx, {score, arrangement} = current, budget, seen) do
    next =
      arrangement
      |> neighbours(ctx)
      |> Enum.reduce_while(nil, fn candidate, nil ->
        if :counters.get(budget, 1) <= 0 do
          {:halt, nil}
        else
          :counters.sub(budget, 1, 1)
          s = proxy(ctx, candidate)
          if s < score - 1.0e-6, do: {:halt, {s, candidate}}, else: {:cont, nil}
        end
      end)

    case next do
      nil -> [current | seen]
      better -> do_climb(ctx, better, budget, [better | seen])
    end
  end

  defp neighbours(arrangement, ctx) do
    band_moves(arrangement) ++ row_moves(arrangement) ++ layer_moves(arrangement, ctx)
  end

  defp band_moves(%{bands: bands} = a) do
    for band <- bands,
        pos <- 0..(length(bands) - 1),
        moved = List.insert_at(List.delete(bands, band), pos, band),
        moved != bands,
        uniq: true,
        do: %{a | bands: moved}
  end

  defp row_moves(%{rows: rows} = a) do
    for {key, ids} <- Enum.sort(rows),
        length(ids) > 1,
        id <- ids,
        pos <- 0..(length(ids) - 1),
        moved = List.insert_at(List.delete(ids, id), pos, id),
        moved != ids,
        uniq: true,
        do: %{a | rows: Map.put(rows, key, moved)}
  end

  # Levar um nó para outra camada, sem nenhuma seta passar a subir: entre a
  # camada mais baixa dos que apontam para ele e a mais alta dos que ele aponta.
  defp layer_moves(%{layer: layer} = a, ctx) do
    deepest = layer |> Map.values() |> Enum.max()

    for {id, l} <- Enum.sort(layer),
        low = ctx.preds |> Map.get(id, []) |> Enum.map(&(layer[&1] + 1)) |> Enum.max(fn -> 0 end),
        high =
          ctx.succs
          |> Map.get(id, [])
          |> Enum.map(&(layer[&1] - 1))
          |> Enum.min(fn -> deepest + 1 end),
        target <- low..high//1,
        target != l do
      move_layer(a, ctx, id, l, target)
    end
  end

  defp move_layer(a, ctx, id, from, to) do
    layer = Map.put(a.layer, id, to)

    rows =
      case ctx.group_of[id] do
        nil ->
          a.rows

        group ->
          a.rows
          |> Map.update({group, from}, [], &List.delete(&1, id))
          |> Map.update({group, to}, [id], &(&1 ++ [id]))
          |> Map.reject(fn {_k, ids} -> ids == [] end)
      end

    %{a | layer: layer, rows: rows}
  end

  # ── geometria ─────────────────────────────────────────────────────────────

  @doc false
  def boxes(ctx, %{bands: bands, rows: rows, layer: layer}) do
    # camadas vazias somem: numeração compacta
    used = layer |> Map.values() |> Enum.uniq() |> Enum.sort() |> Enum.with_index() |> Map.new()
    y_of = fn id -> @top + used[layer[id]] * (h_max(ctx) + @layer_gap) end

    columns = columns(bands, rows, layer)

    {boxes, _cursor} =
      Enum.reduce(columns, {%{}, @margin}, fn column, {acc, cursor} ->
        pad = if Enum.any?(column, &is_binary/1), do: @group_pad, else: 0

        column_rows =
          used
          |> Map.keys()
          |> Map.new(fn l ->
            ids =
              Enum.flat_map(column, fn
                {:loose, id} -> if layer[id] == l, do: [id], else: []
                label -> Map.get(rows, {label, l}, [])
              end)

            {l, ids}
          end)
          |> Map.reject(fn {_l, ids} -> ids == [] end)

        width =
          column_rows |> Map.values() |> Enum.map(&row_width(ctx, &1)) |> Enum.max(fn -> 0 end)

        left = cursor + pad

        placed =
          Enum.reduce(column_rows, acc, fn {_l, ids}, acc2 ->
            start = left + (width - row_width(ctx, ids)) / 2

            ids
            |> Enum.map_reduce(start, fn id, x ->
              s = ctx.sizes[id]
              {{id, box(id, x, y_of.(id), s, ctx, left, left + width)}, x + s.w + @node_gap}
            end)
            |> elem(0)
            |> Map.new()
            |> then(&Map.merge(acc2, &1))
          end)

        {placed, left + width + pad + @column_gap}
      end)

    align(boxes, ctx, @align_passes)
  end

  defp h_max(ctx), do: ctx.sizes |> Map.values() |> Enum.map(& &1.h) |> Enum.max()

  defp box(id, x, y, s, ctx, min_x, max_x) do
    %{id: id, x: x, y: y, w: s.w, h: s.h, group: ctx.group_of[id], min_x: min_x, max_x: max_x}
  end

  # Faixas vizinhas dividem uma coluna quando não disputam camada: um grupo
  # que ocupa as camadas 0–1 empilha sobre outro que ocupa 2–4, e a seta entre
  # eles desce reta. Nós soltos vizinhos sempre dividem (lado a lado, se
  # caírem na mesma camada).
  defp columns(bands, rows, layer) do
    range = fn
      {:loose, id} ->
        MapSet.new([layer[id]])

      label ->
        # o intervalo inteiro: a caixa do grupo cobre as camadas do meio também
        case for({{^label, l}, [_ | _]} <- rows, do: l) do
          [] -> MapSet.new()
          ls -> MapSet.new(Enum.min(ls)..Enum.max(ls))
        end
    end

    bands
    |> Enum.reduce([], fn band, columns ->
      mine = range.(band)

      case columns do
        [column | rest] ->
          if Enum.all?(column, &shares?(band, &1, mine, range)),
            do: [[band | column] | rest],
            else: [[band] | columns]

        [] ->
          [[band]]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(&Enum.reverse/1)
  end

  defp shares?({:loose, _}, {:loose, _}, _mine, _range), do: true
  defp shares?(_band, other, mine, range), do: MapSet.disjoint?(mine, range.(other))

  defp row_width(_ctx, []), do: 0

  defp row_width(ctx, ids),
    do: Enum.sum(Enum.map(ids, &ctx.sizes[&1].w)) + @node_gap * (length(ids) - 1)

  # Cada caixa desliza, dentro da sua coluna e sem trocar de ordem, em direção
  # ao centro médio das vizinhas: seta entre caixas alinhadas sai reta.
  defp align(boxes, _ctx, 0), do: boxes

  defp align(boxes, ctx, passes) do
    rows =
      boxes
      |> Map.values()
      |> Enum.group_by(&{&1.min_x, &1.y})
      |> Map.values()

    aligned =
      Enum.reduce(rows, boxes, fn row, acc ->
        row = Enum.sort_by(row, & &1.x)

        wanted =
          Enum.map(row, fn b ->
            case Map.get(ctx.neighbours, b.id, [])
                 |> Enum.map(&acc[&1])
                 |> Enum.reject(&is_nil/1) do
              [] -> b.x
              ns -> Enum.sum(Enum.map(ns, &(&1.x + &1.w / 2))) / length(ns) - b.w / 2
            end
          end)

        row
        |> Enum.zip(wanted)
        |> pack()
        |> Enum.reduce(acc, fn b, acc2 -> Map.put(acc2, b.id, b) end)
      end)

    align(aligned, ctx, passes - 1)
  end

  # Posições desejadas → posições válidas: sem sobreposição, na ordem, dentro
  # da coluna. Ida empurra para a direita, volta puxa para dentro.
  defp pack(pairs) do
    {forward, _} =
      Enum.map_reduce(pairs, nil, fn {b, want}, prev_right ->
        x = max(want, b.min_x)
        x = if prev_right, do: max(x, prev_right + @node_gap), else: x
        {%{b | x: x}, x + b.w}
      end)

    {backward, _} =
      forward
      |> Enum.reverse()
      |> Enum.map_reduce(nil, fn b, next_left ->
        x = min(b.x, b.max_x - b.w)
        x = if next_left, do: min(x, next_left - @node_gap - b.w), else: x
        {%{b | x: x}, x}
      end)

    Enum.map(backward, fn b -> %{b | x: round(b.x)} end)
  end

  # ── medida rápida ─────────────────────────────────────────────────────────

  @doc false
  def proxy(ctx, arrangement) do
    boxes = boxes(ctx, arrangement)
    groups = group_boxes(boxes)

    segments =
      Enum.map(ctx.edges, fn e -> {e, segment(boxes[e.from], boxes[e.to])} end)

    crossings =
      for {{e1, s1}, i} <- Enum.with_index(segments),
          {{e2, s2}, j} <- Enum.with_index(segments),
          i < j,
          MapSet.disjoint?(MapSet.new([e1.from, e1.to]), MapSet.new([e2.from, e2.to])),
          crosses?(s1, s2),
          reduce: 0,
          do: (acc -> acc + 1)

    node_hits =
      for {e, s} <- segments,
          {id, b} <- boxes,
          id not in [e.from, e.to],
          hits?(s, inflate(b, 8)),
          reduce: 0,
          do: (acc -> acc + 1)

    group_hits =
      for {e, s} <- segments,
          {label, g} <- groups,
          label not in [ctx.group_of[e.from], ctx.group_of[e.to]],
          hits?(s, g),
          reduce: 0,
          do: (acc -> acc + 1)

    {length, slant} =
      Enum.reduce(segments, {0.0, 0.0}, fn {_e, {{x1, y1}, {x2, y2}}}, {l, sl} ->
        {l + abs(x2 - x1) + abs(y2 - y1), sl + if(x1 == x2 or y1 == y2, do: 0, else: 1)}
      end)

    crossings * 100 + node_hits * 250 + group_hits * 40 + slant * 4 + length * 0.05 +
      stretch(arrangement) * 30 + area(boxes) * @area_weight
  end

  # Espaço vazio também atrapalha: o olho percorre mais para seguir uma seta.
  defp area(boxes) do
    bs = Map.values(boxes)
    w = Enum.max(Enum.map(bs, &(&1.x + &1.w))) - Enum.min(Enum.map(bs, & &1.x))
    h = Enum.max(Enum.map(bs, &(&1.y + &1.h))) - Enum.min(Enum.map(bs, & &1.y))
    w * h
  end

  # Camada vazia dentro de um grupo: a caixa do grupo estica à toa e vira
  # obstáculo para as setas dos outros.
  defp stretch(%{rows: rows}) do
    rows
    |> Enum.group_by(fn {{label, _l}, _ids} -> label end, fn {{_label, l}, _ids} -> l end)
    |> Enum.map(fn {_label, ls} -> Enum.max(ls) - Enum.min(ls) + 1 - length(ls) end)
    |> Enum.sum()
  end

  defp segment(a, b) do
    cond do
      b.y >= a.y + a.h -> {{a.x + a.w / 2, a.y + a.h}, {b.x + b.w / 2, b.y}}
      b.y + b.h <= a.y -> {{a.x + a.w / 2, a.y}, {b.x + b.w / 2, b.y + b.h}}
      b.x >= a.x -> {{a.x + a.w, a.y + a.h / 2}, {b.x, b.y + b.h / 2}}
      true -> {{a.x, a.y + a.h / 2}, {b.x + b.w, b.y + b.h / 2}}
    end
  end

  defp group_boxes(boxes) do
    boxes
    |> Map.values()
    |> Enum.filter(& &1.group)
    |> Enum.group_by(& &1.group)
    |> Map.new(fn {label, members} ->
      x = Enum.min(Enum.map(members, & &1.x)) - @group_pad
      y = Enum.min(Enum.map(members, & &1.y)) - @group_pad - 20
      right = Enum.max(Enum.map(members, &(&1.x + &1.w))) + @group_pad
      bottom = Enum.max(Enum.map(members, &(&1.y + &1.h))) + @group_pad
      {label, %{x: x + 4, y: y + 4, w: right - x - 8, h: bottom - y - 8}}
    end)
  end

  defp inflate(b, by), do: %{x: b.x - by, y: b.y - by, w: b.w + 2 * by, h: b.h + 2 * by}

  defp crosses?({p1, p2}, {p3, p4}) do
    d1 = orient(p3, p4, p1)
    d2 = orient(p3, p4, p2)
    d3 = orient(p1, p2, p3)
    d4 = orient(p1, p2, p4)
    d1 * d2 < 0 and d3 * d4 < 0
  end

  defp orient({ax, ay}, {bx, by}, {cx, cy}), do: (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)

  # Liang–Barsky: o segmento entra no retângulo?
  defp hits?({{x1, y1}, {x2, y2}}, r) do
    dx = x2 - x1
    dy = y2 - y1

    [{-dx, x1 - r.x}, {dx, r.x + r.w - x1}, {-dy, y1 - r.y}, {dy, r.y + r.h - y1}]
    |> Enum.reduce_while({0.0, 1.0}, fn
      {p, q}, acc when p == 0 ->
        if q < 0, do: {:halt, nil}, else: {:cont, acc}

      {p, q}, {t0, t1} ->
        t = q / p
        {t0, t1} = if p < 0, do: {max(t0, t), t1}, else: {t0, min(t1, t)}
        if t0 > t1, do: {:halt, nil}, else: {:cont, {t0, t1}}
    end)
    |> case do
      nil -> false
      {t0, t1} -> t1 - t0 > 1.0e-6
    end
  end

  # ── desenho de verdade ────────────────────────────────────────────────────

  # Grava a arrumação como fixações e mede o que o editor vai mostrar.
  defp render(source, ctx, arrangement) do
    edited = write_pins(source, boxes(ctx, arrangement))

    with {:ok, ast} <- parse(edited) do
      metrics = ast |> Layout.build() |> Quality.measure()
      {Quality.score(metrics), edited, metrics}
    else
      _ -> nil
    end
  end

  # Um bloco `layout` novo, com uma linha por nó na ordem de declaração.
  defp write_pins(source, boxes) do
    cleared = Hints.clear(source)
    {:ok, ast} = Parser.parse(cleared)

    ast.nodes
    |> Enum.filter(&boxes[&1.id])
    |> Enum.reduce(cleared, fn node, acc ->
      b = boxes[node.id]
      Hints.pin(acc, node.id, {round(b.x), round(b.y)})
    end)
  end

  defp parse(source) do
    case Parser.parse(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, errors} -> {:error, {:syntax, errors}}
    end
  end
end
