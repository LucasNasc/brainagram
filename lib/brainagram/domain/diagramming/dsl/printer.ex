defmodule Brainagram.Domain.Diagramming.Dsl.Printer do
  @moduledoc """
  AST → DSL canônica.

  É o escritor *explícito*, usado só quando a pessoa pede: o comando Formatar,
  `mix brainagram.fmt` e a importação de Mermaid/PlantUML (onde não há
  formatação original a preservar). Para edições interativas o caminho é
  `Dsl.Editor` — regenerar o arquivo a cada gesto apagaria comentários e
  transformaria "arrastei uma caixa" num diff de quarenta linhas.

  A forma canônica:

      diagram architecture "Plataforma"

      service  api "API"
      database pg  "PostgreSQL"

      group "Dados" {
        queue mq "RabbitMQ"
      }

      step "Leitura" {
        api -> pg : SELECT
      }

      layout {
        pg at (420, 680)
      }

  O contrato que os testes cobram: `Parser.parse(print(ast))` devolve a mesma
  AST, a menos de posições (`line`, `span`, `spans`) e ids gerados.
  """

  alias Brainagram.Domain.Diagramming.Dsl.{Ast, Edge, Group, Node, Note, Parser, Pin, Step}

  @indent "  "

  @spec print(Ast.t()) :: String.t()
  def print(%Ast{} = ast) do
    [header(ast), nodes_section(ast), steps_section(ast), layout_section(ast)]
    |> Enum.reject(&(&1 == []))
    |> Enum.map_join("\n\n", &Enum.join(&1, "\n"))
    |> Kernel.<>("\n")
  end

  # ── cabeçalho ─────────────────────────────────────────────────────────────

  defp header(%Ast{kind: kind, title: nil}), do: ["diagram #{kind}"]
  defp header(%Ast{kind: kind, title: title}), do: ["diagram #{kind} #{quote_text(title)}"]

  # ── nós e grupos ──────────────────────────────────────────────────────────

  # Os nós saem na ordem da AST — é ela que decide a ordem das raias numa
  # sequência. Um grupo é impresso onde aparece o primeiro membro dele, com
  # todos os membros dentro; grupos vazios vão para o fim da seção.
  defp nodes_section(%Ast{nodes: nodes, groups: groups}) do
    by_label = Map.new(groups, &{&1.label, &1})

    {chunks, printed_groups} =
      Enum.reduce(nodes, {[], MapSet.new()}, fn node, {chunks, printed} ->
        case node.group && Map.get(by_label, node.group) do
          nil ->
            {[{:loose, node} | chunks], printed}

          %Group{label: label} = group ->
            if MapSet.member?(printed, label),
              do: {chunks, printed},
              else: {[{:group, group} | chunks], MapSet.put(printed, label)}
        end
      end)

    empty_groups =
      groups
      |> Enum.reject(&MapSet.member?(printed_groups, &1.label))
      |> Enum.map(&{:group, &1})

    node_by_id = Map.new(nodes, &{&1.id, &1})

    (Enum.reverse(chunks) ++ empty_groups)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn
      [{:loose, _} | _] = run ->
        run |> Enum.map(&elem(&1, 1)) |> declarations("")

      groups ->
        groups
        |> Enum.map(fn {:group, group} -> group_lines(group, node_by_id) end)
        |> Enum.intersperse([""])
        |> List.flatten()
    end)
    |> Enum.intersperse([""])
    |> List.flatten()
  end

  defp group_lines(%Group{} = group, node_by_id) do
    members = group.node_ids |> Enum.map(&node_by_id[&1]) |> Enum.reject(&is_nil/1)
    ["group #{quote_text(group.label)} {"] ++ declarations(members, @indent) ++ ["}"]
  end

  # Colunas alinhadas, como nos exemplos: fica fácil bater o olho no tipo.
  defp declarations(nodes, indent) do
    kind_w = nodes |> Enum.map(&String.length(Atom.to_string(&1.kind))) |> Enum.max(fn -> 0 end)
    id_w = nodes |> Enum.map(&String.length(&1.id)) |> Enum.max(fn -> 0 end)

    Enum.map(nodes, fn %Node{} = node ->
      kind = node.kind |> Atom.to_string() |> String.pad_trailing(kind_w)
      id = String.pad_trailing(node.id, id_w)
      String.trim_trailing("#{indent}#{kind} #{id} #{quote_text(node.label)}")
    end)
  end

  # ── passos ────────────────────────────────────────────────────────────────

  # Passos implícitos (o parser os inventou a partir de mensagens soltas) voltam
  # a ser mensagens soltas; só os explícitos viram bloco `step`.
  defp steps_section(%Ast{steps: steps}) do
    {implicit, explicit} = Enum.split_with(steps, & &1.implicit)

    loose = implicit |> Enum.flat_map(& &1.items) |> Enum.flat_map(&item/1)
    blocks = Enum.map(explicit, &step_block/1)

    [loose | blocks]
    |> Enum.reject(&(&1 == []))
    |> Enum.intersperse([""])
    |> List.flatten()
  end

  defp step_block(%Step{} = step) do
    ["step #{quote_text(step.label)} {"] ++
      Enum.flat_map(step.items, fn item -> Enum.map(item(item), &(@indent <> &1)) end) ++ ["}"]
  end

  # Cada item vira uma ou mais linhas: a mensagem e, abaixo dela, o payload.
  defp item(%Edge{} = edge) do
    base = "#{edge.from} #{arrow(edge.arrow)} #{edge.to}"
    line = if edge.label, do: "#{base} : #{edge.label}", else: base
    [line | payload(edge.payload)]
  end

  defp item(%Note{} = note) do
    ["note #{placement(note.placement)} #{Enum.join(note.target_ids, ", ")} : #{note.text}"]
  end

  @doc """
  As linhas do payload, recuadas sob a mensagem. Uma linha que o parser leria
  igual vira `payload: …`; o resto (várias linhas, ou `#`/`//` que virariam
  comentário) vai num bloco `\"""`, onde nada é comentário.
  """
  @spec payload(String.t() | nil) :: [String.t()]
  def payload(nil), do: []
  def payload(""), do: []

  def payload(text) do
    single = "payload: " <> text

    if String.contains?(text, "
") or Parser.comments?(single) do
      lines = text |> String.split("
") |> Enum.map(&String.trim_trailing(@indent <> &1))

      Enum.map([~s(payload """) | lines] ++ [~s(""")], &(@indent <> &1))
      |> Enum.map(&String.trim_trailing/1)
    else
      [@indent <> single]
    end
  end

  @doc "O operador da DSL para cada tipo de seta."
  @spec arrow(Edge.arrow()) :: String.t()
  def arrow(:sync), do: "->"
  def arrow(:return), do: "-->"
  def arrow(:async), do: "->>"
  def arrow(:fail), do: "-x"

  defp placement(:over), do: "over"
  defp placement(:left), do: "left of"
  defp placement(:right), do: "right of"

  # ── layout ────────────────────────────────────────────────────────────────

  defp layout_section(%Ast{pins: []}), do: []

  defp layout_section(%Ast{pins: pins}) do
    ["layout {"] ++ Enum.map(pins, &(@indent <> pin(&1))) ++ ["}"]
  end

  @doc "Uma linha do bloco `layout`: `api at (420, 680)`."
  @spec pin(Pin.t() | {String.t(), {integer(), integer()}}) :: String.t()
  def pin(%Pin{id: id, x: x, y: y}), do: "#{id} at (#{x}, #{y})"
  def pin({id, {x, y}}), do: "#{id} at (#{x}, #{y})"

  # A DSL não tem escape de aspas: uma aspa dentro do texto quebraria a linha,
  # então vira aspa tipográfica.
  defp quote_text(text), do: ~s("#{String.replace(text, "\"", "”")}")
end
