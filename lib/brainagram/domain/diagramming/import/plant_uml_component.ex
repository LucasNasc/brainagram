defmodule Brainagram.Domain.Diagramming.Import.PlantUmlComponent do
  @moduledoc """
  Diagrama de componentes (ou de implantação) do PlantUML → diagrama de
  arquitetura do Brainagram.

  Cobertura:

    * elementos: `[Nome]`, `[Nome] as ID`, e as palavras-chave `component`,
      `database`, `queue`, `actor`, `person`, `cloud`, `rectangle`, `node`,
      `interface`, `storage`, `collections`, `boundary`… nas formas
      `"Nome" as ID`, `ID as "Nome"`, `[Nome] as ID` e `ID`;
    * contêineres com `{ }` — `package`, `node`, `cloud`, `rectangle`,
      `frame`, `folder`… — viram `group`. Aninhados, vale o mais de dentro
      (a DSL não tem grupo dentro de grupo);
    * setas `->`, `-->`, `..>` (pontilhada = assíncrona), `-x`, invertidas
      (`<--`), com cor ou estilo (`-[#blue]->`, `-[dashed]->`), com direção
      (`-down->`, `-r->`) e com rótulo depois de `:`;
    * `title`; `\\n` nos nomes vira espaço.

  O tipo do nó vem da palavra-chave; para os genéricos (`[X]`, `component`,
  `rectangle`, `node`), o nome ajuda: "Redis", "Postgres", "Cache" viram
  `database`, "Fila", "Kafka", "SQS" viram `queue`, "Clientes" vira `actor`.

  Ficam de fora, com aviso no topo do arquivo: notas (a arquitetura não
  desenha notas — o texto delas vai no aviso, nada se perde), setas para um
  grupo inteiro e linhas não reconhecidas. Aparência (`skinparam`, `!theme`,
  `hide`, `left to right direction`…) é ignorada sem aviso.
  """

  alias Brainagram.Domain.Diagramming.Import.Builder

  @element_kinds %{
    "component" => :service,
    "database" => :database,
    "storage" => :database,
    "collections" => :database,
    "queue" => :queue,
    "actor" => :actor,
    "person" => :actor,
    "cloud" => :external,
    "rectangle" => :system,
    "node" => :node,
    "frame" => :system,
    "folder" => :system,
    "package" => :system,
    "artifact" => :component,
    "file" => :component,
    "card" => :component,
    "agent" => :service,
    "hexagon" => :component,
    "stack" => :component,
    "usecase" => :component,
    "interface" => :boundary,
    "boundary" => :boundary,
    "control" => :component,
    "entity" => :component
  }

  @generic [:service, :system, :node, :component]

  @keywords Map.keys(@element_kinds) ++ ["together"]
  @re_keyword ~r/^(?<kw>#{Enum.join(@keywords, "|")})\b\s*(?<rest>.*)$/i
  @re_bracket ~r/^\[(?<label>[^\]]+)\](?:\s+as\s+(?<id>[^\s{]+))?/

  # rest de uma declaração, já sem estereótipo, cor e `{`
  @re_quoted_as ~r/^"(?<label>[^"]+)"\s+as\s+(?<id>[^\s"]+)$/
  @re_id_as_quoted ~r/^(?<id>[^\s"\[]+)\s+as\s+"(?<label>[^"]+)"$/
  @re_bracket_as ~r/^\[(?<label>[^\]]+)\]\s+as\s+(?<id>\S+)$/
  @re_id_as_bracket ~r/^(?<id>[^\s"\[]+)\s+as\s+\[(?<label>[^\]]+)\]$/
  @re_id_as_plain ~r/^(?<id>[^\s"\[]+)\s+as\s+(?<label>\S+)$/
  @re_quoted ~r/^"(?<label>[^"]+)"$/
  @re_bracket_only ~r/^\[(?<label>[^\]]+)\]$/
  @re_plain ~r/^(?<id>[^\s"\[]+)$/

  # `[Nome]` numa seta declara o componente na hora, como no PlantUML.
  @endpoint ~S{\[[^\]]+\]|"[^"]+"|[\w.\/-]+?}
  @re_edge Regex.compile!(
             "^(?<from>#{@endpoint})\\s*" <>
               ~S"(?<arrow>(?:<\|?|\(|o|\*|x|\}|\+|\^|#)?[-.=~]+(?:\[[^\]]*\])?(?:(?:up|down|left|right|le|ri|do|u|d|l|r)(?=[-.]))?[-.=~]*(?:\|?>|\)|o|\*|x|\{|\+|\^|#)?)" <>
               "\\s*(?<to>#{@endpoint})\\s*(?::\\s*(?<text>.*))?$"
           )

  @re_note_inline ~r/^note\s+(?:left|right|top|bottom)\s+of\s+(?<target>\S+)\s*:\s*(?<text>.+)$/i
  @re_note_open ~r/^note\s+(?:left|right|top|bottom)(?:\s+of\s+(?<target>\S+))?\s*$/i
  @re_note_floating ~r/^note\s+"(?<text>[^"]*)"(?:\s+as\s+\S+)?$/i

  @silent ~r/^(skinparam|!|hide|show|scale|header|footer|legend|endlegend|left to right|top to bottom|allowmixing|caption|newpage|\}\s*$)/i

  @label_kinds [
    {~r/\b(redis|cache|memcache|postgres|postgresql|mysql|mariadb|mongo|mongodb|dynamo|dynamodb|sqlite|oracle|database|banco|db|s3|bucket|elastic|elasticsearch|opensearch)\b/i,
     :database},
    {~r/\b(queue|fila|kafka|rabbit|rabbitmq|sqs|sns|pubsub|pub\/sub|nats|broker|topic|t[óo]pico)\b/i,
     :queue},
    {~r/\b(client|clients|cliente|clientes|user|users|usu[áa]rio|usu[áa]rios|consumer|consumers|consumidor|consumidores|browser|navegador)\b/i,
     :actor}
  ]

  @doc """
  É um diagrama de componentes? Colchetes (`[API]`), contêiner com `{` ou
  palavra-chave que só existe fora da sequência — e nenhuma que só existe nela.
  """
  @spec component?(String.t()) :: boolean()
  def component?(text) do
    component =
      text =~ ~r/^\s*\[[^\]]+\]/m or
        text =~
          ~r/^\s*(component|package|cloud|rectangle|node|frame|folder|interface|artifact|storage|usecase|agent|card|hexagon|stack|together)\b/im or
        text =~ ~r/^\s*(database|queue|actor)\b[^\n]*\{\s*$/im

    sequence =
      text =~
        ~r/^\s*(participant|activate|deactivate|autonumber|alt|else|loop|opt|par|critical|break|ref\s+over|return|box)\b|^\s*==/im

    component and not sequence
  end

  @spec convert(String.t()) :: {:ok, %{source: String.t(), warnings: list()}} | {:error, term()}
  def convert(text) when is_binary(text) do
    text
    |> strip_block_comments()
    |> String.split(~r/\r\n|\r|\n/)
    |> Enum.with_index(1)
    |> Enum.map(fn {line, n} -> {String.trim(line), n} end)
    |> Enum.reduce(
      %{b: Builder.kind(Builder.new(), :architecture), stack: [], groups: %{}, note: nil},
      &line/2
    )
    |> flush_note()
    |> Map.fetch!(:b)
    |> Builder.finish("PlantUML")
  end

  defp strip_block_comments(text), do: Regex.replace(~r{/'.*?'/}s, text, "")

  # Nota de várias linhas: acumula até `end note`.
  defp line({text, _n}, %{note: {target, lines, n0}} = st) do
    if text =~ ~r/^end\s*note$/i,
      do: flush_note(st),
      else: %{st | note: {target, lines ++ [text], n0}}
  end

  defp line({"", _n}, st), do: st
  defp line({"'" <> _, _n}, st), do: st

  defp line({text, n}, %{b: b} = st) do
    cond do
      text =~ ~r/^@(start|end)uml/i ->
        st

      caps = Regex.named_captures(~r/^title\s+(?<title>.+)$/i, text) ->
        %{st | b: Builder.title(b, caps["title"])}

      text =~ ~r/^\}\s*$/ ->
        close(st)

      caps = Regex.named_captures(@re_note_inline, text) ->
        %{st | b: note_warning(b, n, caps["target"], [caps["text"]])}

      caps = Regex.named_captures(@re_note_open, text) ->
        %{st | note: {caps["target"], [], n}}

      caps = Regex.named_captures(@re_note_floating, text) ->
        %{st | b: note_warning(b, n, nil, [caps["text"]])}

      caps = Regex.named_captures(@re_edge, text) ->
        edge(st, caps, n)

      caps = Regex.named_captures(@re_bracket, text) ->
        container_or_element(st, :service, "[#{caps["label"]}]" <> as(caps["id"]), text, n)

      caps = Regex.named_captures(@re_keyword, text) ->
        keyword(st, caps, text, n)

      text =~ @silent ->
        st

      true ->
        %{st | b: Builder.warn(b, n, "linha não reconhecida: `#{text}`")}
    end
  end

  defp as(nil), do: ""
  defp as(""), do: ""
  defp as(id), do: " as #{id}"

  defp keyword(st, caps, text, n) do
    kw = String.downcase(caps["kw"])

    if kw == "together" do
      open(st, nil, nil)
    else
      container_or_element(st, Map.fetch!(@element_kinds, kw), caps["rest"], text, n)
    end
  end

  # `package "X" {` abre grupo; `database "X" as db` declara um nó.
  defp container_or_element(st, kind, rest, text, n) do
    container? = String.ends_with?(text, "{")

    case name(tidy(rest)) do
      {id, label} when container? ->
        open(st, label || id, id)

      nil when container? ->
        open(st, nil, nil)

      {id, label} ->
        label = display(label || id)
        %{st | b: Builder.participant(st.b, key(id), label, refine(kind, label))}

      nil ->
        %{st | b: Builder.warn(st.b, n, "declaração não reconhecida: `#{text}`")}
    end
  end

  # Tira `{`, estereótipos (`<<banco>>`), cores (`#lightblue`) e `$tags`.
  defp tidy(rest) do
    rest
    |> String.replace(~r/\{\s*$/, "")
    |> String.replace(~r/<<[^>]*>>/, "")
    |> String.replace(~r/\s#[\w#;:.\-]+/, "")
    |> String.replace(~r/\s\$\w+/, "")
    |> String.trim()
  end

  # `{id, rótulo | nil}` — o id é o nome usado nas setas.
  defp name(""), do: nil

  defp name(rest) do
    cond do
      m = Regex.named_captures(@re_quoted_as, rest) -> {m["id"], m["label"]}
      m = Regex.named_captures(@re_id_as_quoted, rest) -> {m["id"], m["label"]}
      m = Regex.named_captures(@re_bracket_as, rest) -> {m["id"], m["label"]}
      m = Regex.named_captures(@re_id_as_bracket, rest) -> {m["id"], m["label"]}
      m = Regex.named_captures(@re_id_as_plain, rest) -> {m["id"], m["label"]}
      m = Regex.named_captures(@re_quoted, rest) -> {"[#{m["label"]}]", m["label"]}
      m = Regex.named_captures(@re_bracket_only, rest) -> {"[#{m["label"]}]", m["label"]}
      m = Regex.named_captures(@re_plain, rest) -> {m["id"], nil}
      true -> nil
    end
  end

  # Nome sem alias: o próprio `[Nome]`/`"Nome"` é a referência nas setas, e
  # vira id pelo texto de dentro.
  defp ref("[" <> _ = name), do: name |> String.trim_leading("[") |> String.trim_trailing("]")
  defp ref("\"" <> _ = name), do: String.trim(name, "\"")
  defp ref(name), do: name

  # O nome como o Builder conhece: sem colchetes/aspas, `\n` virando espaço.
  # Declaração e seta passam por aqui, então `[A\nB]` e `A\nB` são o mesmo nó.
  defp key(name), do: name |> ref() |> String.replace("\\n", " ") |> String.trim()

  defp display(label), do: key(label)

  defp refine(kind, label) when kind in @generic do
    Enum.find_value(@label_kinds, kind, fn {re, k} -> if label =~ re, do: k end)
  end

  defp refine(kind, _label), do: kind

  # ── contêineres ───────────────────────────────────────────────────────────

  defp open(st, label, alias_id) do
    label = label && display(label)
    groups = if alias_id, do: Map.put(st.groups, key(alias_id), label), else: st.groups
    stack = [label | st.stack]
    %{st | stack: stack, groups: groups, b: box(st.b, stack)}
  end

  defp close(%{stack: []} = st), do: st

  defp close(%{stack: [_ | rest]} = st), do: %{st | stack: rest, b: box(st.b, rest)}

  # O grupo de quem é declarado agora: o contêiner com nome mais de dentro.
  defp box(b, stack) do
    case Enum.find(stack, & &1) do
      nil -> Builder.close_box(b)
      label -> Builder.open_box(b, label)
    end
  end

  # ── setas ─────────────────────────────────────────────────────────────────

  defp edge(st, caps, n) do
    raw = caps["arrow"]
    {from, to} = {caps["from"], caps["to"]}
    shaft = Regex.replace(~r/\[([^\]]*)\]/, raw, "")

    style =
      case Regex.run(~r/\[([^\]]*)\]/, raw) do
        [_, s] -> String.downcase(s)
        _ -> ""
      end

    left_head? = shaft =~ ~r/^(<|\(|o|\*|x|\}|\+|\^|#)/
    right_head? = shaft =~ ~r/(>|\)|o|\*|x|\{|\+|\^|#)$/
    {from, to} = if left_head? and not right_head?, do: {to, from}, else: {from, to}

    arrow =
      cond do
        shaft =~ ~r/x$|^x/ -> :fail
        String.contains?(shaft, ".") or style =~ ~r/dash|dott/ -> :async
        true -> :sync
      end

    target_group = Enum.find([from, to], &Map.has_key?(st.groups, key(&1)))

    cond do
      target_group ->
        warn(st, n, "seta para o grupo `#{key(target_group)}` — ligue a um nó de dentro dele")

      true ->
        b =
          if left_head? and right_head?,
            do:
              Builder.warn(
                st.b,
                n,
                "seta de mão dupla `#{raw}` — convertida só no sentido de ida"
              ),
            else: st.b

        %{st | b: Builder.message(b, key(from), key(to), arrow, caps["text"])}
    end
  end

  defp warn(st, n, text), do: %{st | b: Builder.warn(st.b, n, text)}

  # ── notas ─────────────────────────────────────────────────────────────────

  defp flush_note(%{note: nil} = st), do: st

  defp flush_note(%{note: {target, lines, n}} = st),
    do: %{st | b: note_warning(st.b, n, target, lines), note: nil}

  defp note_warning(b, n, target, lines) do
    text =
      lines
      |> Enum.map(&(&1 |> String.trim() |> String.trim_leading("-") |> String.trim()))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("; ")

    about = if target, do: " sobre #{key(target)}", else: ""
    Builder.warn(b, n, "nota#{about} (a arquitetura não desenha notas): #{text}")
  end
end
