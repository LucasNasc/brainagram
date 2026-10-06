defmodule Brainagram.Test.DslGenerators do
  @moduledoc """
  Geradores de fontes da DSL para os testes de propriedade (spec 001, §12).

  Geram texto **válido e bagunçado de propósito**: comentários no fim da linha
  e em linhas soltas, indentação irregular, espaços extras, `\\r\\n`, arquivo
  com e sem quebra final. É nesse texto que o editor cirúrgico precisa provar
  que não mexe no que não foi apontado.
  """

  import StreamData
  import ExUnitProperties, only: [gen: 2]

  alias Brainagram.Domain.Diagramming.Dsl.{Ast, Parser, Span}

  @ids ~w(api db web fila worker cache auth pg s3 user billing mq)
  @kinds ~w(actor participant database queue service component external system node boundary)
  @arrows ~w(-> --> ->> -x)

  @doc """
  Um fonte válido. Opções: `pins: false` para não gerar bloco `layout`;
  `kind: "architecture"` (ou outro) para fixar o tipo do cabeçalho.
  """
  def source(opts \\ []) do
    gen all(
          ids <- uniq_list_of(member_of(@ids), min_length: 2, max_length: 6, max_tries: 1_000),
          extra <- list_of(member_of(~w(ext1 ext2 ext3)), max_length: 2),
          kind <-
            if(Keyword.has_key?(opts, :kind),
              do: constant(opts[:kind]),
              else: member_of(["sequence", "architecture", "arquitetura", nil])
            ),
          title <- one_of([constant(nil), label()]),
          kinds <- list_of(member_of(@kinds), length: length(ids)),
          labels <- list_of(one_of([constant(nil), label()]), length: length(ids)),
          group_split <- integer(0..length(ids)),
          group_names <- uniq_list_of(label(), length: 2, max_tries: 1_000),
          items <- list_of(item(ids ++ Enum.uniq(extra)), min_length: 1, max_length: 8),
          mode <- member_of([:loose, :steps, :mixed]),
          step_names <- list_of(label(), length: 3),
          pin_ids <-
            if(Keyword.get(opts, :pins, true),
              do: uniq_list_of(member_of(ids), max_length: 2, max_tries: 1_000),
              else: constant([])
            ),
          coords <- list_of(tuple({integer(0..900), integer(0..700)}), length: 2),
          style <- style()
        ) do
      decls =
        Enum.zip([ids, kinds, labels])
        |> Enum.map(fn {id, k, l} -> if l, do: ~s(#{k} #{id} "#{l}"), else: "#{k} #{id}" end)

      {loose_decls, grouped} = Enum.split(decls, group_split)
      {g1, g2} = Enum.split(grouped, div(length(grouped), 2))

      groups =
        [{Enum.at(group_names, 0), g1}, {Enum.at(group_names, 1), g2}]
        |> Enum.reject(fn {_name, members} -> members == [] end)
        |> Enum.flat_map(fn {name, members} ->
          [~s(group "#{name}" {)] ++ Enum.map(members, &(style.indent <> &1)) ++ ["}"]
        end)

      header =
        case {kind, title} do
          {nil, _} -> []
          {k, nil} -> ["diagram #{k}"]
          {k, t} -> [~s(diagram #{k} "#{t}")]
        end

      body = steps_block(items, mode, step_names, style.indent)

      layout =
        case pin_ids do
          [] ->
            []

          pins ->
            lines =
              pins
              |> Enum.zip(coords)
              |> Enum.map(fn {id, {x, y}} -> "#{style.indent}#{id} at (#{x}, #{y})" end)

            ["layout {"] ++ lines ++ ["}"]
        end

      (header ++ [""] ++ loose_decls ++ [""] ++ groups ++ [""] ++ body ++ [""] ++ layout)
      |> decorate(style)
    end
  end

  @doc "Um fonte já parseado — o `ast_generator()` da spec."
  def ast do
    map(source(), fn src ->
      {:ok, ast} = Parser.parse(src)
      ast
    end)
  end

  @doc "`{fonte, span, texto_novo}` com o span tirado de um campo editável real."
  def edit do
    gen all(
          src <- source(),
          {:ok, ast} = Parser.parse(src),
          spans = editable_spans(ast),
          spans != [],
          span <- member_of(spans),
          text <- string(:alphanumeric, max_length: 10)
        ) do
      {src, span, text}
    end
  end

  @doc "`{fonte, id_de_nó_não_fixado, {x, y}}`."
  def drag do
    gen all(
          src <- source(),
          {:ok, ast} = Parser.parse(src),
          pinned = MapSet.new(ast.pins, & &1.id),
          free = Enum.reject(ast.nodes, &MapSet.member?(pinned, &1.id)),
          free != [],
          node <- member_of(free),
          x <- integer(0..1200),
          y <- integer(0..900)
        ) do
      {src, node.id, {x, y}}
    end
  end

  @doc "Todos os spans de campo editável da AST, com o texto que cada um deve cobrir."
  def expected_spans(%Ast{} = ast) do
    header = [{ast.spans[:title], ast.title}]

    nodes =
      Enum.flat_map(ast.nodes, fn n ->
        [{n.spans[:id], n.id}, {n.spans[:label], n.label}, {n.spans[:kind], nil}]
      end)

    groups = Enum.map(ast.groups, &{&1.spans[:label], &1.label})

    steps = Enum.map(ast.steps, &{&1.spans[:label], &1.label})

    items =
      ast.steps
      |> Enum.flat_map(& &1.items)
      |> Enum.flat_map(fn
        %{from: from, to: to, label: label, arrow: arrow} = e ->
          [
            {e.spans[:from], from},
            {e.spans[:to], to},
            {e.spans[:label], label},
            {e.spans[:arrow], arrow_text(arrow)}
          ]

        note ->
          [{note.spans[:text], note.text}]
      end)

    pins = Enum.map(ast.pins, &{&1.spans[:id], &1.id})

    (header ++ nodes ++ groups ++ steps ++ items ++ pins)
    |> Enum.filter(fn {span, _} -> match?(%Span{}, span) end)
  end

  def editable_spans(ast), do: ast |> expected_spans() |> Enum.map(&elem(&1, 0))

  defp arrow_text(:sync), do: "->"
  defp arrow_text(:return), do: "-->"
  defp arrow_text(:async), do: "->>"
  defp arrow_text(:fail), do: "-x"

  # ── partes ────────────────────────────────────────────────────────────────

  defp label do
    [?a..?z, ?A..?Z, ?0..?9, [?\s, ?ç, ?ã, ?é, ?-, ?(, ?)]]
    |> Enum.concat()
    |> string(min_length: 1, max_length: 14)
    |> filter(&(String.trim(&1) != ""))
    |> map(&String.trim/1)
  end

  defp message do
    [?a..?z, ?A..?Z, ?0..?9, [?\s, ?/, ?:, ?{, ?}, ?ç, ?é]]
    |> Enum.concat()
    |> string(min_length: 1, max_length: 16)
    |> map(&(&1 |> String.replace("//", "/") |> String.trim()))
  end

  defp item(ids) do
    one_of([
      gen all(
            from <- member_of(ids),
            to <- member_of(ids),
            arrow <- member_of(@arrows),
            text <- one_of([constant(nil), message()]),
            payload <- one_of([constant(nil), constant(nil), message()])
          ) do
        base = "#{from} #{arrow} #{to}"
        line = if text in [nil, ""], do: base, else: "#{base} : #{text}"
        # payload de uma linha, recuado sob a mensagem (vira uma linha própria
        # em `lines/2`, então passa pelos enfeites de estilo como as outras)
        if payload in [nil, ""], do: line, else: line <> "\n  payload: " <> payload
      end,
      gen all(
            targets <-
              uniq_list_of(member_of(ids), min_length: 1, max_length: 2, max_tries: 1_000),
            placement <- member_of(["over", "left of", "right of"]),
            text <- label()
          ) do
        "note #{placement} #{Enum.join(targets, ", ")} : #{text}"
      end
    ])
  end

  defp steps_block(items, :loose, _names, _indent), do: Enum.flat_map(items, &lines(&1, ""))

  defp steps_block(items, :steps, names, indent) do
    items
    |> Enum.chunk_every(max(div(length(items) + 1, 2), 1))
    |> Enum.zip(names)
    |> Enum.flat_map(fn {chunk, name} ->
      [~s(step "#{name}" {)] ++ Enum.flat_map(chunk, &lines(&1, indent)) ++ ["}"]
    end)
  end

  defp steps_block([first | rest], :mixed, names, indent) do
    lines(first, "") ++ steps_block(rest, :steps, names, indent)
  end

  # Um item pode ter mais de uma linha (a mensagem e o payload dela).
  defp lines(item, indent), do: item |> String.split("\n") |> Enum.map(&(indent <> &1))

  # ── bagunça controlada ────────────────────────────────────────────────────

  defp style do
    gen all(
          indent <- member_of(["  ", "    ", "\t", "   "]),
          newline <- member_of(["\n", "\n", "\r\n"]),
          trailing? <- boolean(),
          comment_every <- integer(0..4)
        ) do
      %{indent: indent, newline: newline, trailing?: trailing?, comment_every: comment_every}
    end
  end

  defp decorate(lines, style) do
    lines
    |> Enum.with_index()
    |> Enum.flat_map(fn {line, i} ->
      commented =
        cond do
          style.comment_every == 0 or line == "" ->
            [line]

          rem(i, style.comment_every + 2) == 0 ->
            ["# comentário solto #{i}", line]

          rem(i, style.comment_every + 3) == 0 and not String.ends_with?(line, "{") ->
            [line <> "   # nota #{i}"]

          true ->
            [line]
        end

      commented
    end)
    |> Enum.join(style.newline)
    |> then(fn text -> if style.trailing?, do: text <> style.newline, else: text end)
  end
end
