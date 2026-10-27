defmodule Brainagram.Domain.Diagramming.Authoring do
  @moduledoc """
  Autoria pelo canvas: cada gesto vira uma edição cirúrgica do texto.

  O canvas é uma projeção editável da DSL (spec 001, §3). Nada fica guardado
  "só no visual": arrastar, renomear, conectar ou apagar termina aqui, como
  `texto -> texto`, e o texto novo é compilado como qualquer outro.

  Cada operação:

    1. faz o parse do fonte atual (fonte inválido não é editável pelo canvas —
       não há como saber onde as coisas estão);
    2. localiza o alvo pelos `%Span{}` da AST e aplica o **menor patch** com
       `Dsl.Editor` — comentários, alinhamento e ordem ficam intactos;
    3. valida o resultado. Se o patch produzir um fonte inválido, ele é
       descartado e nada é aplicado (spec 001, §10).

  Devolve `{:ok, fonte}` ou, quando o gesto cria algo que a interface precisa
  apontar em seguida (o nó novo para renomear, a seta nova para rotular),
  `{:ok, fonte, meta}`.

  Tudo aqui é puro. Quem persiste é o agregado (`Diagram.apply_edit/2`), pelos
  comandos da camada de aplicação; quem só quer pré-visualizar é a query
  `EditSource`.
  """

  alias Brainagram.Domain.Diagramming.Dsl.{
    Ast,
    Edge,
    Editor,
    Group,
    Node,
    Note,
    Parser,
    Printer,
    Span
  }

  alias Brainagram.Domain.Diagramming.Layout.{Hints, Untangle}

  @type point :: {integer(), integer()}
  @type result :: {:ok, String.t()} | {:ok, String.t(), map()} | {:error, term()}

  @arrows %{"sync" => :sync, "return" => :return, "async" => :async, "fail" => :fail}
  @kinds Map.new(Parser.node_kinds(), &{&1, String.to_atom(&1)})

  # ── rótulos e setas (fase B) ──────────────────────────────────────────────

  @doc "Troca o rótulo de um nó — só os bytes entre as aspas."
  @spec rename_node_label(String.t(), String.t(), String.t()) :: result()
  def rename_node_label(source, node_id, label) do
    edit(source, fn ast ->
      with {:ok, node} <- find_node(ast, node_id),
           {:ok, label} <- clean_label(label) do
        cond do
          span = node.spans[:label] ->
            {:ok, Editor.replace(source, span, label)}

          node.span ->
            {:ok, Editor.replace(source, node.spans.id, ~s(#{node.id} "#{label}"))}

          # nó que só existia por aparecer numa seta: ganha uma declaração
          true ->
            {:ok, declare(source, ast, ~s(#{node.kind} #{node.id} "#{label}"), nil)}
        end
      end
    end)
  end

  @doc "Troca o texto depois de `:` numa seta. Rótulo vazio remove o `: …`."
  @spec relabel_edge(String.t(), String.t(), String.t() | nil) :: result()
  def relabel_edge(source, edge_id, label) do
    edit(source, fn ast ->
      with {:ok, edge} <- find_edge(ast, edge_id),
           {:ok, label} <- clean_edge_label(label) do
        tail = range(source, Span.stop(edge.spans.to), Span.stop(edge.span))

        cond do
          label == "" -> {:ok, Editor.replace(source, tail, "")}
          span = edge.spans[:label] -> {:ok, Editor.replace(source, span, label)}
          true -> {:ok, Editor.replace(source, tail, " : " <> label)}
        end
      end
    end)
  end

  @doc "Troca `->` por `-->`, `->>` ou `-x`."
  @spec change_edge_arrow(String.t(), String.t(), atom() | String.t()) :: result()
  def change_edge_arrow(source, edge_id, arrow) do
    edit(source, fn ast ->
      with {:ok, edge} <- find_edge(ast, edge_id),
           {:ok, arrow} <- arrow(arrow) do
        {:ok, Editor.replace(source, edge.spans.arrow, Printer.arrow(arrow))}
      end
    end)
  end

  @spec remove_edge(String.t(), String.t()) :: result()
  def remove_edge(source, edge_id) do
    edit(source, fn ast ->
      with {:ok, edge} <- find_edge(ast, edge_id) do
        {:ok, Editor.remove_lines(source, edge.span, last_span(edge))}
      end
    end)
  end

  @doc """
  Escreve (ou troca, ou apaga com texto vazio) o payload de uma mensagem — o
  balão com os dados que ela carrega. Uma linha vira `payload: …`; várias, ou
  com `#`/`//`, um bloco `payload \"""`. Sempre logo abaixo da mensagem, com o
  recuo dela.
  """
  @spec set_payload(String.t(), String.t(), String.t() | nil) :: result()
  def set_payload(source, edge_id, text) do
    edit(source, fn ast ->
      with {:ok, edge} <- find_edge(ast, edge_id) do
        text = clean_payload(text)
        indent = Editor.indentation(source, edge.span)
        nl = Editor.newline(source)
        block = text |> Printer.payload() |> Enum.map_join(nl, &(indent <> &1))

        without =
          case edge.spans[:payload] do
            %Span{} = first -> Editor.remove_lines(source, first, edge.spans[:payload_end])
            nil -> source
          end

        {:ok, if(block == "", do: without, else: Editor.insert_line(without, edge.span, block))}
      end
    end)
  end

  defp clean_payload(nil), do: ""

  defp clean_payload(text) when is_binary(text) do
    text
    |> String.replace(~r/\r\n|\r/, "\n")
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.join("\n")
    |> String.trim("\n")
  end

  # A última linha de um item: a do payload, se houver; senão a própria.
  defp last_span(%Edge{spans: %{payload_end: %Span{} = span}}), do: span
  defp last_span(%{span: span}), do: span

  @doc """
  Remove um nó e tudo que só existe por causa dele: as setas que chegam ou
  saem dele, as notas ancoradas nele e a posição fixada.
  """
  @spec remove_node(String.t(), String.t()) :: result()
  def remove_node(source, node_id) do
    edit(source, fn ast ->
      with {:ok, node} <- find_node(ast, node_id) do
        items = Enum.flat_map(ast.steps, & &1.items)

        dependents =
          Enum.filter(items, fn
            %Edge{from: from, to: to} -> node_id in [from, to]
            %Note{target_ids: ids} -> node_id in ids
          end)

        # de trás para frente: remover linhas não desloca as que vêm antes; a
        # mensagem sai com o payload dela
        without =
          [node | dependents]
          |> Enum.filter(& &1.span)
          |> Enum.map(&{&1.span, last_span(&1)})
          |> Enum.uniq_by(fn {first, _last} -> first.line end)
          |> Enum.sort_by(fn {first, _last} -> first.offset end, :desc)
          |> Enum.reduce(source, fn {first, last}, acc ->
            Editor.remove_lines(acc, first, last)
          end)

        {:ok, Hints.unpin(without, node_id)}
      end
    end)
  end

  # ── criar e conectar (fase C) ─────────────────────────────────────────────

  @doc """
  Declara um nó novo. O id sai do rótulo (`"Fila de pedidos"` → `fila_de_pedidos`),
  sem colidir com os existentes. Com `:at`, já nasce fixado naquela posição.

  Atributos: `:label`, `:kind` (padrão: `service` na arquitetura,
  `participant` na sequência), `:group` (rótulo de um grupo existente), `:at`.
  """
  @spec add_node(String.t(), map()) :: result()
  def add_node(source, attrs) do
    edit(source, fn ast ->
      with {:ok, label} <- clean_label(Map.get(attrs, :label) || "Novo nó"),
           {:ok, kind} <- node_kind(Map.get(attrs, :kind), ast),
           {:ok, group} <- find_group(ast, Map.get(attrs, :group)) do
        id = unique_id(ast, label)
        declared = declare(source, ast, ~s(#{kind} #{id} "#{label}"), group && group.label)

        pinned =
          case Map.get(attrs, :at) do
            {x, y} -> Hints.pin(declared, id, {x, y})
            nil -> declared
          end

        {:ok, pinned, %{node_id: id}}
      end
    end)
  end

  @doc """
  Nova seta `from -> to` no passo indicado (índice da timeline) ou, sem passo,
  no último. Num passo explícito, a linha entra antes do `}`; num implícito,
  logo depois da última mensagem dele.
  """
  @spec connect_nodes(String.t(), map()) :: result()
  def connect_nodes(source, attrs) do
    edit(source, fn ast ->
      with {:ok, from} <- find_node(ast, Map.get(attrs, :from)),
           {:ok, to} <- find_node(ast, Map.get(attrs, :to)),
           {:ok, arrow} <- arrow(Map.get(attrs, :arrow) || :sync),
           {:ok, label} <- clean_edge_label(Map.get(attrs, :label)) do
        text = "#{from.id} #{Printer.arrow(arrow)} #{to.id}"
        text = if label == "", do: text, else: "#{text} : #{label}"

        {edited, offset} = insert_item(source, ast, target_step(ast, Map.get(attrs, :step)), text)
        {:ok, new_ast} = Parser.parse(edited)
        line = line_of(edited, offset)

        case Enum.find(all_edges(new_ast), &(&1.span.line == line)) do
          %Edge{id: id} -> {:ok, edited, %{edge_id: id}}
          nil -> {:error, :invalid_edit}
        end
      end
    end)
  end

  # ── posições (fase D) ─────────────────────────────────────────────────────

  @doc "Fixa o nó em `{x, y}` — uma linha no bloco `layout`."
  @spec pin_node(String.t(), String.t(), point()) :: result()
  def pin_node(source, node_id, {x, y}) when is_number(x) and is_number(y) do
    edit(source, fn ast ->
      with {:ok, node} <- find_node(ast, node_id) do
        {:ok, Hints.pin(source, node.id, {round(x), round(y)})}
      end
    end)
  end

  def pin_node(_source, _node_id, _point), do: {:error, :invalid_position}

  @spec unpin_node(String.t(), String.t()) :: result()
  def unpin_node(source, node_id),
    do: edit(source, fn _ast -> {:ok, Hints.unpin(source, node_id)} end)

  @doc "\"Reorganizar tudo\": apaga o bloco `layout` e o layout volta a ser automático."
  @spec clear_layout_hints(String.t()) :: result()
  def clear_layout_hints(source), do: edit(source, fn _ast -> {:ok, Hints.clear(source)} end)

  @doc """
  Move a declaração do nó para dentro do `group` indicado (pelo rótulo), ou para
  fora de qualquer grupo com `nil`. A linha é levada como está — comentário e
  alinhamento vão junto.
  """
  @spec move_node_to_group(String.t(), String.t(), String.t() | nil) :: result()
  def move_node_to_group(source, node_id, group_label) do
    edit(source, fn ast ->
      with {:ok, node} <- find_node(ast, node_id),
           {:ok, group} <- find_group(ast, blank_to_nil(group_label)) do
        target = group && group.label

        if node.group == target do
          {:ok, source}
        else
          text =
            if node.span,
              do: whole_line(source, node.span),
              else: ~s(#{node.kind} #{node.id} "#{node.label}")

          without = if node.span, do: Editor.remove_line(source, node.span), else: source

          case Parser.parse(without) do
            {:ok, rest} -> {:ok, declare(without, rest, text, target)}
            {:error, _} -> {:error, :invalid_edit}
          end
        end
      end
    end)
  end

  @doc """
  Solta um nó arrastado: move para o grupo em que caiu (se mudou) e fixa a
  posição. Uma edição só — desfazer volta o gesto inteiro.
  """
  @spec drop_node(String.t(), String.t(), point(), String.t() | nil | :keep) :: result()
  def drop_node(source, node_id, point, group \\ :keep) do
    moved =
      case group do
        :keep -> {:ok, source}
        label -> move_node_to_group(source, node_id, label)
      end

    with {:ok, moved} <- moved, do: pin_node(moved, node_id, point)
  end

  # ── teclado (fase E) ──────────────────────────────────────────────────────

  @doc """
  Move o bloco `step` que contém a linha `line` uma posição para cima ou para
  baixo, trocando-o de lugar com o vizinho. Devolve a linha onde o cursor deve
  ficar — o mesmo ponto do passo, agora na posição nova.
  """
  @spec move_step(String.t(), pos_integer(), :up | :down) :: result()
  def move_step(source, line, direction) when direction in [:up, :down] do
    edit(source, fn ast ->
      explicit = Enum.reject(ast.steps, & &1.implicit)
      index = Enum.find_index(explicit, &(&1.span.line <= line and line <= &1.end_span.line))
      neighbour = if index, do: index + if(direction == :up, do: -1, else: 1)

      if is_nil(index) or neighbour < 0 or neighbour >= length(explicit) do
        {:ok, source, %{line: line}}
      else
        [a, b] =
          Enum.sort(
            [Enum.at(explicit, index), Enum.at(explicit, neighbour)],
            &(&1.span.offset <= &2.span.offset)
          )

        {a_start, a_stop} = block_range(source, a)
        {b_start, b_stop} = block_range(source, b)

        swapped =
          binary_part(source, 0, a_start) <>
            binary_part(source, b_start, b_stop - b_start) <>
            binary_part(source, a_stop, b_start - a_stop) <>
            binary_part(source, a_start, a_stop - a_start) <>
            binary_part(source, b_stop, byte_size(source) - b_stop)

        delta =
          if direction == :down,
            do: b.end_span.line - a.end_span.line,
            else: a.span.line - b.span.line

        {:ok, swapped, %{line: line + delta}}
      end
    end)
  end

  @doc """
  Formata o arquivo inteiro com o printer canônico. Comentários não
  sobrevivem — `meta.comments_dropped` diz se havia algum, para a interface
  avisar (e lembrar que dá para desfazer).
  """
  @spec format(String.t()) :: result()
  def format(source) do
    edit(source, fn ast ->
      {:ok, Printer.print(ast), %{comments_dropped: Parser.comments?(source)}}
    end)
  end

  @doc """
  Renomeia o diagrama — que, aqui, é trocar o título do cabeçalho
  `diagram <tipo> "<título>"`. Só os bytes entre as aspas mudam; sem título,
  ele entra depois do tipo; sem cabeçalho, o cabeçalho entra na 1ª linha.
  """
  @spec rename_title(String.t(), String.t()) :: result()
  def rename_title(source, title) do
    edit(source, fn ast ->
      with {:ok, title} <- clean_label(title) do
        cond do
          match?(%Span{}, ast.spans[:title]) ->
            {:ok, Editor.replace(source, ast.spans[:title], title)}

          match?(%Span{}, ast.spans[:kind]) ->
            %Span{offset: offset, length: length} = ast.spans[:kind]
            {:ok, Editor.insert_at(source, offset + length, ~s( "#{title}"))}

          true ->
            header = ~s(diagram #{ast.kind} "#{title}")
            {:ok, header <> Editor.newline(source) <> source}
        end
      end
    end)
  end

  @doc "Alterna entre `sequence` e `architecture` trocando só a palavra do cabeçalho."
  @spec switch_kind(String.t()) :: result()
  def switch_kind(source) do
    edit(source, fn ast ->
      next = if ast.kind == :sequence, do: "architecture", else: "sequence"

      case ast.spans[:kind] do
        %Span{} = span -> {:ok, Editor.replace(source, span, next)}
        nil -> {:ok, "diagram #{next}" <> Editor.newline(source) <> source}
      end
    end)
  end

  @doc """
  Deita ou levanta um diagrama de arquitetura. Para deitar, a linha
  `direction horizontal` entra logo abaixo do cabeçalho; para levantar, ela sai
  (vertical é o padrão). As posições fixadas valiam para a outra orientação,
  então o bloco `layout` sai junto — `meta.unpinned` diz se havia um.
  """
  @spec switch_direction(String.t()) :: result()
  def switch_direction(source) do
    edit(source, fn
      %Ast{kind: :architecture} = ast ->
        unpinned = not is_nil(ast.layout_span)
        cleared = if unpinned, do: Hints.clear(source), else: source
        {:ok, cleared_ast} = Parser.parse(cleared)

        {:ok, set_direction(cleared, cleared_ast), %{unpinned: unpinned}}

      _ast ->
        {:error, :not_architecture}
    end)
  end

  defp set_direction(source, %Ast{direction: :horizontal, direction_span: %Span{} = span}),
    do: Editor.remove_line(source, span)

  defp set_direction(source, %Ast{direction: :vertical, direction_span: %Span{} = span}),
    do: Editor.replace(source, span, "direction horizontal")

  defp set_direction(source, %Ast{span: %Span{} = header}),
    do: Editor.insert_line(source, header, "direction horizontal")

  defp set_direction(source, _ast),
    do: "direction horizontal" <> Editor.newline(source) <> source

  @doc """
  Reorganiza os componentes de um diagrama de arquitetura para desembaraçar
  as setas (`Layout.Untangle`) e grava a arrumação no bloco `layout`.
  `meta` traz as métricas de antes e depois e `improved`: sem melhora
  possível, o fonte volta igual e `improved` é `false`.
  """
  @spec untangle(String.t()) :: result()
  def untangle(source) do
    edit(source, fn _ast ->
      with {:ok, result} <- Untangle.run(source) do
        {:ok, result.source,
         %{improved: result.improved, before: result.before, after: result.after}}
      end
    end)
  end

  # ── despacho por nome (canvas, paleta) ────────────────────────────────────

  @operations ~w(rename_node relabel_edge change_arrow remove_node remove_edge add_node connect
                 pin unpin clear_layout untangle move_to_group drop move_step format switch_kind
                 switch_direction rename_title set_payload)

  @doc "Nomes aceitos por `run/3` — o vocabulário que o canvas e a paleta usam."
  @spec operations() :: [String.t()]
  def operations, do: @operations

  @doc """
  Executa uma operação pelo nome, com parâmetros vindos da interface (chaves e
  valores em string). É a porta única que a query `EditSource` usa.
  """
  @spec run(String.t(), String.t(), map()) :: result()
  def run(source, op, params) when is_map(params) do
    p = fn key -> Map.get(params, key) end

    case op do
      "rename_node" ->
        rename_node_label(source, p.("id"), p.("label") || "")

      "relabel_edge" ->
        relabel_edge(source, p.("id"), p.("label"))

      "change_arrow" ->
        change_edge_arrow(source, p.("id"), p.("arrow"))

      "remove_node" ->
        remove_node(source, p.("id"))

      "remove_edge" ->
        remove_edge(source, p.("id"))

      "add_node" ->
        add_node(source, %{
          label: p.("label"),
          kind: p.("kind"),
          group: p.("group"),
          at: point(params)
        })

      "connect" ->
        connect_nodes(source, %{
          from: p.("from"),
          to: p.("to"),
          arrow: p.("arrow"),
          label: p.("label"),
          step: int(p.("step"))
        })

      "pin" ->
        with {:ok, at} <- require_point(params), do: pin_node(source, p.("id"), at)

      "unpin" ->
        unpin_node(source, p.("id"))

      "clear_layout" ->
        clear_layout_hints(source)

      "untangle" ->
        untangle(source)

      "move_to_group" ->
        move_node_to_group(source, p.("id"), p.("group"))

      "drop" ->
        with {:ok, at} <- require_point(params),
             do: drop_node(source, p.("id"), at, drop_group(params))

      "move_step" ->
        move_step(source, int(p.("line")) || 1, if(p.("direction") == "up", do: :up, else: :down))

      "format" ->
        format(source)

      "switch_kind" ->
        switch_kind(source)

      "switch_direction" ->
        switch_direction(source)

      "rename_title" ->
        rename_title(source, p.("title") || "")

      "set_payload" ->
        set_payload(source, p.("id"), p.("payload"))

      _ ->
        {:error, :unknown_operation}
    end
  end

  # ── privados: fluxo ───────────────────────────────────────────────────────

  defp edit(source, fun) when is_binary(source) do
    with {:ok, ast} <- parse(source) do
      case fun.(ast) do
        {:ok, edited} -> validated(edited, %{})
        {:ok, edited, meta} -> validated(edited, meta)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp edit(_source, _fun), do: {:error, :invalid_edit}

  defp parse(source) do
    case Parser.parse(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, errors} -> {:error, {:syntax, errors}}
    end
  end

  # Patch que quebra o fonte é descartado inteiro — nada de meio aplicado.
  defp validated(edited, meta) do
    case Parser.parse(edited) do
      {:ok, _} -> if meta == %{}, do: {:ok, edited}, else: {:ok, edited, meta}
      {:error, _} -> {:error, :invalid_edit}
    end
  end

  # ── privados: busca ───────────────────────────────────────────────────────

  defp find_node(%Ast{nodes: nodes}, id) do
    case Enum.find(nodes, &(&1.id == id)) do
      %Node{} = node -> {:ok, node}
      nil -> {:error, :unknown_node}
    end
  end

  defp find_edge(ast, id) do
    case Enum.find(all_edges(ast), &(&1.id == id)) do
      %Edge{} = edge -> {:ok, edge}
      nil -> {:error, :unknown_edge}
    end
  end

  defp find_group(_ast, nil), do: {:ok, nil}
  defp find_group(_ast, ""), do: {:ok, nil}

  defp find_group(%Ast{groups: groups}, label) do
    case Enum.find(groups, &(&1.label == label)) do
      %Group{} = group -> {:ok, group}
      nil -> {:error, :unknown_group}
    end
  end

  defp all_edges(%Ast{steps: steps}) do
    steps |> Enum.flat_map(& &1.items) |> Enum.filter(&match?(%Edge{}, &1))
  end

  defp target_step(%Ast{steps: []}, _index), do: nil
  defp target_step(%Ast{steps: steps}, nil), do: List.last(steps)

  defp target_step(%Ast{steps: steps}, index),
    do: Enum.find(steps, &(&1.index == index)) || List.last(steps)

  # ── privados: onde inserir ────────────────────────────────────────────────

  # Declaração nova: no fim do grupo, ou logo depois da última declaração solta,
  # ou logo depois do cabeçalho — com a indentação dos vizinhos.
  defp declare(source, ast, text, group_label) do
    group = group_label && Enum.find(ast.groups, &(&1.label == group_label))

    if group do
      members = Enum.filter(ast.nodes, &(&1.group == group.label and &1.span))

      indent =
        case members do
          [] -> Editor.indentation(source, group.span) <> "  "
          _ -> Editor.indentation(source, Enum.max_by(members, & &1.span.offset).span)
        end

      Editor.insert_line_before(source, group.end_span, indent <> text)
    else
      loose = Enum.filter(ast.nodes, &(is_nil(&1.group) and &1.span))

      cond do
        loose != [] ->
          last = Enum.max_by(loose, & &1.span.offset)
          Editor.insert_line(source, last.span, Editor.indentation(source, last.span) <> text)

        ast.span ->
          Editor.insert_line(source, ast.span, text)

        source == "" ->
          text

        true ->
          text <> Editor.newline(source) <> source
      end
    end
  end

  # Devolve o fonte editado e o offset onde a linha nova começa.
  defp insert_item(source, ast, nil, text) do
    case ast.layout_span do
      %Span{} = layout ->
        {start, _, _} = Editor.line_bounds(source, layout.offset)
        {Editor.insert_line_before(source, layout, text), start}

      nil ->
        edited = Editor.append_line(source, text)

        offset =
          cond do
            source == "" -> 0
            Editor.ends_with_newline?(source) -> byte_size(source)
            true -> byte_size(source) + byte_size(Editor.newline(source))
          end

        {edited, offset}
    end
  end

  defp insert_item(source, _ast, %{implicit: false} = step, text) do
    indent =
      case Enum.filter(step.items, & &1.span) do
        [] -> Editor.indentation(source, step.span) <> "  "
        items -> Editor.indentation(source, List.last(items).span)
      end

    {start, _, _} = Editor.line_bounds(source, step.end_span.offset)
    {Editor.insert_line_before(source, step.end_span, indent <> text), start}
  end

  defp insert_item(source, ast, %{implicit: true, items: items}, text) do
    case items |> Enum.filter(& &1.span) |> List.last() do
      nil ->
        insert_item(source, ast, nil, text)

      last ->
        # depois do payload da última mensagem, não entre ela e o payload
        anchor = last_span(last)
        indent = Editor.indentation(source, last.span)
        {_, stop, _} = Editor.line_bounds(source, anchor.offset)
        edited = Editor.insert_line(source, anchor, indent <> text)
        {edited, stop + byte_size(Editor.newline(source))}
    end
  end

  # A linha inteira da declaração, sem a indentação — o comentário do fim vai junto.
  defp whole_line(source, span) do
    {start, stop, _} = Editor.line_bounds(source, span.offset)
    source |> binary_part(start, stop - start) |> String.trim_leading()
  end

  defp block_range(source, step) do
    {start, _, _} = Editor.line_bounds(source, step.span.offset)
    {_, stop, _} = Editor.line_bounds(source, step.end_span.offset)
    {start, stop}
  end

  defp range(source, from, to) do
    {line_start, _, _} = Editor.line_bounds(source, from)
    line = line_of(source, from)
    Span.new(line, from - line_start + 1, from, to - from)
  end

  defp line_of(source, offset) do
    length(Regex.scan(~r/\r\n|\r|\n/, binary_part(source, 0, offset))) + 1
  end

  # ── privados: valores ─────────────────────────────────────────────────────

  # A DSL não escapa aspas nem quebras: aspa vira aspa tipográfica, quebra vira espaço.
  defp clean_label(label) when is_binary(label) do
    case label
         |> String.replace(~r/[\r\n\t]+/, " ")
         |> String.replace("\"", "”")
         |> String.trim() do
      "" -> {:error, :blank_label}
      text -> {:ok, text}
    end
  end

  defp clean_label(_), do: {:error, :blank_label}

  # Depois do `:` qualquer texto vale, menos o que o parser leria como comentário.
  defp clean_edge_label(nil), do: {:ok, ""}

  defp clean_edge_label(label) when is_binary(label) do
    text = label |> String.replace(~r/[\r\n\t]+/, " ") |> String.trim()

    if String.contains?(text, ["#", "//"]),
      do: {:error, :invalid_label},
      else: {:ok, text}
  end

  defp clean_edge_label(_), do: {:error, :invalid_label}

  defp arrow(arrow) when arrow in [:sync, :return, :async, :fail], do: {:ok, arrow}

  defp arrow(arrow) when is_binary(arrow) do
    case Map.fetch(@arrows, arrow) do
      {:ok, atom} -> {:ok, atom}
      :error -> {:error, :invalid_arrow}
    end
  end

  defp arrow(_), do: {:error, :invalid_arrow}

  defp node_kind(nil, %Ast{kind: :architecture}), do: {:ok, :service}
  defp node_kind(nil, _ast), do: {:ok, :participant}
  defp node_kind("", ast), do: node_kind(nil, ast)
  defp node_kind(kind, _ast) when is_atom(kind), do: node_kind(Atom.to_string(kind), nil)

  defp node_kind(kind, _ast) when is_binary(kind) do
    case Map.fetch(@kinds, kind) do
      {:ok, atom} -> {:ok, atom}
      :error -> {:error, :invalid_kind}
    end
  end

  # `"Fila de Pedidos"` → `fila_de_pedidos`; `fila_de_pedidos_2` se já existir.
  defp unique_id(%Ast{nodes: nodes}, label) do
    taken = MapSet.new(nodes, & &1.id)

    base =
      label
      |> String.normalize(:nfd)
      |> String.replace(~r/[^\x00-\x7F]/u, "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")
      |> case do
        "" -> "no"
        <<digit, _::binary>> = id when digit in ?0..?9 -> "n_" <> id
        id -> id
      end

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}_#{n}"
    end)
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  defp point(params) do
    with x when not is_nil(x) <- number(params["x"]),
         y when not is_nil(y) <- number(params["y"]) do
      {x, y}
    else
      _ -> nil
    end
  end

  defp require_point(params) do
    case point(params) do
      nil -> {:error, :invalid_position}
      at -> {:ok, at}
    end
  end

  # Na soltura, a chave `group` ausente quer dizer "não mudou de grupo"; presente
  # e vazia quer dizer "saiu de todos".
  defp drop_group(params) do
    if Map.has_key?(params, "group"), do: blank_to_nil(params["group"]), else: :keep
  end

  defp number(n) when is_integer(n), do: n
  defp number(n) when is_float(n), do: round(n)

  defp number(n) when is_binary(n) do
    case Float.parse(n) do
      {value, _} -> round(value)
      :error -> nil
    end
  end

  defp number(_), do: nil

  defp int(nil), do: nil
  defp int(n) when is_integer(n), do: n

  defp int(n) when is_binary(n) do
    case Integer.parse(n) do
      {value, _} -> value
      :error -> nil
    end
  end

  defp int(_), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
