defmodule Brainagram.Domain.Diagramming.Dsl.Parser do
  @moduledoc """
  Parser da DSL do Brainagram.

  A gramática é orientada a linha com blocos delimitados por `{ }`. Escolha
  deliberada: o parser nunca aborta no primeiro erro — ele coleta *todos* os
  problemas com número de linha, para que o editor consiga mostrar os erros
  inline enquanto o usuário digita.

      diagram sequence "Checkout"

      actor user "Usuário"
      participant api "API Gateway"
      database db "Postgres"

      step "Criação do pedido" {
        user -> api : POST /orders
        api -> db  : INSERT order
        db --> api : ok
        api --> user : 201 Created
      }

      layout {
        db at (420, 680)
      }

  Num diagrama de arquitetura, `direction horizontal` (ou `LR`) deita o
  layout: as camadas correm da esquerda para a direita. `direction vertical`
  (ou `TB`) é o padrão.

  Setas suportadas:

    * `->`  chamada síncrona
    * `-->` retorno / resposta
    * `->>` mensagem assíncrona (fire-and-forget)
    * `-x`  falha / timeout

  Além da estrutura, o parser registra onde cada coisa está no texto
  (`%Span{}` por declaração e por campo editável). É o que permite ao canvas
  editar o fonte sem regenerá-lo — ver `Dsl.Editor`.
  """

  alias Brainagram.Domain.Diagramming.Dsl.{Ast, Edge, Group, Node, Note, ParseError, Pin, Span}
  alias Brainagram.Domain.Diagramming.Dsl.Step
  alias Brainagram.Shared.Text

  @node_kinds ~w(actor participant database queue service component external system node boundary decision)

  @re_diagram ~r/^diagram\s+(?<kind>[a-z]+)(?:\s+"(?<title>[^"]*)")?$/i
  @re_step ~r/^step\s+"(?<label>[^"]*)"\s*\{$/i
  @re_group ~r/^group\s+"(?<label>[^"]*)"\s*\{$/i
  @re_layout ~r/^layout\s*\{$/i
  @re_direction ~r/^direction\s+(?<value>[A-Za-z\-]+)$/i
  @re_pin ~r/^(?<id>[A-Za-z_][\w\-.]*)\s+at\s*(?<coords>\(\s*(?<x>-?\d+)\s*,\s*(?<y>-?\d+)\s*\))$/
  @re_node ~r/^(?<kind>#{Enum.join(@node_kinds, "|")})\s+(?<id>[A-Za-z_][\w\-.]*)(?:\s+(?:as\s+)?"(?<label>[^"]*)")?(?:\s+kind:\s*(?<kind2>[a-z]+))?$/i
  @re_note ~r/^note\s+(?<placement>over|left of|right of)\s+(?<targets>[A-Za-z_][\w\-.]*(?:\s*,\s*[A-Za-z_][\w\-.]*)*)\s*:\s*(?<text>.*)$/i
  # payload de uma mensagem: `payload: {"id": 1}` ou o bloco `payload """`
  @re_payload_line ~r/^(?:payload|dados)\s*:\s*(?<text>.*)$/i
  @re_payload_open ~r/^(?:payload|dados)\s*"""$/i
  @fence ~s(""")
  @re_edge ~r/^(?<from>[A-Za-z_][\w\-.]*)\s*(?<arrow>->>|-->|->|-x)\s*(?<to>[A-Za-z_][\w\-.]*)\s*(?::\s*(?<label>.*))?$/

  @type error :: ParseError.t()

  @doc "Tipos de nó aceitos pela DSL, na ordem em que aparecem na documentação."
  @spec node_kinds() :: [String.t()]
  def node_kinds, do: @node_kinds

  @doc """
  Faz o parse do código-fonte.

  Retorna `{:ok, %Ast{}}` ou `{:error, [%ParseError{}]}` com *todos* os
  problemas encontrados, ordenados por linha.
  """
  @spec parse(String.t()) :: {:ok, Ast.t()} | {:error, [error()]}
  def parse(source) when is_binary(source) do
    state =
      source
      |> lines()
      |> Enum.reduce(initial_state(), &parse_line/2)
      |> close_dangling_blocks()
      |> finalize()

    case state.errors do
      [] -> {:ok, state.ast}
      errors -> {:error, Enum.sort_by(errors, & &1.line)}
    end
  end

  @doc """
  O fonte tem comentário (`#` ou `//` fora de aspas)? O printer canônico não os
  preserva — quem formata o arquivo inteiro precisa avisar antes.
  """
  @spec comments?(String.t()) :: boolean()
  def comments?(source) when is_binary(source) do
    source
    |> String.split(~r/\r\n|\r|\n/)
    |> Enum.any?(&(strip_comment(&1) != &1))
  end

  # Divide em linhas guardando o offset (em bytes) de cada uma. `\r\n`, `\r` e
  # `\n` contam como quebra — o offset é o que mantém os spans exatos em
  # qualquer um deles.
  defp lines(source) do
    ~r/\r\n|\r|\n/
    |> Regex.split(source, include_captures: true)
    |> Enum.chunk_every(2)
    |> Enum.map_reduce({0, 1}, fn [text | sep], {offset, line} ->
      sep = List.first(sep, "")
      {{text, line, offset}, {offset + byte_size(text) + byte_size(sep), line + 1}}
    end)
    |> elem(0)
  end

  # ── estado ────────────────────────────────────────────────────────────────

  defp initial_state do
    %{
      kind: :sequence,
      title: nil,
      direction: :vertical,
      direction_span: nil,
      header_span: nil,
      header_spans: %{},
      nodes: [],
      node_ids: MapSet.new(),
      groups: [],
      steps: [],
      loose: [],
      pins: [],
      layout_span: nil,
      layout_end_span: nil,
      block: nil,
      block_label: nil,
      block_line: nil,
      block_span: nil,
      block_spans: %{},
      block_items: [],
      block_nodes: [],
      counter: 0,
      # payload: o bloco """ aberto (as linhas vão cruas, sem tirar comentário)
      raw: nil,
      # linha da última mensagem (ou do último payload dela) e da última linha
      # com conteúdo — o payload só vale colado na mensagem
      edge_line: nil,
      last_line: nil,
      errors: [],
      ast: %Ast{}
    }
  end

  # ── linha a linha ─────────────────────────────────────────────────────────

  # Dentro de `payload """`: a linha vai inteira, sem tirar comentário — `#` e
  # `//` num JSON ou numa URL são conteúdo — até a linha com `"""`.
  defp parse_line({raw, line, start}, %{raw: %{} = open} = state) do
    trimmed = String.trim(raw)

    if trimmed == @fence do
      {index, _} = :binary.match(raw, @fence)
      close_span = Span.new(line, index + 1, start + index, byte_size(@fence))
      close_payload(%{state | raw: nil}, open, close_span, line)
    else
      %{state | raw: %{open | lines: open.lines ++ [raw]}}
    end
  end

  defp parse_line({raw, line, start}, state) do
    stripped = strip_comment(raw)
    trimmed_left = String.trim_leading(stripped)
    text = String.trim_trailing(trimmed_left)
    # onde o texto útil começa no fonte — âncora de todo span desta linha
    base = start + byte_size(stripped) - byte_size(trimmed_left)
    at = %{line: line, start: start, base: base, text: text}

    cond do
      text == "" -> state
      text == "}" -> %{close_block(state, at) | last_line: line}
      true -> %{dispatch(text, at, state) | last_line: line}
    end
  end

  defp dispatch(text, at, state) do
    cond do
      state.block == :layout ->
        put_pin(state, match(@re_pin, text, at), at)

      m = match(@re_diagram, text, at) ->
        put_diagram(state, m, at)

      m = match(@re_step, text, at) ->
        open_block(state, :step, m, at)

      m = match(@re_group, text, at) ->
        open_block(state, :group, m, at)

      m = match(@re_layout, text, at) ->
        open_layout(state, m, at)

      m = match(@re_direction, text, at) ->
        put_direction(state, m, at)

      m = match(@re_node, text, at) ->
        put_node(state, m, at)

      m = match(@re_note, text, at) ->
        put_note(state, m, at)

      m = match(@re_edge, text, at) ->
        put_edge(state, m, at)

      m = match(@re_payload_open, text, at) ->
        # se vale é decidido aqui, onde "logo abaixo da mensagem" é verificável
        %{state | raw: %{span: m.span, line: at.line, lines: [], attached?: attached?(state)}}

      m = match(@re_payload_line, text, at) ->
        attach_payload(state, m.caps["text"], m.span, m.span, at.line)

      match(@re_pin, text, at) ->
        error(state, at.line, :pin_outside_layout, %{text: inspect(text)})

      true ->
        error(state, at.line, :unknown_line, %{text: inspect(text)})
    end
  end

  # Captura nomeada com posição. Devolve `%{caps: %{nome => valor}, spans:
  # %{nome => %Span{} | nil}, span: %Span{}}` — o valor é "" quando o grupo
  # opcional não casou, igual ao `Regex.named_captures/2`.
  defp match(regex, text, at) do
    case Regex.run(regex, text, capture: :all_names, return: :index) do
      nil ->
        nil

      indexes ->
        pairs = Enum.zip(Regex.names(regex), indexes)

        %{
          caps: Map.new(pairs, fn {name, index} -> {name, value(text, index)} end),
          spans: Map.new(pairs, fn {name, index} -> {name, span_of(at, index)} end),
          span: span_of(at, {0, byte_size(text)})
        }
    end
  end

  defp value(_text, {offset, _length}) when offset < 0, do: ""
  defp value(text, {offset, length}), do: binary_part(text, offset, length)

  defp span_of(_at, {offset, _length}) when offset < 0, do: nil

  defp span_of(at, {offset, length}) do
    absolute = at.base + offset
    Span.new(at.line, absolute - at.start + 1, absolute, length)
  end

  # ── diretivas ─────────────────────────────────────────────────────────────

  defp put_diagram(state, m, at) do
    spans = %{kind: m.spans["kind"], title: m.spans["title"]}
    caps = m.caps

    case String.downcase(caps["kind"]) do
      k when k in ["sequence", "sequencia", "sequência", "seq"] ->
        %{
          state
          | kind: :sequence,
            title: blank_to_nil(caps["title"]),
            header_span: m.span,
            header_spans: spans
        }

      k when k in ["architecture", "arquitetura", "arch", "c4"] ->
        %{
          state
          | kind: :architecture,
            title: blank_to_nil(caps["title"]),
            header_span: m.span,
            header_spans: spans
        }

      other ->
        error(state, at.line, :unknown_kind, %{kind: other})
    end
  end

  @directions %{
    "horizontal" => :horizontal,
    "lr" => :horizontal,
    "rl" => :horizontal,
    "vertical" => :vertical,
    "tb" => :vertical,
    "td" => :vertical,
    "bt" => :vertical
  }

  # A última `direction` vence, como redeclarar um nó.
  defp put_direction(state, m, at) do
    value = m.caps["value"]

    case Map.fetch(@directions, String.downcase(value)) do
      {:ok, direction} -> %{state | direction: direction, direction_span: m.span}
      :error -> error(state, at.line, :unknown_direction, %{direction: value})
    end
  end

  defp put_node(state, m, at) do
    caps = m.caps
    id = caps["id"]
    kind = (blank_to_nil(caps["kind2"]) || caps["kind"]) |> String.downcase() |> node_kind()
    label = blank_to_nil(caps["label"]) || humanize(id)

    node = %Node{
      id: id,
      label: label,
      kind: kind,
      group: if(state.block == :group, do: state.block_label),
      line: at.line,
      span: m.span,
      spans: %{id: m.spans["id"], label: m.spans["label"], kind: m.spans["kind"]}
    }

    state
    |> declare_node(node)
    |> then(fn s ->
      if s.block == :group, do: %{s | block_nodes: s.block_nodes ++ [id]}, else: s
    end)
  end

  # `kind: x` aceita qualquer palavra; só as conhecidas viram átomo, o resto cai
  # em `component` — `String.to_atom/1` em texto do usuário vazaria átomos.
  @kind_atoms Map.new(@node_kinds, &{&1, String.to_atom(&1)})
  defp node_kind(kind), do: Map.get(@kind_atoms, kind, :component)

  defp put_edge(state, m, at) do
    caps = m.caps

    arrow =
      case caps["arrow"] do
        "->" -> :sync
        "-->" -> :return
        "->>" -> :async
        "-x" -> :fail
      end

    state = state |> ensure_node(caps["from"], at.line) |> ensure_node(caps["to"], at.line)
    {state, id} = next_id(state, "e")

    edge = %Edge{
      id: id,
      from: caps["from"],
      to: caps["to"],
      label: blank_to_nil(caps["label"]),
      arrow: arrow,
      line: at.line,
      span: m.span,
      spans: %{
        from: m.spans["from"],
        to: m.spans["to"],
        arrow: m.spans["arrow"],
        label: non_empty(m.spans["label"])
      }
    }

    state |> push_item(edge, at.line) |> Map.put(:edge_line, at.line)
  end

  # ── payload ───────────────────────────────────────────────────────────────

  defp close_payload(state, %{attached?: false} = open, _close_span, line) do
    %{error(state, open.line, :orphan_payload) | last_line: line}
  end

  defp close_payload(state, open, close_span, line) do
    state
    |> put_payload(dedent(open.lines), open.span, close_span, line)
    |> Map.put(:last_line, line)
  end

  defp attached?(state), do: not is_nil(state.edge_line) and state.edge_line == state.last_line

  # Vale só logo depois de uma mensagem (ou de outro payload dela): cola na
  # última mensagem da lista em que ela entrou. Vários `payload:` seguidos
  # viram várias linhas do mesmo payload.
  defp attach_payload(state, text, first, last, line) do
    if attached?(state),
      do: put_payload(state, text, first, last, line),
      else: error(state, line, :orphan_payload)
  end

  defp put_payload(state, text, first, last, line) do
    key = if state.block == :step, do: :block_items, else: :loose
    items = Map.fetch!(state, key)

    case List.last(items) do
      %Edge{} = edge ->
        payload = if edge.payload, do: edge.payload <> "\n" <> text, else: text

        spans =
          edge.spans
          |> Map.put_new(:payload, first)
          |> Map.put(:payload_end, last)

        updated = %{edge | payload: payload, spans: spans}

        state
        |> Map.put(key, List.replace_at(items, -1, updated))
        |> Map.put(:edge_line, line)

      _ ->
        error(state, line, :orphan_payload)
    end
  end

  # Tira a indentação comum e as linhas em branco das pontas: o payload fica
  # como foi escrito, só sem o recuo do bloco.
  defp dedent(lines) do
    indent =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(fn l -> byte_size(l) - byte_size(String.trim_leading(l)) end)
      |> Enum.min(fn -> 0 end)

    lines
    |> Enum.map(fn l ->
      if String.trim(l) == "", do: "", else: binary_part(l, indent, byte_size(l) - indent)
    end)
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp put_note(state, m, at) do
    caps = m.caps

    placement =
      case String.downcase(caps["placement"]) do
        "over" -> :over
        "left of" -> :left
        "right of" -> :right
      end

    targets = caps["targets"] |> String.split(",") |> Enum.map(&String.trim/1)
    state = Enum.reduce(targets, state, &ensure_node(&2, &1, at.line))
    {state, id} = next_id(state, "n")

    note = %Note{
      id: id,
      placement: placement,
      target_ids: targets,
      text: String.trim(caps["text"]),
      line: at.line,
      span: m.span,
      spans: %{
        placement: m.spans["placement"],
        targets: m.spans["targets"],
        text: non_empty(m.spans["text"])
      }
    }

    push_item(state, note, at.line)
  end

  defp put_pin(state, nil, at) do
    error(state, at.line, :invalid_layout_line, %{text: inspect(at.text)})
  end

  defp put_pin(state, m, at) do
    caps = m.caps

    pin = %Pin{
      id: caps["id"],
      x: String.to_integer(caps["x"]),
      y: String.to_integer(caps["y"]),
      line: at.line,
      span: m.span,
      spans: %{id: m.spans["id"], coords: m.spans["coords"]}
    }

    # A última posição de um mesmo id vence — igual a redeclarar um nó.
    %{state | pins: Enum.reject(state.pins, &(&1.id == pin.id)) ++ [pin]}
  end

  # ── blocos ────────────────────────────────────────────────────────────────

  defp open_block(%{block: nil} = state, type, m, at) do
    %{
      state
      | block: type,
        block_label: m.caps["label"],
        block_line: at.line,
        block_span: m.span,
        block_spans: %{label: m.spans["label"]},
        block_items: [],
        block_nodes: []
    }
  end

  defp open_block(state, _type, _m, at) do
    error(state, at.line, :nested_block)
  end

  defp open_layout(%{block: nil, layout_span: nil} = state, m, at) do
    %{state | block: :layout, block_line: at.line, layout_span: m.span}
  end

  defp open_layout(%{block: nil} = state, _m, at) do
    error(state, at.line, :duplicate_layout)
  end

  defp open_layout(state, m, at), do: open_block(state, :layout, m, at)

  defp close_block(%{block: nil} = state, at) do
    error(state, at.line, :unmatched_close)
  end

  defp close_block(%{block: :step} = state, at) do
    step = %Step{
      index: length(state.steps),
      label: state.block_label,
      items: state.block_items,
      line: state.block_line,
      span: state.block_span,
      end_span: end_span(at),
      spans: state.block_spans
    }

    %{state | steps: state.steps ++ [step]} |> reset_block()
  end

  defp close_block(%{block: :group} = state, at) do
    {state, id} = next_id(state, "g")

    group = %Group{
      id: id,
      label: state.block_label,
      node_ids: state.block_nodes,
      line: state.block_line,
      span: state.block_span,
      end_span: end_span(at),
      spans: state.block_spans
    }

    %{state | groups: state.groups ++ [group]} |> reset_block()
  end

  defp close_block(%{block: :layout} = state, at) do
    %{state | layout_end_span: end_span(at)} |> reset_block()
  end

  defp end_span(nil), do: nil
  defp end_span(at), do: Span.new(at.line, at.base - at.start + 1, at.base, 1)

  defp reset_block(state) do
    %{
      state
      | block: nil,
        block_label: nil,
        block_line: nil,
        block_span: nil,
        block_spans: %{},
        block_items: [],
        block_nodes: []
    }
  end

  defp close_dangling_blocks(%{raw: %{} = open} = state) do
    %{state | raw: nil}
    |> error(open.line, :unclosed_payload)
    |> close_dangling_blocks()
  end

  defp close_dangling_blocks(%{block: nil} = state), do: state

  defp close_dangling_blocks(state) do
    state
    |> error(state.block_line, :unclosed_block, %{block: to_string(state.block)})
    |> close_block(nil)
  end

  # ── finalização ───────────────────────────────────────────────────────────

  # Sem nenhum `step` explícito, cada mensagem vira seu próprio passo — assim
  # o usuário ganha uma animação decente só escrevendo setas.
  defp finalize(%{steps: [], loose: loose} = state) when loose != [] do
    steps =
      loose
      |> Enum.with_index()
      |> Enum.map(fn {item, i} ->
        %Step{index: i, label: auto_label(item), items: [item], line: item.line, implicit: true}
      end)

    build_ast(%{state | steps: steps, loose: []})
  end

  # Com steps explícitos, o que sobrou fora deles vira um passo inicial.
  defp finalize(%{loose: loose} = state) when loose != [] do
    setup = %Step{index: 0, label: "Contexto inicial", items: loose, line: 1, implicit: true}
    steps = [setup | Enum.map(state.steps, &%{&1 | index: &1.index + 1})]
    build_ast(%{state | steps: steps, loose: []})
  end

  defp finalize(state), do: build_ast(state)

  defp build_ast(state) do
    ast = %Ast{
      kind: state.kind,
      title: state.title,
      direction: state.direction,
      direction_span: state.direction_span,
      nodes: state.nodes,
      groups: state.groups,
      steps: state.steps,
      pins: state.pins,
      span: state.header_span,
      spans: state.header_spans,
      layout_span: state.layout_span,
      layout_end_span: state.layout_end_span
    }

    %{state | ast: ast}
  end

  defp auto_label(%Edge{} = e), do: e.label || "#{label_of(e.from)} → #{label_of(e.to)}"
  defp auto_label(%Note{} = n), do: n.text

  defp label_of(id), do: humanize(id)

  # ── helpers ───────────────────────────────────────────────────────────────

  defp push_item(%{block: :step} = state, item, _line) do
    %{state | block_items: state.block_items ++ [item]}
  end

  defp push_item(%{block: :group} = state, _item, line) do
    error(state, line, :message_in_group)
  end

  defp push_item(state, item, _line), do: %{state | loose: state.loose ++ [item]}

  defp declare_node(state, %Node{id: id} = node) do
    if MapSet.member?(state.node_ids, id) do
      # Redeclarar substitui: permite `api -> db` primeiro e `database db "PG"` depois.
      nodes =
        Enum.map(state.nodes, fn
          %Node{id: ^id} = existing -> %{node | group: node.group || existing.group}
          other -> other
        end)

      %{state | nodes: nodes}
    else
      %{state | nodes: state.nodes ++ [node], node_ids: MapSet.put(state.node_ids, id)}
    end
  end

  # Nós usados em setas sem declaração explícita são criados automaticamente.
  defp ensure_node(state, id, line) do
    if MapSet.member?(state.node_ids, id) do
      state
    else
      declare_node(state, %Node{
        id: id,
        label: humanize(id),
        kind: :participant,
        group: nil,
        line: line
      })
    end
  end

  defp next_id(state, prefix) do
    n = state.counter + 1
    {%{state | counter: n}, "#{prefix}#{n}"}
  end

  # O texto de cada erro em português; a interface traduz pelo `code`.
  @messages %{
    pin_outside_layout: "posição fora de um bloco `layout { }`: %{text}",
    unknown_line: "não entendi esta linha: %{text}",
    unknown_kind: "tipo de diagrama desconhecido: %{kind} (use sequence ou architecture)",
    unknown_direction: "direção desconhecida: %{direction} (use horizontal ou vertical)",
    invalid_layout_line: "dentro de `layout` só cabem linhas `id at (x, y)`: %{text}",
    nested_block: "blocos aninhados não são suportados (feche o bloco anterior com `}`)",
    duplicate_layout: "só pode haver um bloco `layout` por diagrama",
    unmatched_close: "`}` sem bloco aberto correspondente",
    unclosed_block: "bloco `%{block}` aberto aqui nunca foi fechado com `}`",
    message_in_group: "mensagens não podem ficar dentro de um `group` — use um `step`",
    orphan_payload: "`payload` precisa vir logo abaixo de uma mensagem (`a -> b : …`)",
    unclosed_payload: ~s(payload aberto aqui nunca foi fechado com """)
  }

  defp error(state, line, code, bindings \\ %{}) do
    message =
      Enum.reduce(bindings, Map.fetch!(@messages, code), fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", value)
      end)

    error = %ParseError{line: line, message: message, code: code, bindings: bindings}
    %{state | errors: [error | state.errors]}
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  defp non_empty(%Span{length: 0}), do: nil
  defp non_empty(span), do: span

  defp humanize(id), do: Text.humanize(id)

  # Remove comentários `#` e `//`, respeitando aspas.
  defp strip_comment(line) do
    line |> String.graphemes() |> do_strip(false, [])
  end

  defp do_strip([], _quoted?, acc), do: acc |> Enum.reverse() |> Enum.join()
  defp do_strip(["\"" | rest], quoted?, acc), do: do_strip(rest, not quoted?, ["\"" | acc])
  defp do_strip(["#" | _rest], false, acc), do: acc |> Enum.reverse() |> Enum.join()
  defp do_strip(["/", "/" | _rest], false, acc), do: acc |> Enum.reverse() |> Enum.join()
  defp do_strip([c | rest], quoted?, acc), do: do_strip(rest, quoted?, [c | acc])
end
