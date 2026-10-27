defmodule Brainagram.Domain.Diagramming.Import.MermaidFlowchart do
  @moduledoc """
  `flowchart` / `graph` do Mermaid → diagrama de arquitetura.

  Cobertura:

    * nós em todas as formas clássicas (`A[x]`, `A(x)`, `A([x])`, `A[[x]]`,
      `A((x))`, `A{x}`, `A{{x}}`, `A>x]`, `A[/x/]`…) e na sintaxe nova
      `A@{ shape: cyl, label: "x" }`; o cilindro (`A[(x)]`) é `database` e o
      losango (`A{x}`, `shape: diamond`) é `decision`;
    * o tipo dos outros nós vem do nome da classe (`classDef queue …` +
      `class A queue` ou `A:::queue`), depois do rótulo ("fila", "Redis"…), e
      por fim `service`;
    * `subgraph … end` vira `group` (aninhados: vale o de dentro);
    * setas `-->`, `==>`, `--o` (síncronas), `-.->` (assíncrona), `--x`
      (falha), com texto em `-->|x|`, `-- x -->`, `-. x .->`, `== x ==>`,
      em cadeia (`A --> B --> C`) e em leque (`A & B --> C`);
    * `title` do front matter; `<br/>` no rótulo de um nó vira ` · `;
    * a direção do cabeçalho: `LR` e `RL` viram `direction horizontal`;
      `TD`, `TB` e `BT` ficam no padrão, em pé.

  Cada seta é um passo, na ordem do texto. Ficam no comentário do topo:
  ligações sem ponta (`---`) e de mão dupla (`<-->`), convertidas num sentido
  só; setas de ou para um `subgraph`; linhas não reconhecidas. Aparência
  (`style`, `linkStyle`, cores de `classDef`, `click`, `direction`) é
  ignorada sem aviso.
  """

  alias Brainagram.Domain.Diagramming.Import.Builder

  # {abre, fechamentos, tipo}: os mais longos antes, para `((` não ser lido
  # como `(`. Com dois fechamentos possíveis (`[/x/]`, `[/x\]`), vale o mais
  # próximo: o outro pode ser de um nó adiante na mesma linha.
  @shapes [
    {"(((", [")))"], nil},
    {"([", ["])"], nil},
    {"((", ["))"], nil},
    {"[(", [")]"], :database},
    {"[[", ["]]"], nil},
    {"[/", ["/]", "\\]"], nil},
    {"[\\", ["\\]", "/]"], nil},
    {"{{", ["}}"], nil},
    {"[", ["]"], nil},
    {"(", [")"], nil},
    {"{", ["}"], :decision},
    {">", ["]"], nil}
  ]

  @decision_shapes ~w(diamond diam decision question)
  @storage_shapes ~w(cyl cylinder database db das disk lin-cyl h-cyl horizontal-cylinder lined-cylinder stored-data bow-rect)

  @class_kinds [
    {~w(queue queues fila filas topic topics topico broker bus mq stream streams), :queue},
    {~w(store stores storage db database databases data datastore banco cache persistence),
     :database},
    {~w(ext external externo externa externos vendor saas thirdparty third 3p), :external},
    {~w(actor actors user users person people client clients cliente usuario), :actor},
    {~w(svc service services servico app api worker microservice), :service}
  ]

  @re_id ~r/^(?<id>[\p{L}\p{N}_][\p{L}\p{N}_.\-]*?)(?=[\s\[\(\{>@&:;<~=]|-[-.=>]|$)/u
  @re_new_shape ~r/^@\{(?<body>[^}]*)\}/
  @re_class_suffix ~r/^:::(?<cls>[\w\-]+)/u
  @re_amp ~r/^\s*&\s*/
  @re_link_id ~r/^[\w\-]+@(?=[-=.<~])/u
  @re_text_link ~r/^(?<lh><)?(?<open>--|==|-\.)\s+(?<text>.+?)\s*(?<close>-{2,}|={2,}|\.+-+)(?<head>>|[ox](?=\s|$))?/u
  @re_link ~r/^(?<lh><)?(?<shaft>~{3,}|={2,}|-\.+-|-{2,})(?<head>>|[ox](?=\s|$|\|))?/
  @re_link_label ~r/^\s*\|(?<text>[^|]*)\|/

  @re_subgraph_bracket ~r/^subgraph\s+(?<id>[^\s\[]+)\s*\[(?<title>.*)\]$/i
  @re_subgraph_quoted ~r/^subgraph\s+"(?<title>[^"]*)"$/i
  @re_subgraph ~r/^subgraph(?:\s+(?<title>.+))?$/i
  @re_class ~r/^class\s+(?<ids>\S+(?:\s*,\s*\S+)*)\s+(?<cls>[\w\-]+)$/u
  @re_header ~r/^\S+(?:\s+(?<dir>TB|TD|BT|RL|LR)\b)?\s*;?\s*/i
  @silent ~r/^(classDef|style|linkStyle|click|direction|accTitle|accDescr|title)\b/i

  @doc """
  Continua a conversão a partir do cabeçalho. `b` já traz o título do front
  matter; `header` é a linha `flowchart LR` (que pode trazer comandos depois de
  `;`) e `body` as linhas seguintes, já numeradas e sem espaços nas pontas.
  """
  @spec convert(Builder.t(), {String.t(), pos_integer()}, [{String.t(), pos_integer()}]) ::
          {:ok, %{source: String.t(), warnings: list()}} | {:error, term()}
  def convert(b, {header, hn}, body) do
    rest = Regex.replace(@re_header, header, "")
    lines = if rest == "", do: body, else: [{rest, hn} | body]
    b = Builder.direction(b, direction(header))

    lines
    |> Enum.flat_map(fn {text, n} -> text |> statements() |> Enum.map(&{&1, n}) end)
    |> Enum.reduce(
      %{
        b: Builder.kind(b, :architecture),
        stack: [],
        subgraphs: MapSet.new(),
        nodes: %{},
        classes: %{},
        skipping: false
      },
      &line/2
    )
    |> finish()
  end

  # `LR` e `RL` deitam o diagrama; `TB`, `TD`, `BT` ou nenhuma, em pé.
  defp direction(header) do
    case Regex.named_captures(@re_header, header) do
      %{"dir" => dir} when dir != "" ->
        if String.upcase(dir) in ["LR", "RL"], do: :horizontal, else: :vertical

      _ ->
        :vertical
    end
  end

  # ── linha a linha ─────────────────────────────────────────────────────────

  # `accDescr { … }` de várias linhas: pula até o `}`.
  defp line({text, _n}, %{skipping: true} = st),
    do: if(String.ends_with?(text, "}"), do: %{st | skipping: false}, else: st)

  defp line({"", _n}, st), do: st
  defp line({"%%" <> _, _n}, st), do: st

  defp line({text, n}, st) do
    cond do
      text =~ ~r/^end$/i ->
        close(st, n)

      text =~ ~r/^subgraph\b/i ->
        open(st, text)

      text =~ ~r/^accDescr\s*\{/i and not String.ends_with?(text, "}") ->
        %{st | skipping: true}

      caps = Regex.named_captures(@re_class, text) ->
        classes(st, caps)

      text =~ @silent ->
        st

      true ->
        case statement(text) do
          {:ok, groups, links} -> apply_statement(st, groups, links, n)
          :error -> warn(st, n, "linha não reconhecida: `#{text}`")
        end
    end
  end

  # `A --> B; B --> C` são dois comandos; `;` dentro de aspas é texto. Em
  # comentário e estilo (`fill:#f9f;stroke:#333`) o `;` é do próprio comando.
  defp statements(text) do
    if String.starts_with?(text, "%%") or text =~ @silent or text =~ @re_class,
      do: [text],
      else: split_statements(text)
  end

  defp split_statements(text) do
    text
    |> String.graphemes()
    |> Enum.reduce({[], "", false}, fn
      "\"", {acc, cur, q} -> {acc, cur <> "\"", not q}
      ";", {acc, cur, false} -> {[cur | acc], "", false}
      c, {acc, cur, q} -> {acc, cur <> c, q}
    end)
    |> then(fn {acc, cur, _} -> Enum.reverse([cur | acc]) end)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # ── subgraphs ─────────────────────────────────────────────────────────────

  defp open(st, text) do
    {id, title} =
      cond do
        m = Regex.named_captures(@re_subgraph_bracket, text) ->
          {m["id"], plain(m["title"])}

        m = Regex.named_captures(@re_subgraph_quoted, text) ->
          {m["title"], plain(m["title"])}

        m = Regex.named_captures(@re_subgraph, text) ->
          title = String.trim(m["title"] || "")
          {blank(title), blank(plain(title))}
      end

    subgraphs = if id, do: MapSet.put(st.subgraphs, id), else: st.subgraphs
    stack = [title | st.stack]
    %{st | stack: stack, subgraphs: subgraphs, b: box(st.b, stack)}
  end

  defp close(%{stack: []} = st, n), do: warn(st, n, "`end` sem `subgraph` aberto")
  defp close(%{stack: [_ | rest]} = st, _n), do: %{st | stack: rest, b: box(st.b, rest)}

  # Quem aparece agora entra no subgraph com título mais de dentro.
  defp box(b, stack) do
    case Enum.find(stack, & &1) do
      nil -> Builder.close_box(b)
      title -> Builder.open_box(b, title)
    end
  end

  # ── classes ───────────────────────────────────────────────────────────────

  defp classes(st, caps) do
    ids = caps["ids"] |> String.split(",") |> Enum.map(&String.trim/1)
    Enum.reduce(ids, st, &put_class(&2, &1, caps["cls"]))
  end

  defp put_class(st, _name, nil), do: st
  defp put_class(st, _name, ""), do: st

  defp put_class(st, name, cls) do
    case class_kind(cls) do
      nil -> st
      kind -> %{st | classes: Map.put(st.classes, name, kind)}
    end
  end

  # `queue`, `extSystem`, `data-store`: qualquer pedaço do nome que seja uma
  # palavra conhecida decide o tipo.
  defp class_kind(cls) do
    tokens =
      cls
      |> String.split(~r/[-_\s]+|(?<=[a-z])(?=[A-Z])/)
      |> Enum.map(&String.downcase/1)

    Enum.find_value(@class_kinds, fn {words, kind} ->
      if Enum.any?(tokens, &(&1 in words)), do: kind
    end)
  end

  # ── comandos: nós e setas ─────────────────────────────────────────────────

  defp apply_statement(st, groups, links, n) do
    st = groups |> List.flatten() |> Enum.reduce(st, &touch/2)

    groups
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.zip(links)
    |> Enum.reduce(st, fn {[froms, tos], link}, st -> connect(st, froms, tos, link, n) end)
  end

  # Primeira vez que o nó aparece: entra no Builder (e no subgraph aberto). Das
  # outras, só atualiza rótulo, forma e classe — o tipo final sai no `finish`.
  defp touch(node, st) do
    st = put_class(st, node.name, node.class)

    cond do
      subgraph_ref?(st, node.name) ->
        st

      Map.has_key?(st.nodes, node.name) ->
        update_in(st.nodes[node.name], fn old ->
          %{label: node.label || old.label, shape: node.shape || old.shape}
        end)

      true ->
        b = Builder.participant(st.b, node.name, node.label, :service)
        %{st | b: b, nodes: Map.put(st.nodes, node.name, %{label: node.label, shape: node.shape})}
    end
  end

  defp subgraph_ref?(st, name),
    do: MapSet.member?(st.subgraphs, name) and not Map.has_key?(st.nodes, name)

  defp connect(st, _froms, _tos, %{style: :invisible}, _n), do: st

  defp connect(st, froms, tos, link, n) do
    pairs = for f <- froms, t <- tos, do: {f.name, t.name}

    case Enum.find(pairs, fn {f, t} -> subgraph_ref?(st, f) or subgraph_ref?(st, t) end) do
      {f, t} ->
        group = if subgraph_ref?(st, f), do: f, else: t
        warn(st, n, "seta para o subgraph `#{group}` — ligue a um nó de dentro dele")

      nil ->
        st = link_warning(st, link, pairs, n)
        arrow = arrow(link)
        text = edge_text(link.text)

        b =
          Enum.reduce(pairs, st.b, fn {f, t}, b -> Builder.message(b, f, t, arrow, text) end)

        %{st | b: b}
    end
  end

  defp arrow(%{head: :x}), do: :fail
  defp arrow(%{style: :dotted}), do: :async
  defp arrow(_link), do: :sync

  defp link_warning(st, %{both: true, raw: raw}, [{f, t} | _], n),
    do:
      warn(
        st,
        n,
        "seta de mão dupla `#{raw}` entre #{f} e #{t} — convertida só no sentido de ida"
      )

  defp link_warning(st, %{head: :none, raw: raw}, [{f, t} | _], n),
    do: warn(st, n, "ligação sem seta `#{raw}` — convertida como #{f} → #{t}")

  defp link_warning(st, _link, _pairs, _n), do: st

  defp warn(st, n, text), do: %{st | b: Builder.warn(st.b, n, text)}

  # O tipo de cada nó só se decide no fim: a classe costuma vir depois.
  defp finish(st) do
    b = Builder.close_box(st.b)

    st.nodes
    |> Enum.reduce(b, fn {name, node}, b ->
      # o losango é pergunta, qualquer que seja a classe
      kind =
        if node.shape == :decision,
          do: :decision,
          else:
            Map.get(st.classes, name) || node.shape ||
              Builder.guess_kind(node.label || name, :service)

      Builder.participant(b, name, node.label, kind)
    end)
    |> Builder.finish("Mermaid")
  end

  # ── gramática de um comando ───────────────────────────────────────────────

  # `A & B --> C -->|x| D` → {:ok, [[A, B], [C], [D]], [link, link]}
  defp statement(text) do
    with {:ok, group, rest} <- node_group(text), do: links(rest, [group], [])
  end

  defp links(rest, groups, acc) do
    case String.trim_leading(rest) do
      "" ->
        {:ok, Enum.reverse(groups), Enum.reverse(acc)}

      rest ->
        with {:ok, link, rest} <- link(rest),
             {:ok, group, rest} <- node_group(String.trim_leading(rest)) do
          links(rest, [group | groups], [link | acc])
        end
    end
  end

  defp node_group(text) do
    with {:ok, node, rest} <- parse_node(text) do
      case take(@re_amp, rest) do
        {_, rest} ->
          with {:ok, more, rest} <- node_group(rest), do: {:ok, [node | more], rest}

        nil ->
          {:ok, [node], rest}
      end
    end
  end

  defp parse_node(text) do
    case take(@re_id, text) do
      {%{"id" => id}, rest} ->
        {label, shape, rest} = node_shape(rest)

        {class, rest} =
          case take(@re_class_suffix, rest) do
            {%{"cls" => cls}, rest} -> {cls, rest}
            nil -> {nil, rest}
          end

        {:ok, %{name: id, label: label, shape: shape, class: class}, rest}

      nil ->
        :error
    end
  end

  defp node_shape(rest) do
    case take(@re_new_shape, rest) do
      {%{"body" => body}, rest} ->
        {new_shape_label(body), new_shape_kind(body), rest}

      nil ->
        Enum.find_value(@shapes, {nil, nil, rest}, fn {open, closers, kind} ->
          with true <- String.starts_with?(rest, open),
               {label, rest} <- shape_label(drop(rest, open), closers) do
            {plain(label), kind, rest}
          else
            _ -> nil
          end
        end)
    end
  end

  # Rótulo entre aspas pode ter o fechamento dentro (`A["x]"]`); sem aspas,
  # vai até o primeiro fechamento.
  defp shape_label(inner, closers) do
    case Regex.run(~r/^\s*"([^"]*)"\s*/u, inner) do
      [m, label] ->
        rest = drop(inner, m)

        case Enum.find(closers, &String.starts_with?(rest, &1)) do
          nil -> nil
          close -> {"\"" <> label <> "\"", drop(rest, close)}
        end

      nil ->
        closers
        |> Enum.map(&:binary.match(inner, &1))
        |> Enum.reject(&(&1 == :nomatch))
        |> Enum.min_by(fn {i, _len} -> i end, fn -> nil end)
        |> case do
          {i, len} ->
            {binary_part(inner, 0, i), binary_part(inner, i + len, byte_size(inner) - i - len)}

          nil ->
            nil
        end
    end
  end

  defp new_shape_label(body) do
    case Regex.run(~r/label\s*:\s*(?:"([^"]*)"|([^,}]+))/u, body) do
      [_, quoted] -> plain(quoted)
      [_, "", bare] -> plain(bare)
      nil -> nil
    end
  end

  defp new_shape_kind(body) do
    case Regex.run(~r/shape\s*:\s*"?([\w\-]+)/u, body) do
      [_, shape] ->
        shape = String.downcase(shape)

        cond do
          shape in @storage_shapes -> :database
          shape in @decision_shapes -> :decision
          true -> nil
        end

      nil ->
        nil
    end
  end

  defp link(text) do
    text =
      case take(@re_link_id, text) do
        {_, rest} -> rest
        nil -> text
      end

    cond do
      parsed = take(@re_text_link, text) ->
        {caps, rest} = parsed
        shaft = caps["open"] <> caps["close"]

        {:ok, link(caps, shaft, caps["text"], raw(caps, caps["open"] <> " … " <> caps["close"])),
         rest}

      parsed = take(@re_link, text) ->
        {caps, rest} = parsed

        # `--` e `==` sem ponta só existem como abertura de `-- texto -->`.
        if caps["shaft"] in ["--", "=="] and caps["head"] == "" do
          :error
        else
          {label, rest} =
            case take(@re_link_label, rest) do
              {%{"text" => t}, rest} -> {t, rest}
              nil -> {nil, rest}
            end

          {:ok, link(caps, caps["shaft"], label, raw(caps, caps["shaft"])), rest}
        end

      true ->
        :error
    end
  end

  defp link(caps, shaft, text, raw) do
    style =
      cond do
        String.contains?(shaft, "~") -> :invisible
        String.contains?(shaft, ".") -> :dotted
        String.contains?(shaft, "=") -> :thick
        true -> :solid
      end

    head =
      case caps["head"] do
        ">" -> :arrow
        "x" -> :x
        "o" -> :circle
        _ -> :none
      end

    %{style: style, head: head, both: caps["lh"] == "<" and head != :none, text: text, raw: raw}
  end

  defp raw(caps, shaft), do: caps["lh"] <> shaft <> caps["head"]

  # ── texto ─────────────────────────────────────────────────────────────────

  # Rótulo de nó: uma linha só, sem HTML nem Markdown, sem aspas duplas (que
  # fechariam o `"…"` da DSL).
  defp plain(nil), do: nil

  defp plain(text) do
    text
    |> decode()
    |> String.replace(~r/<br\s*\/?>/i, " · ")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("\"", "'")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> blank()
  end

  # Texto de seta: o Builder já cuida de `#`, `//` e `<br>`.
  defp edge_text(nil), do: nil

  defp edge_text(text) do
    text
    |> decode()
    |> String.replace(~r/<br\s*\/?>/i, " ")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
    |> blank()
  end

  # Aspas de fora, string Markdown (`"`**x**`"`) e entidades (`#quot;`, `#35;`).
  defp decode(text) do
    text
    |> String.trim()
    |> unwrap("\"")
    |> unwrap("`")
    |> String.replace(~r/\*\*|__/, "")
    |> String.replace(~r/#(\d+);/, fn m ->
      [_, code] = Regex.run(~r/#(\d+);/, m)
      <<String.to_integer(code)::utf8>>
    end)
    |> String.replace(~r/[#&](quot|amp|lt|gt|nbsp);/, fn m ->
      case String.slice(m, 1..-2//1) do
        "quot" -> "'"
        "amp" -> "&"
        "lt" -> "<"
        "gt" -> ">"
        "nbsp" -> " "
      end
    end)
  end

  defp unwrap(text, mark) do
    if String.length(text) >= 2 and String.starts_with?(text, mark) and
         String.ends_with?(text, mark),
       do: text |> String.slice(1..-2//1) |> String.trim(),
       else: text
  end

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(text), do: text

  # ── utilitários ───────────────────────────────────────────────────────────

  # Casa `re` (ancorada no começo) e devolve {capturas, o que sobrou}.
  defp take(re, text) do
    case Regex.run(re, text, return: :index, capture: :first) do
      [{0, len}] ->
        {Regex.named_captures(re, text), binary_part(text, len, byte_size(text) - len)}

      _ ->
        nil
    end
  end

  defp drop(text, prefix),
    do: binary_part(text, byte_size(prefix), byte_size(text) - byte_size(prefix))
end
