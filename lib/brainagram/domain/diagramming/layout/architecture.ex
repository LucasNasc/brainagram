defmodule Brainagram.Domain.Diagramming.Layout.Architecture do
  @moduledoc """
  Layout de diagrama arquitetural — Sugiyama com nós fantasma.

  O problema que este módulo existe para resolver: numa aresta que pula camadas
  (a API na camada 2 falando com o Postgres na camada 5), a reta entre os dois
  atravessa tudo que estiver no caminho, em diagonal, cruzando as arestas curtas
  e cortando caixas de grupo. É o que torna um diagrama arquitetural ilegível.

  A solução clássica é **normalizar o grafo**: toda aresta longa vira uma cadeia
  de nós fantasma, um por camada intermediária. A aresta deixa de ser uma reta e
  passa a ser um caminho roteado, e os fantasmas participam do posicionamento
  como qualquer outro nó — ou seja, ganham espaço reservado em vez de passar por
  cima de quem já estava lá.

  O pipeline:

    1. **Camadas** — relaxação iterativa de `camada(destino) >= camada(origem)+1`,
       limitada a |V| passadas para tolerar ciclos.
    2. **Faixas** — cada `group` ocupa uma faixa horizontal exclusiva. Faixas
       disjuntas em X garantem que duas caixas de grupo nunca se sobreponham,
       qualquer que seja a camada de cada membro. A ordem declarada na DSL é o
       ponto de partida; trocas entre faixas vizinhas são aceitas quando encurtam
       a distância total das arestas entre grupos.
    3. **Corredores** — entre faixas (e nas bordas) fica um corredor vertical, com
       uma vaga por aresta longa. A largura cresce com o número de cadeias que
       passam nele, então duas nunca dividem a mesma coluna.
    4. **Ordenação** — quatro varreduras de baricentro (duas para baixo, duas para
       cima) reordenam os nós *dentro* de cada faixa, reduzindo cruzamentos sem
       quebrar a coesão dos grupos.
    5. **Roteamento** — arestas entre camadas vizinhas usam curva suave; as que
       pulam camadas viram polilinha ortogonal com cantos arredondados: sai pela
       base, corre na horizontal dentro do vão entre camadas, desce reta pelo
       corredor. Cruzamento perpendicular é o que o olho separa sem esforço.
    6. **Rótulos** — posicionados no trecho vertical e depois empurrados para
       baixo, um a um, até não se sobreporem.

  ## Posições fixadas (`Hints`)

  Um nó fixado no bloco `layout` mantém a coordenada exata — ponto. A camada
  dele passa a ser derivada do `y`, não do grafo, e os demais seguem o
  algoritmo tratando a caixa fixada como ocupada. Uma fixação que contradiz o
  grafo (destino acima da origem) é desenhada como aresta ascendente: o autor
  mandou, o algoritmo obedece (spec 001, §5).

  Com qualquer posição fixada, as rotas deixam de usar os corredores (que
  supõem as faixas do automático) e passam pelo `Router`, que desvia de
  caixas em qualquer geometria. É também o que desenha a arrumação gravada
  por "Organizar setas" (`Untangle`).

  ## Deitado (`direction horizontal`)

  O pipeline é um só. No horizontal ele roda num plano transposto, com largura
  e altura das caixas trocadas: as camadas que desceriam passam a andar para a
  direita, e as faixas de grupo, que seriam colunas, viram linhas. No fim, as
  caixas são transpostas de volta e todas as setas passam pelo `Router`,
  preferindo sair pelas laterais. As posições fixadas estão no plano real e
  são transpostas na entrada.
  """

  alias Brainagram.Domain.Diagramming.Dsl.{Ast, Edge}
  alias Brainagram.Domain.Diagramming.Layout.{Hints, Router}
  alias Brainagram.Domain.Diagramming.Scene

  @margin 56
  @top 92
  @layer_gap 140
  @node_gap 40
  @node_h 68
  @min_node_w 156
  @label_size 12.0
  @node_label_size 13.5

  @gutter_min 56
  @stub 34
  @stub_step 12
  @corner 14
  @gutter_pad 22
  @dummy_slot 24

  @spec build(Ast.t(), Hints.t()) :: Scene.t()
  def build(ast, hints \\ %Hints{})

  def build(%Ast{nodes: []} = ast, _hints) do
    %Scene{kind: :architecture, title: ast.title, width: 640, height: 280}
  end

  def build(%Ast{} = ast, %Hints{pinned: pinned}) do
    horizontal? = ast.direction == :horizontal
    # o plano em que o pipeline roda: o real ou, deitado, o transposto
    plane_pins =
      if horizontal?, do: Map.new(pinned, fn {id, {x, y}} -> {id, {y, x}} end), else: pinned

    edges = all_edges(ast)
    sizes = sizes(ast.nodes, horizontal?)
    pinned_layers = Map.new(plane_pins, fn {id, {_x, y}} -> {id, layer_of_y(y)} end)
    layers = layers(ast.nodes, edges, pinned_layers)
    free = Enum.reject(ast.nodes, &Map.has_key?(pinned, &1.id))

    {band_order, band_of} = bands(ast.nodes, edges)
    band_index = band_order |> Enum.with_index() |> Map.new()

    by_layer = order_nodes(free, edges, layers, band_index, band_of)
    chains = chains(edges, layers, by_layer, band_of, band_index, length(band_order))

    geometry = place(by_layer, sizes, band_of, band_index, chains, length(band_order))

    boxes =
      geometry.boxes
      |> Map.merge(pinned_boxes(plane_pins, sizes, layers))
      |> avoid_pinned(plane_pins)

    {boxes, laid_edges} =
      if horizontal? do
        boxes = Map.new(boxes, fn {id, box} -> {id, transpose(box)} end)

        laid =
          edges
          |> Enum.map(&route(&1, boxes, %{}, layers))
          |> reroute_around(boxes, ast, :horizontal)

        {boxes, laid}
      else
        lanes = corridors(chains, geometry, boxes)

        laid =
          edges
          |> Enum.map(&route(&1, boxes, lanes, layers))
          |> reroute_around(boxes, ast, if(reroute?(ast, pinned), do: :vertical))

        {boxes, laid}
      end

    laid_edges = spread_labels(laid_edges)

    {edge_right, edge_bottom} = edge_extent(laid_edges)

    height =
      boxes
      |> Map.values()
      |> Enum.map(&(&1.y + &1.h))
      |> Enum.max(&>=/2, fn -> @top end)
      |> max(edge_bottom)

    right =
      boxes
      |> Map.values()
      |> Enum.map(&(&1.x + &1.w + @margin))
      |> Enum.max(fn -> 0 end)
      |> max(edge_right + @margin / 2)

    %Scene{
      kind: :architecture,
      title: ast.title,
      direction: ast.direction,
      width: round(if(horizontal?, do: right, else: max(geometry.width, right))),
      height: round(height + @margin),
      nodes: boxes |> Map.values() |> Enum.sort_by(&{&1.layer, &1.x}) |> Enum.map(&public/1),
      groups: groups(ast, boxes),
      edges: laid_edges,
      notes: [],
      activations: [],
      steps: steps(ast, laid_edges)
    }
  end

  # ── camadas ───────────────────────────────────────────────────────────────

  # Nó fixado tem camada fixa (derivada do `y`) e não é empurrado pela
  # relaxação — mas continua empurrando quem vem depois dele no grafo.
  #
  # Ciclos (A → B → C → A, comum em "o cliente chama, o sistema devolve
  # evento ao cliente") não têm camada que satisfaça todo mundo: a relaxação
  # empurraria o ciclo para baixo a cada passada. As arestas de retorno saem
  # da conta e são desenhadas subindo.
  defp layers(nodes, edges, pinned_layers) do
    ids = Enum.map(nodes, & &1.id)
    init = ids |> Map.new(&{&1, 0}) |> Map.merge(Map.take(pinned_layers, ids))

    pairs =
      edges
      |> Enum.map(&{&1.from, &1.to})
      |> Enum.reject(fn {a, b} -> a == b end)
      |> Enum.uniq()
      |> without_back_edges(ids)

    Enum.reduce_while(1..max(length(ids), 1), init, fn _, acc ->
      next =
        Enum.reduce(pairs, acc, fn {u, v}, m ->
          with lu when not is_nil(lu) <- m[u],
               lv when not is_nil(lv) <- m[v],
               false <- Map.has_key?(pinned_layers, v) do
            if lv < lu + 1, do: Map.put(m, v, lu + 1), else: m
          else
            _ -> m
          end
        end)

      if next == acc, do: {:halt, acc}, else: {:cont, next}
    end)
  end

  # Busca em profundidade a partir das fontes (quem não recebe seta), na ordem
  # de declaração: a aresta que volta para um nó ainda na pilha fecha um ciclo.
  defp without_back_edges(pairs, ids) do
    succs = Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))
    targets = MapSet.new(pairs, &elem(&1, 1))
    {sources, rest} = Enum.split_with(ids, &(not MapSet.member?(targets, &1)))

    {_seen, back} =
      Enum.reduce(sources ++ rest, {MapSet.new(), MapSet.new()}, fn id, acc ->
        visit(id, succs, MapSet.new(), acc)
      end)

    Enum.reject(pairs, &MapSet.member?(back, &1))
  end

  defp visit(id, succs, stack, {seen, back} = acc) do
    if MapSet.member?(seen, id) do
      acc
    else
      stack = MapSet.put(stack, id)

      succs
      |> Map.get(id, [])
      |> Enum.reduce({MapSet.put(seen, id), back}, fn next, {seen2, back2} ->
        if MapSet.member?(stack, next),
          do: {seen2, MapSet.put(back2, {id, next})},
          else: visit(next, succs, stack, {seen2, back2})
      end)
    end
  end

  # ── faixas ────────────────────────────────────────────────────────────────

  # Todos os nós sem grupo dividem uma faixa só. Dar uma faixa por nó solto
  # transformaria um diagrama sem `group` nenhum — o caso mais comum — numa
  # escada de uma coluna por caixa, larguíssima e com uma caixa por camada.
  # O prefixo nulo evita colisão com um grupo que por acaso se chame igual.
  defp band_key(%{group: nil}), do: "\0avulsos"
  defp band_key(%{group: group}), do: group

  defp bands(nodes, edges) do
    declared = nodes |> Enum.map(&band_key/1) |> Enum.uniq()
    of = Map.new(nodes, &{&1.id, band_key(&1)})
    {refine_band_order(declared, edges, of), of}
  end

  # A ordem declarada na DSL é o ponto de partida, não a palavra final: trocas
  # de faixas vizinhas são aceitas enquanto encurtarem a distância total das
  # arestas entre grupos. Duas colunas que conversam muito acabam lado a lado, e
  # uma aresta que antes atravessava o diagrama passa a cruzar um vão só.
  #
  # A busca é local (só vizinhos) e parte do que o autor escreveu — então o
  # resultado continua previsível, e reordenar os `group` no texto ainda muda o
  # desenho.
  defp refine_band_order(declared, _edges, _band_of) when length(declared) < 3, do: declared

  defp refine_band_order(declared, edges, band_of) do
    pairs =
      edges
      |> Enum.map(&{band_of[&1.from], band_of[&1.to]})
      |> Enum.reject(fn {a, b} -> is_nil(a) or is_nil(b) or a == b end)
      |> Enum.frequencies()

    Enum.reduce(1..4, declared, fn _pass, order ->
      0..(length(order) - 2)
      |> Enum.reduce(order, fn i, acc ->
        swapped = swap_at(acc, i)
        if spread(swapped, pairs) < spread(acc, pairs), do: swapped, else: acc
      end)
    end)
  end

  defp swap_at(list, i) do
    {before, [a, b | rest]} = Enum.split(list, i)
    before ++ [b, a] ++ rest
  end

  defp spread(order, pairs) do
    index = order |> Enum.with_index() |> Map.new()

    Enum.reduce(pairs, 0, fn {{a, b}, weight}, total ->
      total + abs(Map.fetch!(index, a) - Map.fetch!(index, b)) * weight
    end)
  end

  # ── ordenação ─────────────────────────────────────────────────────────────

  defp order_nodes(nodes, edges, layers, band_index, band_of) do
    decl = nodes |> Enum.with_index() |> Map.new(fn {n, i} -> {n.id, i} end)
    by_layer = Enum.group_by(nodes, &layers[&1.id], & &1.id)
    keys = by_layer |> Map.keys() |> Enum.sort()

    {preds, succs} =
      Enum.reduce(edges, {%{}, %{}}, fn e, {p, s} ->
        if e.from == e.to do
          {p, s}
        else
          {Map.update(p, e.to, [e.from], &[e.from | &1]),
           Map.update(s, e.from, [e.to], &[e.to | &1])}
        end
      end)

    Enum.reduce(1..4, by_layer, fn pass, acc ->
      down? = rem(pass, 2) == 1
      sweep_keys = if down?, do: keys, else: Enum.reverse(keys)
      adjacency = if down?, do: preds, else: succs
      sweep(acc, sweep_keys, adjacency, band_index, band_of, decl)
    end)
  end

  defp sweep(by_layer, keys, adjacency, band_index, band_of, decl) do
    Enum.reduce(keys, by_layer, fn layer, acc ->
      positions = positions_of(acc)

      sorted =
        acc
        |> Map.fetch!(layer)
        |> Enum.sort_by(fn id ->
          neighbours =
            adjacency |> Map.get(id, []) |> Enum.map(&positions[&1]) |> Enum.reject(&is_nil/1)

          barycenter =
            if neighbours == [],
              do: decl[id] * 1.0,
              else: Enum.sum(neighbours) / length(neighbours)

          # A faixa vem primeiro: o baricentro reordena *dentro* do grupo, nunca
          # espalha os membros dele pela camada.
          {band_index[band_of[id]], barycenter, decl[id]}
        end)

      Map.put(acc, layer, sorted)
    end)
  end

  defp positions_of(by_layer) do
    for {_layer, ids} <- by_layer,
        {id, index} <- Enum.with_index(ids),
        into: %{},
        do: {id, index}
  end

  # ── cadeias de fantasmas ──────────────────────────────────────────────────

  # Uma cadeia é a lista de camadas intermediárias que uma aresta longa precisa
  # atravessar, mais o corredor por onde ela vai descer.
  defp chains(edges, layers, by_layer, band_of, band_index, band_count) do
    edges
    |> Enum.flat_map(fn edge ->
      with false <- edge.from == edge.to,
           lu when not is_nil(lu) <- layers[edge.from],
           lv when not is_nil(lv) <- layers[edge.to],
           true <- abs(lv - lu) > 1 do
        between = if lu < lv, do: (lu + 1)..(lv - 1), else: (lv + 1)..(lu - 1)

        [
          {edge.id,
           %{
             from: edge.from,
             to: edge.to,
             gutter: gutter_for(edge, by_layer, layers, band_of, band_index, band_count),
             span: Enum.to_list(between)
           }}
        ]
      else
        _ -> []
      end
    end)
    |> Map.new()
  end

  # Escolher o corredor é escolher de que lado a aresta vai descer — e é o que
  # decide se ela chega limpa ou atravessando meia camada.
  #
  # Entre faixas diferentes, o corredor é o que fica *entre* as duas: a aresta
  # sai, desce pelo vão e entra no destino pela lateral.
  #
  # Dentro da mesma faixa, o lado é o do destino. Descer sempre pela direita e
  # depois voltar para um destino que está à esquerda faz a aresta cortar tudo
  # que estiver na última camada — foi exatamente o cruzamento que sobrava entre
  # "SELECT" e "upload".
  defp gutter_for(edge, by_layer, layers, band_of, band_index, band_count) do
    a = band_index[band_of[edge.from]] || 0
    b = band_index[band_of[edge.to]] || 0

    if a == b do
      if target_on_left_half?(edge.to, by_layer, layers), do: a, else: min(a + 1, band_count)
    else
      max(a, b)
    end
  end

  defp target_on_left_half?(id, by_layer, layers) do
    peers = Map.get(by_layer, layers[id], [])

    case Enum.find_index(peers, &(&1 == id)) do
      nil -> false
      index -> index < length(peers) / 2
    end
  end

  # ── posicionamento ────────────────────────────────────────────────────────

  # Deitado, largura e altura trocam: o pipeline enxerga a caixa já girada.
  defp sizes(nodes, horizontal?) do
    Map.new(nodes, fn n ->
      {w, h} = box_size(n)
      {w, h} = if horizontal?, do: {h, w}, else: {w, h}
      {n.id, %{w: w, h: h, label: n.label, kind: n.kind, group: n.group}}
    end)
  end

  # O losango leva a pergunta no meio: só cabe a faixa central, então ele é
  # mais largo que o texto e mais alto que as caixas.
  defp box_size(%{kind: :decision} = n) do
    {Scene.decision_width(n.label, @node_label_size, @min_node_w), Scene.decision_h()}
  end

  defp box_size(n) do
    w = round(max(@min_node_w, Scene.text_width(n.label, @node_label_size) + 52) + extra_w(n))
    {w, @node_h}
  end

  # A fila é um cilindro deitado: a tampa da direita come parte da caixa.
  defp extra_w(%{kind: :queue}), do: Scene.queue_cap() * 2
  defp extra_w(_node), do: 0

  defp transpose(box), do: %{box | x: box.y, y: box.x, w: box.h, h: box.w, cx: box.cy, cy: box.cx}

  defp place(by_layer, sizes, band_of, band_index, chains, band_count) do
    band = fn id -> Map.get(band_index, Map.get(band_of, id), 0) end

    runs =
      for {layer, ids} <- by_layer,
          chunk <- Enum.chunk_by(ids, band),
          do: {layer, band.(hd(chunk)), chunk}

    band_widths =
      Enum.reduce(runs, %{}, fn {_layer, b, chunk}, acc ->
        Map.update(acc, b, run_width(chunk, sizes), &max(&1, run_width(chunk, sizes)))
      end)

    gutter_widths = gutter_widths(chains, band_count)

    {band_x, gutter_x, cursor} =
      Enum.reduce(0..(band_count - 1), {%{}, %{}, @margin}, fn i, {bx, gx, x} ->
        gx = Map.put(gx, i, x)
        x = x + Map.fetch!(gutter_widths, i)
        bx = Map.put(bx, i, x)
        {bx, gx, x + Map.get(band_widths, i, @min_node_w)}
      end)

    gutter_x = Map.put(gutter_x, band_count, cursor)
    width = cursor + Map.fetch!(gutter_widths, band_count) + @margin
    {layer_y, layer_h} = layer_rows(by_layer, sizes)

    boxes =
      runs
      |> Enum.flat_map(fn {layer, b, chunk} ->
        span = run_width(chunk, sizes)
        start = Map.fetch!(band_x, b) + (Map.get(band_widths, b, span) - span) / 2

        chunk
        |> Enum.reduce({[], start}, fn id, {acc, x} ->
          s = sizes[id]
          # caixas mais baixas que a camada ficam centradas nela
          y = layer_y.(layer) + div(layer_h.(layer) - s.h, 2)

          box = %{
            id: id,
            label: s.label,
            kind: s.kind,
            group: s.group,
            layer: layer,
            x: round(x),
            y: y,
            w: round(s.w),
            h: s.h,
            cx: round(x + s.w / 2),
            cy: y + div(s.h, 2)
          }

          {[box | acc], x + s.w + @node_gap}
        end)
        |> elem(0)
      end)
      |> Map.new(&{&1.id, &1})

    %{boxes: boxes, gutter_x: gutter_x, width: width}
  end

  # A largura de um corredor acompanha quantas cadeias passam por ele. Uma vaga
  # por cadeia (e não por camada) é o que permite a aresta descer em linha reta
  # de ponta a ponta: mudar de coluna no meio do caminho seria mais uma curva
  # para o leitor seguir.
  defp gutter_widths(chains, band_count) do
    load = chains |> Enum.map(fn {_id, chain} -> chain.gutter end) |> Enum.frequencies()

    for g <- 0..band_count, into: %{} do
      slots = Map.get(load, g, 0)

      width =
        cond do
          slots > 0 -> @gutter_pad * 2 + @dummy_slot * slots
          g == 0 or g == band_count -> 0
          true -> @gutter_min
        end

      {g, width}
    end
  end

  # A espessura de cada camada é a da caixa mais alta dela. Em pé são todas
  # `@node_h` e o `y` da camada é `@top + camada * (@node_h + @layer_gap)`;
  # deitado, a "altura" é a largura do rótulo e cada coluna tem a sua.
  defp layer_rows(by_layer, sizes) do
    heights =
      Map.new(by_layer, fn {layer, ids} ->
        {layer, ids |> Enum.map(&sizes[&1].h) |> Enum.max(fn -> @node_h end)}
      end)

    height = fn layer -> Map.get(heights, layer, @node_h) end
    last = by_layer |> Map.keys() |> Enum.max(fn -> 0 end)

    tops =
      Enum.reduce(0..last//1, %{0 => @top}, fn layer, acc ->
        Map.put(acc, layer + 1, acc[layer] + height.(layer) + @layer_gap)
      end)

    {fn layer -> Map.get(tops, layer, @top + layer * (@node_h + @layer_gap)) end, height}
  end

  defp layer_of_y(y), do: max(0, round((y - @top) / (@node_h + @layer_gap)))

  defp pinned_boxes(pinned, sizes, layers) do
    for {id, {x, y}} <- pinned, s = sizes[id], s != nil, into: %{} do
      w = round(s.w)

      {id,
       %{
         id: id,
         label: s.label,
         kind: s.kind,
         group: s.group,
         layer: layers[id],
         x: x,
         y: y,
         w: w,
         h: s.h,
         cx: round(x + w / 2),
         cy: y + div(s.h, 2),
         pinned: true
       }}
    end
  end

  # A caixa fixada é obstáculo: quem caiu em cima dela é empurrado para a
  # direita, e empurra junto os vizinhos da mesma camada — a ordem da camada
  # não muda, só abre espaço.
  defp avoid_pinned(boxes, pinned) when map_size(pinned) == 0, do: boxes

  defp avoid_pinned(boxes, pinned) do
    fixed = boxes |> Map.take(Map.keys(pinned)) |> Map.values()

    boxes
    |> Map.values()
    |> Enum.reject(&Map.has_key?(pinned, &1.id))
    |> Enum.group_by(& &1.layer)
    |> Enum.flat_map(fn {_layer, row} ->
      row
      |> Enum.sort_by(& &1.x)
      |> Enum.map_reduce(nil, fn box, cursor ->
        x = clear_of(max(box.x, cursor || box.x), box, fixed)
        {%{box | x: x, cx: round(x + box.w / 2)}, x + box.w + @node_gap}
      end)
      |> elem(0)
    end)
    |> Map.new(&{&1.id, &1})
    |> Map.merge(Map.new(fixed, &{&1.id, &1}))
  end

  defp clear_of(x, box, fixed) do
    case Enum.find(fixed, &collides?(x, box, &1)) do
      nil -> x
      other -> clear_of(other.x + other.w + @node_gap, box, fixed)
    end
  end

  defp collides?(x, box, other) do
    x < other.x + other.w + @node_gap and other.x < x + box.w + @node_gap and
      box.y < other.y + other.h + @node_gap and other.y < box.y + box.h + @node_gap
  end

  defp run_width(chunk, sizes) do
    Enum.reduce(chunk, 0, &(&2 + sizes[&1].w)) + @node_gap * (length(chunk) - 1)
  end

  # Cada cadeia recebe uma vaga fixa no seu corredor. A ordem das vagas segue a
  # altura da origem: cadeias que começam mais acima ficam mais para fora, então
  # os trechos horizontais de entrada e saída não se cruzam dentro do corredor.
  defp corridors(chains, geometry, boxes) do
    chains
    |> Enum.group_by(fn {_id, chain} -> chain.gutter end)
    |> Enum.flat_map(fn {gutter, entries} ->
      entries
      |> Enum.sort_by(fn {id, chain} -> {origin_y(chain, boxes), target_y(chain, boxes), id} end)
      |> Enum.with_index()
      |> Enum.map(fn {{id, _chain}, slot} ->
        {id, %{x: geometry.gutter_x[gutter] + @gutter_pad + slot * @dummy_slot, slot: slot}}
      end)
    end)
    |> Map.new()
  end

  defp origin_y(chain, boxes), do: (boxes[chain.from] || %{cy: 0}).cy
  defp target_y(chain, boxes), do: (boxes[chain.to] || %{cy: 0}).cy

  # ── roteamento ────────────────────────────────────────────────────────────

  defp route(%Edge{} = edge, boxes, lanes, layers) do
    a = boxes[edge.from]
    b = boxes[edge.to]

    geometry =
      cond do
        is_nil(a) or is_nil(b) -> fallback()
        edge.from == edge.to -> self_loop(a)
        layers[edge.from] == layers[edge.to] -> sideways(a, b)
        true -> through(a, b, Map.get(lanes, edge.id))
      end

    Map.merge(
      %{
        id: edge.id,
        from: edge.from,
        to: edge.to,
        arrow: edge.arrow,
        label: edge.label,
        self: edge.from == edge.to,
        duration: Scene.edge_duration(edge)
      },
      geometry
    )
  end

  defp fallback do
    %{path: "M 0 0", x1: 0, y1: 0, x2: 0, y2: 0, label_x: 0, label_y: 0, label_anchor: "middle"}
  end

  # Roteamento ortogonal: sai pelo topo ou pela base, corre na horizontal *dentro
  # do vão entre camadas* (espaço sempre livre), desce reto pelo corredor e entra
  # pela mesma lógica do outro lado.
  #
  # Duas razões para abandonar a diagonal suave aqui. A primeira é legibilidade:
  # quando uma reta vertical cruza uma horizontal, o cruzamento é perpendicular e
  # o olho separa as duas sem esforço — é o que mantém um esquema elétrico legível
  # com dezenas de fios. A segunda é segurança: sair pela lateral faria o trecho
  # horizontal passar por cima dos vizinhos da mesma camada, enquanto o vão entre
  # camadas é, por construção, vazio.
  # Aresta entre camadas vizinhas não precisa de corredor: a curva suave liga os
  # dois pontos sem ambiguidade e fica mais leve que uma quina.
  defp through(a, b, nil) do
    down? = b.y > a.y
    {y1, y2} = if down?, do: {a.y + a.h, b.y}, else: {a.y, b.y + b.h}
    c = abs(y2 - y1) * 0.45
    {c1, c2} = if down?, do: {y1 + c, y2 - c}, else: {y1 - c, y2 + c}

    %{
      path: "M #{r(a.cx)} #{r(y1)} C #{r(a.cx)} #{r(c1)} #{r(b.cx)} #{r(c2)} #{r(b.cx)} #{r(y2)}",
      x1: r(a.cx),
      y1: r(y1),
      x2: r(b.cx),
      y2: r(y2),
      label_x: r((a.cx + b.cx) / 2 + 10),
      label_y: r((y1 + y2) / 2),
      label_anchor: "start"
    }
  end

  defp through(a, b, lane) do
    down? = b.y > a.y
    clearance = @stub + lane.slot * @stub_step

    {sy, ty} = if down?, do: {a.y + a.h, b.y}, else: {a.y, b.y + b.h}
    run_out = if down?, do: sy + clearance, else: sy - clearance
    run_in = if down?, do: ty - clearance, else: ty + clearance

    points =
      dedupe([
        {a.cx * 1.0, sy * 1.0},
        {a.cx * 1.0, run_out * 1.0},
        {lane.x * 1.0, run_out * 1.0},
        {lane.x * 1.0, run_in * 1.0},
        {b.cx * 1.0, run_in * 1.0},
        {b.cx * 1.0, ty * 1.0}
      ])

    %{
      path: rounded(points, @corner),
      x1: round(a.cx),
      y1: round(sy),
      x2: round(b.cx),
      y2: round(ty),
      label_x: round(lane.x + 10),
      label_y: round((run_out + run_in) / 2),
      label_anchor: "start"
    }
  end

  # Polilinha com cantos arredondados: `L` até pouco antes da quina, `Q` passando
  # por ela, `L` de novo. O raio encolhe quando o trecho é curto, senão a curva
  # ultrapassaria o ponto seguinte.
  defp rounded([], _radius), do: "M 0 0"
  defp rounded([a], _radius), do: "M #{point(a)}"
  defp rounded([a, b], _radius), do: "M #{point(a)} L #{point(b)}"

  defp rounded(points, radius) do
    [first | _] = points
    last = List.last(points)

    middle =
      points
      |> Enum.slice(1..-2//1)
      |> Enum.with_index(1)
      |> Enum.map_join(" ", fn {corner, i} ->
        previous = Enum.at(points, i - 1)
        following = Enum.at(points, i + 1)
        r = min(radius, min(distance(previous, corner), distance(corner, following)) / 2)

        "L #{point(towards(corner, previous, r))} Q #{point(corner)} #{point(towards(corner, following, r))}"
      end)

    "M #{point(first)} #{middle} L #{point(last)}"
  end

  defp towards({x, y}, {tx, ty}, r) do
    d = distance({x, y}, {tx, ty})
    if d == 0, do: {x, y}, else: {x + (tx - x) / d * r, y + (ty - y) / d * r}
  end

  defp distance({x1, y1}, {x2, y2}), do: :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(y2 - y1, 2))

  defp dedupe(points), do: Enum.dedup_by(points, fn {x, y} -> {round(x), round(y)} end)

  defp sideways(a, b) do
    from_right? = a.cx <= b.cx
    x1 = if from_right?, do: a.x + a.w, else: a.x
    x2 = if from_right?, do: b.x, else: b.x + b.w
    y = a.cy
    bow = 30
    mid = (x1 + x2) / 2

    %{
      path:
        "M #{r(x1)} #{r(y)} C #{r(mid)} #{r(y - bow)} #{r(mid)} #{r(y - bow)} #{r(x2)} #{r(y)}",
      x1: r(x1),
      y1: r(y),
      x2: r(x2),
      y2: r(y),
      label_x: r(mid),
      label_y: r(y - bow - 6),
      label_anchor: "middle"
    }
  end

  defp self_loop(a) do
    x = a.x + a.w
    y = a.y + a.h * 0.32

    %{
      path:
        "M #{r(x)} #{r(y)} C #{r(x + 64)} #{r(y - 22)} #{r(x + 64)} #{r(y + 46)} #{r(x)} #{r(y + 26)}",
      x1: r(x),
      y1: r(y),
      x2: r(x),
      y2: r(y + 26),
      label_x: r(x + 72),
      label_y: r(y + 16),
      label_anchor: "start"
    }
  end

  defp point({x, y}), do: "#{r(x)} #{r(y)}"

  # Com alguma posição fixada, os corredores deixam de valer: eles supõem as
  # faixas do automático, e uma caixa arrastada pode estar bem no meio de um.
  # Aí as rotas vêm do `Router`, que desvia de qualquer geometria.
  # Em pé, o `Router` assume quando há posição fixada (os corredores supõem as
  # faixas do automático) ou losango (as respostas saem por pontas diferentes,
  # e os corredores só sabem sair pela base).
  defp reroute?(ast, pinned),
    do: map_size(pinned) > 0 or Enum.any?(ast.nodes, &(&1.kind == :decision))

  # Deitado, as rotas vêm sempre do `Router`: os corredores são do plano em pé.
  defp reroute_around(edges, _boxes, _ast, nil), do: edges

  defp reroute_around(edges, boxes, ast, prefer) do
    groups = groups(ast, boxes)
    group_of = Map.new(boxes, fn {id, box} -> {id, box.group} end)
    routed = Router.route(boxes, edges, groups, group_of, prefer: prefer)

    Enum.map(edges, fn edge ->
      case routed[edge.id] do
        nil -> edge
        geometry -> Map.merge(edge, geometry)
      end
    end)
  end

  # Rotas que contornam por fora e rótulos compridos também precisam caber na
  # cena — senão o SVG exportado corta o texto na borda.
  defp edge_extent(edges) do
    Enum.reduce(edges, {0, 0}, fn edge, {right, bottom} ->
      {xs, ys} =
        ~r/-?\d+(?:\.\d+)?/
        |> Regex.scan(edge.path)
        |> List.flatten()
        |> Enum.map(&String.to_float(if String.contains?(&1, "."), do: &1, else: &1 <> ".0"))
        |> Enum.chunk_every(2, 2, :discard)
        |> Enum.map(&List.to_tuple/1)
        |> Enum.unzip()

      label_right =
        case edge.label do
          nil ->
            0

          label ->
            w = Scene.text_width(label, @label_size) + 14
            if edge.label_anchor == "middle", do: edge.label_x + w / 2, else: edge.label_x + w
        end

      {Enum.max([right, label_right | xs]), Enum.max([bottom, edge.label_y + 10 | ys])}
    end)
  end

  # ── rótulos ───────────────────────────────────────────────────────────────

  # Passada final: empurra rótulos que se sobrepõem para baixo, um por vez. É
  # ingênuo de propósito — resolve o caso comum (duas arestas saindo do mesmo nó)
  # sem inventar um solver de colisão que ninguém conseguiria depurar depois.
  defp spread_labels(edges) do
    {laid, _boxes} =
      edges
      |> Enum.sort_by(&{&1.label_y, &1.label_x})
      |> Enum.map_reduce([], fn edge, taken ->
        if is_nil(edge.label) do
          {edge, taken}
        else
          box = label_box(edge)
          shifted = avoid(box, taken)
          {%{edge | label_y: round(shifted.y + shifted.h / 2)}, [shifted | taken]}
        end
      end)

    Enum.sort_by(laid, & &1.id)
  end

  defp label_box(edge) do
    w = Scene.text_width(edge.label, @label_size) + 14
    h = 16.0

    x =
      case edge.label_anchor do
        "middle" -> edge.label_x - w / 2
        "end" -> edge.label_x - w * 1.0
        _ -> edge.label_x * 1.0
      end

    %{x: x, y: edge.label_y - h / 2, w: w, h: h}
  end

  defp avoid(box, taken) do
    case Enum.find(taken, &overlaps?(box, &1)) do
      nil -> box
      other -> avoid(%{box | y: other.y + other.h + 4}, taken)
    end
  end

  defp overlaps?(a, b) do
    a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
  end

  defp r(n), do: round(n)

  # ── grupos e passos ───────────────────────────────────────────────────────

  defp public(box) do
    box
    |> Map.take([:id, :label, :kind, :group, :x, :y, :w, :h, :cx, :cy])
    |> Map.put(:pinned, Map.get(box, :pinned, false))
  end

  defp groups(ast, boxes) do
    ast.groups
    |> Enum.map(fn group ->
      members = group.node_ids |> Enum.map(&boxes[&1]) |> Enum.reject(&is_nil/1)

      if members == [] do
        nil
      else
        pad = 22
        x = (members |> Enum.map(& &1.x) |> Enum.min()) - pad
        y = (members |> Enum.map(& &1.y) |> Enum.min()) - pad - 20
        right = (members |> Enum.map(&(&1.x + &1.w)) |> Enum.max()) + pad
        bottom = (members |> Enum.map(&(&1.y + &1.h)) |> Enum.max()) + pad

        %{id: group.id, label: group.label, x: r(x), y: r(y), w: r(right - x), h: r(bottom - y)}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp steps(ast, laid_edges) do
    by_id = Map.new(laid_edges, &{&1.id, &1})

    Enum.map(ast.steps, fn step ->
      edges =
        step.items
        |> Enum.filter(&match?(%Edge{}, &1))
        |> Enum.map(&by_id[&1.id])
        |> Enum.reject(&is_nil/1)

      %{
        index: step.index,
        label: step.label,
        y: 0,
        edge_ids: Enum.map(edges, & &1.id),
        note_ids: [],
        node_ids: edges |> Enum.flat_map(&[&1.from, &1.to]) |> Enum.uniq(),
        duration: edges |> Enum.map(& &1.duration) |> Enum.sum() |> max(600)
      }
    end)
  end

  defp all_edges(ast) do
    ast.steps
    |> Enum.flat_map(& &1.items)
    |> Enum.filter(&match?(%Edge{}, &1))
  end
end
