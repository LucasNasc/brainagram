defmodule Brainagram.Domain.Diagramming.Layout.Sequence do
  @moduledoc """
  Layout de diagrama de sequência.

  Estratégia: duas passadas independentes.

    1. **Horizontal** — cada participante vira uma "raia". A largura base vem do
       rótulo; depois as raias são empurradas para a direita até que o rótulo de
       cada mensagem caiba entre origem e destino.
    2. **Vertical** — percorre a timeline. Cada `step` ganha uma faixa de
       cabeçalho e cada item ganha uma linha.

  As barras de ativação saem de uma pilha por participante: `->` empilha,
  `-->` desempilha. É o que dá a leitura de "quem está executando agora".

  ## Payload

  Mensagem com `payload` ganha, logo abaixo da seta, um **chip** minimizado
  (o começo do conteúdo e quantas linhas tem) com uma ponta apontando para
  ela. O layout reserva só o espaço do chip: o diagrama fica compacto.

  O balão inteiro (`payload.x/y/w/h`, mesmo topo do chip) abre por cima do
  que vem abaixo — na animação, enquanto a mensagem é a da vez, ou quando a
  pessoa clica no chip. É o cliente que decide quando; aqui só se calcula a
  geometria dos dois e `hold`, a pausa de leitura que a timeline dá depois de
  uma mensagem com payload. Balão grande é aparado (16 linhas, 64
  caracteres); o texto inteiro vai junto, para a dica e a edição.

  ## Posições fixadas (`Hints`)

  Numa sequência só o eixo horizontal é livre: os cabeçalhos ficam todos na
  mesma altura e a ordem vertical é a da timeline. Um participante fixado fica
  exatamente no `x` pedido (o `y` é ignorado); os demais mantêm a ordem e são
  empurrados para a direita só o necessário para não sobrepor.
  """

  alias Brainagram.Domain.Diagramming.Dsl.{Ast, Edge, Note}
  alias Brainagram.Domain.Diagramming.Layout.Hints
  alias Brainagram.Domain.Diagramming.Scene

  @gutter 136
  @margin_right 56
  @top 28
  @header_h 54
  @head_gap 30
  @lane_gap 40
  @min_lane_w 128
  @step_band_h 46
  @row_h 62
  @self_row_h 88
  @note_row_h 66
  @bottom_pad 52
  @payload_max_lines 16
  @payload_max_chars 64
  @chip_h 20
  @chip_max_label 28
  @payload_char_w 6.7
  @payload_line_h 15
  @payload_pad_x 10
  @payload_pad_y 8
  @payload_gap 12
  @payload_after 18
  @label_size 12.5
  @node_label_size 13.5

  @spec build(Ast.t(), Hints.t()) :: Scene.t()
  def build(%Ast{} = ast, %Hints{} = hints \\ %Hints{}) do
    lanes = ast |> place_lanes() |> apply_pins(hints.pinned)
    {rows, body_h} = place_rows(ast, lanes)

    edges = Enum.filter(rows, &(&1.type == :edge))
    notes = Enum.filter(rows, &(&1.type == :note))
    activations = activations(edges, body_h)

    # um balão largo na última raia também precisa caber
    payload_right =
      edges
      |> Enum.flat_map(fn e -> if e[:payload], do: [e.payload.x + e.payload.w + 24], else: [] end)
      |> Enum.max(fn -> 0 end)

    width =
      lanes
      |> Enum.map(& &1.right)
      |> Enum.max(&>=/2, fn -> @gutter end)
      |> Kernel.+(@margin_right)
      |> max(payload_right)

    height = body_h + @bottom_pad

    %Scene{
      kind: :sequence,
      title: ast.title,
      width: round(width),
      height: round(height),
      nodes: Enum.map(lanes, &lane_to_node(&1, body_h)),
      groups: groups(ast, lanes),
      edges: Enum.map(edges, &Map.delete(&1, :type)),
      notes: Enum.map(notes, &Map.delete(&1, :type)),
      activations: activations,
      steps: steps(ast, rows)
    }
  end

  # ── passada horizontal ────────────────────────────────────────────────────

  defp place_lanes(ast) do
    lanes =
      ast.nodes
      |> Enum.with_index()
      |> Enum.map(fn {node, i} ->
        w = max(@min_lane_w, Scene.text_width(node.label, @node_label_size) + 44)
        %{index: i, id: node.id, label: node.label, kind: node.kind, group: node.group, w: w}
      end)

    lanes
    |> Enum.map_reduce(@gutter + @lane_gap, fn lane, x ->
      {Map.merge(lane, %{x: x, cx: x + lane.w / 2, right: x + lane.w}), x + lane.w + @lane_gap}
    end)
    |> elem(0)
    |> widen_for_labels(all_edges(ast))
  end

  # Empurra raias para a direita até os rótulos das mensagens caberem.
  defp widen_for_labels(lanes, edges) do
    idx = Map.new(lanes, &{&1.id, &1.index})

    Enum.reduce(edges, lanes, fn edge, acc ->
      with i when not is_nil(i) <- idx[edge.from],
           j when not is_nil(j) <- idx[edge.to] do
        needed = Scene.text_width(edge.label, @label_size) + 42
        {lo, hi} = {min(i, j), max(i, j)}

        cond do
          lo == hi ->
            # auto-chamada: precisa de espaço à direita da própria raia
            shift_from(acc, hi + 1, needed + 70 - gap_after(acc, hi))

          true ->
            current = center(acc, hi) - center(acc, lo)
            shift_from(acc, hi, needed - current)
        end
      else
        _ -> acc
      end
    end)
  end

  defp apply_pins(lanes, pinned) when map_size(pinned) == 0, do: lanes

  defp apply_pins(lanes, pinned) do
    fixed =
      for lane <- lanes, {x, _y} = Map.get(pinned, lane.id, {nil, nil}), x != nil do
        %{lane | x: x, cx: x + lane.w / 2, right: x + lane.w} |> Map.put(:pinned, true)
      end

    fixed_ids = MapSet.new(fixed, & &1.id)

    {free, _cursor} =
      lanes
      |> Enum.reject(&MapSet.member?(fixed_ids, &1.id))
      |> Enum.map_reduce(nil, fn lane, cursor ->
        x = clear_of(max(lane.x, cursor || lane.x), lane.w, fixed)
        {%{lane | x: x, cx: x + lane.w / 2, right: x + lane.w}, x + lane.w + @lane_gap}
      end)

    (free ++ fixed) |> Enum.sort_by(& &1.index)
  end

  defp clear_of(x, w, fixed) do
    case Enum.find(fixed, &(x < &1.right + @lane_gap and &1.x < x + w + @lane_gap)) do
      nil -> x
      other -> clear_of(other.right + @lane_gap, w, fixed)
    end
  end

  defp center(lanes, i), do: Enum.at(lanes, i).cx

  defp gap_after(lanes, i) do
    case Enum.at(lanes, i + 1) do
      nil -> 1_000
      next -> next.x - Enum.at(lanes, i).right
    end
  end

  defp shift_from(lanes, _from, delta) when delta <= 0, do: lanes

  defp shift_from(lanes, from, delta) do
    Enum.map(lanes, fn lane ->
      if lane.index >= from do
        %{lane | x: lane.x + delta, cx: lane.cx + delta, right: lane.right + delta}
      else
        lane
      end
    end)
  end

  # ── passada vertical ──────────────────────────────────────────────────────

  defp place_rows(ast, lanes) do
    by_id = Map.new(lanes, &{&1.id, &1})
    start_y = @top + @header_h + @head_gap

    {rows, y} =
      Enum.flat_map_reduce(ast.steps, start_y, fn step, y ->
        band_y = y
        y = y + @step_band_h

        {items, y} =
          Enum.flat_map_reduce(step.items, y, fn item, y ->
            place_item(item, step, by_id, y)
          end)

        {[%{type: :band, step: step.index, y: band_y} | items], y}
      end)

    {rows, y}
  end

  defp bands(rows), do: Enum.filter(rows, &(&1.type == :band))

  defp place_item(%Edge{} = edge, step, by_id, y) do
    from = by_id[edge.from]
    to = by_id[edge.to]

    cond do
      is_nil(from) or is_nil(to) ->
        {[], y}

      edge.from == edge.to ->
        row_y = y + 20
        row = self_edge(edge, step, from, row_y)
        with_payload(row, edge.payload, y + @self_row_h)

      true ->
        row_y = y + 26
        row = straight_edge(edge, step, from, to, row_y)
        with_payload(row, edge.payload, y + @row_h)
    end
  end

  defp place_item(%Note{} = note, step, by_id, y) do
    targets = note.target_ids |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1)

    if targets == [] do
      {[], y}
    else
      xs = Enum.map(targets, & &1.cx)
      text_w = Scene.text_width(note.text, @label_size) + 32
      left = Enum.min(xs)
      right = Enum.max(xs)

      {x, w} =
        case note.placement do
          :over -> {left - 70, max(text_w, right - left + 140)}
          :left -> {left - text_w - 40, text_w}
          :right -> {right + 40, text_w}
        end

      row = %{
        type: :note,
        id: note.id,
        step: step.index,
        text: note.text,
        x: round(x),
        y: round(y + 8),
        w: round(w),
        h: 44
      }

      {[row], y + @note_row_h}
    end
  end

  defp with_payload(row, nil, next_y), do: {[row], next_y}

  defp with_payload(row, text, next_y) do
    {lines, w, h} = payload_box(text)

    chip = chip(text)

    # onde a ponta encosta na seta; chip e balão começam na mesma altura
    {tip_x, tip_y} =
      if row.self,
        do: {row.x1 + 36, row.y + 41},
        else: {(row.x1 + row.x2) / 2, row.y + 4}

    top = tip_y + @payload_gap - 6

    {x, chip_x} =
      if row.self,
        do: {row.x1 + 20, row.x1 + 20},
        else: {tip_x - w / 2, tip_x - chip.w / 2}

    payload = %{
      text: text,
      lines: lines,
      x: round(max(x, 8)),
      y: round(top),
      w: round(w),
      h: round(h),
      tip_x: round(tip_x),
      tip_y: round(tip_y),
      hold: min(1_200 + 110 * chip.count, 2_600),
      chip: %{
        label: chip.label,
        count: chip.count,
        x: round(max(chip_x, 8)),
        y: round(top),
        w: round(chip.w),
        h: @chip_h
      }
    }

    # só o chip ocupa espaço; o balão aberto flutua por cima
    {[Map.put(row, :payload, payload)], max(next_y, top + @chip_h + @payload_after)}
  end

  # O chip: a primeira linha com conteúdo, curta, e quantas linhas há ao todo
  # (o cliente escreve "· N linhas" no idioma da tela — a largura já conta).
  defp chip(text) do
    lines = String.split(text, "\n")
    count = length(lines)

    # JSON começa com um `{` sozinho, que não diz nada: junta com a linha seguinte
    first =
      case lines |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) do
        [open, next | _] when open in ["{", "[", "("] -> open <> " " <> next
        [line | _] -> line
        [] -> ""
      end

    label =
      if String.length(first) > @chip_max_label or count > 1,
        do: String.slice(first, 0, @chip_max_label - 1) <> "…",
        else: first

    extra = if count > 1, do: 11, else: 0
    w = min(max((Scene.char_units(label) + extra) * @payload_char_w + 34, 64), 340)
    %{label: label, count: count, w: w}
  end

  # Linhas que cabem no balão, e o tamanho dele. O que passa do limite vira
  # "…" — a linha longa no fim, as linhas demais numa última "… +N".
  defp payload_box(text) do
    all = String.split(text, "\n")

    lines =
      if length(all) > @payload_max_lines do
        kept = Enum.take(all, @payload_max_lines - 1)
        kept ++ ["… +#{length(all) - length(kept)}"]
      else
        all
      end
      |> Enum.map(&clip/1)

    longest = lines |> Enum.map(&Scene.char_units/1) |> Enum.max(fn -> 0 end)
    w = min(max(longest * @payload_char_w + 2 * @payload_pad_x, 88), 440)
    h = length(lines) * @payload_line_h + 2 * @payload_pad_y
    {lines, w, h}
  end

  defp clip(line) do
    if String.length(line) > @payload_max_chars,
      do: String.slice(line, 0, @payload_max_chars - 1) <> "…",
      else: line
  end

  defp straight_edge(edge, step, from, to, y) do
    dir = if to.cx > from.cx, do: 1, else: -1
    x1 = from.cx
    x2 = to.cx - dir * 6

    %{
      type: :edge,
      id: edge.id,
      step: step.index,
      from: edge.from,
      to: edge.to,
      arrow: edge.arrow,
      label: edge.label,
      self: false,
      y: round(y),
      x1: round(x1),
      x2: round(x2),
      label_x: round((x1 + x2) / 2),
      label_y: round(y - 13),
      label_anchor: "middle",
      path: "M #{round(x1)} #{round(y)} L #{round(x2)} #{round(y)}",
      duration: Scene.edge_duration(edge)
    }
  end

  defp self_edge(edge, step, lane, y) do
    x = lane.cx
    drop = 38

    path =
      "M #{round(x)} #{round(y)} " <>
        "C #{round(x + 62)} #{round(y)} #{round(x + 62)} #{round(y + drop)} #{round(x + 8)} #{round(y + drop)}"

    %{
      type: :edge,
      id: edge.id,
      step: step.index,
      from: edge.from,
      to: edge.to,
      arrow: edge.arrow,
      label: edge.label,
      self: true,
      y: round(y),
      x1: round(x),
      x2: round(x + 8),
      label_x: round(x + 72),
      label_y: round(y + drop / 2 + 4),
      label_anchor: "start",
      path: path,
      duration: Scene.edge_duration(edge)
    }
  end

  # ── ativações ─────────────────────────────────────────────────────────────

  defp activations(edges, body_h) do
    {closed, open} =
      edges
      |> Enum.sort_by(& &1.y)
      |> Enum.reduce({[], %{}}, fn edge, {closed, open} ->
        case edge.arrow do
          :return ->
            case Map.get(open, edge.from, []) do
              [] -> {closed, open}
              [start | rest] -> {[%{start | y2: edge.y} | closed], Map.put(open, edge.from, rest)}
            end

          arrow when arrow in [:sync, :async] ->
            stack = Map.get(open, edge.to, [])

            bar = %{
              node: edge.to,
              depth: length(stack),
              y1: edge.y,
              y2: nil
            }

            {closed, Map.put(open, edge.to, [bar | stack])}

          _ ->
            {closed, open}
        end
      end)

    dangling =
      open
      |> Map.values()
      |> List.flatten()
      |> Enum.map(&%{&1 | y2: body_h - 14})

    (closed ++ dangling)
    |> Enum.map(fn bar -> %{bar | y2: max(bar.y2, bar.y1 + 18)} end)
    |> Enum.sort_by(& &1.y1)
  end

  # ── saída ─────────────────────────────────────────────────────────────────

  defp lane_to_node(lane, body_h) do
    %{
      id: lane.id,
      label: lane.label,
      kind: lane.kind,
      group: lane.group,
      pinned: Map.get(lane, :pinned, false),
      x: round(lane.x),
      y: @top,
      w: round(lane.w),
      h: @header_h,
      cx: round(lane.cx),
      lifeline_y1: @top + @header_h,
      lifeline_y2: round(body_h - 10)
    }
  end

  defp groups(ast, lanes) do
    by_id = Map.new(lanes, &{&1.id, &1})

    ast.groups
    |> Enum.map(fn group ->
      members = group.node_ids |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1)

      if members == [] do
        nil
      else
        x = members |> Enum.map(& &1.x) |> Enum.min()
        right = members |> Enum.map(& &1.right) |> Enum.max()

        %{
          id: group.id,
          label: group.label,
          x: round(x - 12),
          y: @top - 26,
          w: round(right - x + 24),
          h: @header_h + 38
        }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp steps(ast, rows) do
    bands = Map.new(bands(rows), &{&1.step, &1.y})

    by_step =
      rows
      |> Enum.filter(&(&1.type in [:edge, :note]))
      |> Enum.group_by(& &1.step)

    Enum.map(ast.steps, fn step ->
      items = Map.get(by_step, step.index, [])
      edge_ids = items |> Enum.filter(&(&1.type == :edge)) |> Enum.map(& &1.id)
      note_ids = items |> Enum.filter(&(&1.type == :note)) |> Enum.map(& &1.id)

      %{
        index: step.index,
        label: step.label,
        y: Map.get(bands, step.index, @top),
        edge_ids: edge_ids,
        note_ids: note_ids,
        node_ids: items |> Enum.flat_map(&node_ids_of/1) |> Enum.uniq(),
        duration:
          items
          |> Enum.filter(&(&1.type == :edge))
          |> Enum.map(& &1.duration)
          |> Enum.sum()
          |> max(600)
      }
    end)
  end

  defp node_ids_of(%{type: :edge} = e), do: [e.from, e.to]
  defp node_ids_of(_), do: []

  defp all_edges(ast) do
    ast.steps
    |> Enum.flat_map(& &1.items)
    |> Enum.filter(&match?(%Edge{}, &1))
  end
end
