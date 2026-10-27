defmodule Brainagram.Domain.Diagramming.Import.Builder do
  @moduledoc """
  O que os importadores têm em comum: acumular participantes, mensagens, notas
  e blocos na ordem em que aparecem, e no fim montar uma AST que o `Printer`
  transforma em DSL canônica.

  Os dialetos (`Import.Mermaid`, `Import.PlantUml`) só traduzem linhas em
  chamadas daqui. A regra de conversão de blocos mora num lugar só:

    * `loop`, `alt`, `opt`, `critical`, `break`… no nível de fora viram um
      `step`; `else` (e `option`) abre o passo seguinte. Blocos aninhados se
      achatam dentro do passo de fora — a DSL não tem passo dentro de passo.
    * Um separador (`== Fase ==` no PlantUML) abre um passo com aquele nome.
    * Mensagens fora de qualquer bloco, num diagrama que tem blocos, viram um
      passo próprio — senão o printer as juntaria todas no começo e a ordem da
      história mudaria.
    * Sem bloco nenhum, cada mensagem é o seu próprio passo (o padrão da DSL).

  O que não converte vira aviso, e o aviso vira comentário no topo do arquivo —
  falhar num arquivo de 80 linhas por causa de duas construções é como se perde
  um usuário na primeira tentativa (spec 001, §9).
  """

  alias Brainagram.Domain.Diagramming.Dsl.{Ast, Edge, Group, Node, Note, Parser, Printer, Step}

  defstruct kind: :sequence,
            title: nil,
            direction: :vertical,
            order: [],
            names: %{},
            nodes: %{},
            groups: [],
            box: nil,
            segments: [],
            loose: [],
            current: nil,
            depth: 0,
            has_blocks: false,
            warnings: [],
            counter: 0

  @type t :: %__MODULE__{}

  @label_kinds [
    {~r/\b(redis|cache|memcache|postgres|postgresql|mysql|mariadb|mongo|mongodb|dynamo|dynamodb|sqlite|oracle|database|banco|db|s3|bucket|elastic|elasticsearch|opensearch)\b/i,
     :database},
    {~r/\b(queue|fila|kafka|rabbit|rabbitmq|sqs|sns|pubsub|pub\/sub|nats|broker|topic|t[óo]pico)\b/i,
     :queue},
    {~r/\b(client|clients|cliente|clientes|user|users|usu[áa]rio|usu[áa]rios|consumer|consumers|consumidor|consumidores|browser|navegador)\b/i,
     :actor}
  ]

  @doc """
  O tipo que o nome sugere, para nós genéricos: "Redis", "Postgres", "S3"
  viram `database`; "Fila", "Kafka", "SQS" viram `queue`; "Clientes" vira
  `actor`. Sem pista, `default`.
  """
  @spec guess_kind(String.t(), atom()) :: atom()
  def guess_kind(label, default) do
    Enum.find_value(@label_kinds, default, fn {re, k} -> if label =~ re, do: k end)
  end

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Tipo do diagrama gerado: `:sequence` (padrão) ou `:architecture`."
  @spec kind(t(), :sequence | :architecture) :: t()
  def kind(b, kind) when kind in [:sequence, :architecture], do: %{b | kind: kind}

  @doc "Sentido do layout de arquitetura: `:vertical` (padrão) ou `:horizontal`."
  @spec direction(t(), :vertical | :horizontal) :: t()
  def direction(b, direction) when direction in [:vertical, :horizontal],
    do: %{b | direction: direction}

  @spec title(t(), String.t()) :: t()
  def title(b, text), do: %{b | title: clean(text)}

  @doc "Declara um participante (ou atualiza rótulo e tipo se já apareceu)."
  @spec participant(t(), String.t(), String.t() | nil, atom()) :: t()
  def participant(b, name, label \\ nil, kind \\ :participant) do
    {b, id} = id_for(b, name)
    node = Map.get(b.nodes, id, %{id: id, label: name, kind: :participant, group: nil})
    node = %{node | label: clean(label || node.label), kind: kind, group: node.group || b.box}
    b = put_in(b.nodes[id], node)
    if b.box, do: add_to_box(b, id), else: b
  end

  @spec message(t(), String.t(), String.t(), Edge.arrow(), String.t() | nil) :: t()
  def message(b, from, to, arrow, text) do
    {b, from} = ensure(b, from)
    {b, to} = ensure(b, to)
    {b, id} = next_id(b, "e")
    push(b, %Edge{id: id, from: from, to: to, arrow: arrow, label: blank(label(text)), line: 1})
  end

  @spec note(t(), :over | :left | :right, [String.t()], String.t()) :: t()
  def note(b, placement, targets, text) do
    {b, ids} =
      Enum.reduce(targets, {b, []}, fn name, {b, acc} ->
        {b2, id} = ensure(b, name)
        {b2, acc ++ [id]}
      end)

    {b, id} = next_id(b, "n")
    text = label(text) || "…"
    push(b, %Note{id: id, placement: placement, target_ids: ids, text: text, line: 1})
  end

  @doc "Abre um bloco (`loop`, `alt`…). Só o de fora vira passo."
  @spec open(t(), String.t() | nil) :: t()
  def open(%{depth: 0} = b, label) do
    b = b |> finish_section() |> flush_loose()
    %{b | current: {clean(label || "Passo"), []}, depth: 1, has_blocks: true}
  end

  def open(b, _label), do: %{b | depth: b.depth + 1}

  @doc "`else`/`option`: no nível de fora, fecha o passo e abre o próximo."
  @spec branch(t(), String.t() | nil) :: t()
  def branch(%{depth: 1} = b, label) do
    b = finish_current(b)
    %{b | current: {clean(label || "senão"), []}}
  end

  def branch(b, _label), do: b

  @spec close(t()) :: t()
  def close(%{depth: 0} = b), do: b
  def close(%{depth: 1} = b), do: %{finish_current(b) | depth: 0}
  def close(b), do: %{b | depth: b.depth - 1}

  @doc "Separador de seção (`== Nome ==`): abre um passo que vai até o próximo."
  @spec section(t(), String.t()) :: t()
  def section(%{depth: 0} = b, label) do
    b = b |> finish_section() |> flush_loose()
    %{b | current: {:section, clean(label), []}, has_blocks: true}
  end

  def section(b, _label), do: b

  @doc "Agrupamento visual de participantes (`box` no Mermaid e no PlantUML)."
  @spec open_box(t(), String.t()) :: t()
  def open_box(b, label), do: %{b | box: clean(label)}

  @spec close_box(t()) :: t()
  def close_box(b), do: %{b | box: nil}

  @spec warn(t(), pos_integer(), String.t()) :: t()
  def warn(b, line, text), do: %{b | warnings: b.warnings ++ [{line, text}]}

  @doc """
  Monta a AST, imprime e valida. Os avisos viram comentário no topo.
  Devolve `{:ok, %{source: texto, warnings: [{linha, aviso}]}}`.
  """
  @spec finish(t(), String.t()) ::
          {:ok, %{source: String.t(), warnings: list()}} | {:error, term()}
  def finish(b, dialect) do
    b = b |> finish_current() |> finish_section() |> flush_loose()

    if b.order == [] do
      {:error, :nothing_to_import}
    else
      text = header(b.warnings, dialect) <> Printer.print(ast(b))

      case Parser.parse(text) do
        {:ok, _} -> {:ok, %{source: text, warnings: b.warnings}}
        {:error, errors} -> {:error, {:syntax, errors}}
      end
    end
  end

  # ── privados ──────────────────────────────────────────────────────────────

  defp push(%{depth: d, current: {label, items}} = b, item) when d > 0,
    do: %{b | current: {label, items ++ [item]}}

  defp push(%{current: {:section, label, items}} = b, item),
    do: %{b | current: {:section, label, items ++ [item]}}

  defp push(b, item), do: %{b | loose: b.loose ++ [item]}

  defp finish_current(%{current: {label, items}} = b) when is_binary(label) do
    %{b | segments: b.segments ++ [{:step, label, items}], current: nil}
  end

  defp finish_current(b), do: b

  defp finish_section(%{current: {:section, label, items}} = b) do
    %{b | segments: b.segments ++ [{:step, label, items}], current: nil}
  end

  defp finish_section(b), do: b

  defp flush_loose(%{loose: []} = b), do: b
  defp flush_loose(b), do: %{b | segments: b.segments ++ [{:loose, b.loose}], loose: []}

  defp ast(b) do
    nodes =
      Enum.map(b.order, fn id ->
        n = b.nodes[id]
        %Node{id: id, label: n.label, kind: n.kind, group: n.group, line: 1}
      end)

    groups =
      b.groups
      |> Enum.with_index(1)
      |> Enum.map(fn {{label, ids}, i} ->
        %Group{id: "g#{i}", label: label, node_ids: ids, line: 1}
      end)

    steps =
      if b.has_blocks do
        b.segments
        |> Enum.map(fn
          {:loose, items} -> {run_label(items), items}
          {:step, label, items} -> {label, items}
        end)
        |> Enum.reject(fn {_label, items} -> items == [] end)
        |> Enum.with_index()
        |> Enum.map(fn {{label, items}, i} ->
          %Step{index: i, label: label, items: items, line: 1}
        end)
      else
        b.segments
        |> Enum.flat_map(fn {_kind, items} -> items end)
        |> Enum.with_index()
        |> Enum.map(fn {item, i} ->
          %Step{index: i, label: "", items: [item], line: 1, implicit: true}
        end)
      end

    %Ast{
      kind: b.kind,
      title: b.title,
      direction: b.direction,
      nodes: nodes,
      groups: groups,
      steps: steps
    }
  end

  defp run_label([%Edge{label: label} | _]) when is_binary(label), do: label
  defp run_label([%Note{text: text} | _]), do: text
  defp run_label(_), do: "Passo"

  defp header([], _dialect), do: ""

  defp header(warnings, dialect) do
    n = length(warnings)

    title =
      "# #{n} #{if n == 1, do: "construção não convertida", else: "construções não convertidas"} do #{dialect} original:"

    lines = Enum.map(warnings, fn {line, text} -> "#   linha #{line}: #{text}" end)
    Enum.join([title | lines], "\n") <> "\n\n"
  end

  defp ensure(b, name) do
    {b, id} = id_for(b, name)

    if Map.has_key?(b.nodes, id),
      do: {b, id},
      else:
        {put_in(b.nodes[id], %{id: id, label: clean(name), kind: default_kind(b), group: nil}),
         id}
  end

  # Nó citado numa seta sem ter sido declarado: na arquitetura, um serviço.
  defp default_kind(%{kind: :architecture}), do: :service
  defp default_kind(_b), do: :participant

  defp add_to_box(b, id) do
    label = b.box

    groups =
      case List.keyfind(b.groups, label, 0) do
        nil -> b.groups ++ [{label, [id]}]
        {^label, ids} -> List.keyreplace(b.groups, label, 0, {label, Enum.uniq(ids ++ [id])})
      end

    %{b | groups: groups}
  end

  # Nome no dialeto de origem → id válido na DSL. O mesmo nome sempre dá o
  # mesmo id; dois nomes que viram o mesmo id ganham sufixo.
  defp id_for(b, name) do
    name = String.trim(name)

    case Map.fetch(b.names, name) do
      {:ok, id} ->
        {b, id}

      :error ->
        base =
          name
          |> String.normalize(:nfd)
          |> String.replace(~r/[^\x00-\x7F]/u, "")
          |> String.replace(~r/[^A-Za-z0-9_\-.]+/, "_")
          |> String.trim("_")
          |> case do
            "" -> "p"
            <<c, _::binary>> = id when c in ?0..?9 or c in [?-, ?.] -> "p_" <> id
            id -> id
          end

        taken = MapSet.new(Map.values(b.names))

        id =
          Stream.iterate(1, &(&1 + 1))
          |> Stream.map(fn
            1 -> base
            n -> "#{base}_#{n}"
          end)
          |> Enum.find(&(not MapSet.member?(taken, &1)))

        {%{b | names: Map.put(b.names, name, id), order: b.order ++ [id]}, id}
    end
  end

  defp next_id(b, prefix), do: {%{b | counter: b.counter + 1}, "#{prefix}#{b.counter + 1}"}

  # Na DSL, `#` e `//` começam comentário: no texto importado viram sinais
  # parecidos que não cortam a linha.
  defp label(nil), do: nil

  defp label(text) do
    text
    |> clean()
    |> String.replace("#", "＃")
    |> String.replace("//", "/⁄")
    |> String.replace(~r/<br\s*\/?>/i, " ")
  end

  defp clean(text) when is_binary(text), do: text |> String.replace(~r/\s+/, " ") |> String.trim()
  defp clean(nil), do: nil

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(text), do: text
end
