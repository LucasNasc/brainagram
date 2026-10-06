defmodule Brainagram.Domain.Diagramming.Import.PlantUml do
  @moduledoc """
  Diagrama de sequência do PlantUML → DSL do Brainagram. Diagrama de
  componentes (`[API]`, `package { }`, `cloud`…) vai para
  `Import.PlantUmlComponent`, que gera arquitetura.

  Cobertura: `participant`, `actor`, `boundary`, `control`, `entity`,
  `database`, `collections`, `queue` (com `"Nome" as id`, `id as "Nome"` e
  estereótipos/cores ignorados), `box` como grupo, mensagens `->`, `-->`,
  `->>`, `->x`, setas invertidas (`<-`, `<--`), cores de seta (`-[#red]>`),
  notas de uma e de várias linhas, `title`, `== seção ==` como passo e
  `alt`/`else`/`opt`/`loop`/`group`/`critical`/`break` como passos.

  Ficam de fora, com aviso: `par`, `ref over`, atrasos (`...`), `return` e
  linhas não reconhecidas. Diretivas de aparência (`skinparam`, `!theme`,
  `hide`, `autonumber`, `activate`…) são ignoradas sem aviso — não carregam
  conteúdo.
  """

  alias Brainagram.Domain.Diagramming.Import.{Builder, PlantUmlComponent}

  @kinds %{
    "participant" => :participant,
    "actor" => :actor,
    "boundary" => :boundary,
    "control" => :component,
    "entity" => :component,
    "database" => :database,
    "collections" => :database,
    "queue" => :queue
  }

  @re_decl ~r/^(?<kind>participant|actor|boundary|control|entity|database|collections|queue)\s+(?<rest>.+)$/i
  # `"Nome Longo" as id`, `id as "Nome Longo"` e `Nome as id` (sem aspas, o
  # segundo é o id usado nas mensagens).
  @re_quoted_as ~r/^"(?<label>[^"]+)"\s+as\s+(?<id>[^\s<#]+)/
  @re_as_quoted ~r/^(?<id>[^\s"]+)\s+as\s+"(?<label>[^"]+)"/
  @re_as_plain ~r/^(?<label>[^\s"]+)\s+as\s+(?<id>[^\s<#"]+)/
  @re_plain ~r/^(?<id>"[^"]+"|[^\s<#]+)/
  @re_message ~r/^(?<from>"[^"]+"|[\w.]+)\s*(?<arrow>[<ox\\\/]*-{1,2}(?:\[[^\]]*\])?-?[>ox\\\/]*)\s*(?<to>"[^"]+"|[\w.]+)\s*(?::\s*(?<text>.*))?$/
  @re_note_inline ~r/^note\s+(?<placement>over|left of|right of|left|right)\s+(?<targets>[^:]+?)\s*:\s*(?<text>.*)$/i
  @re_note_open ~r/^note\s+(?<placement>over|left of|right of|left|right)\s+(?<targets>.+)$/i
  @re_block ~r/^(?<kw>alt|opt|loop|group|critical|break)\b\s*(?<label>.*)$/i
  @re_else ~r/^else\b\s*(?<label>.*)$/i
  @re_section ~r/^==+\s*(?<label>.*?)\s*==+$/
  @re_box ~r/^box\b\s*(?<label>.*)$/i

  @silent ~r/^(skinparam|!|hide|show|autonumber|activate|deactivate|destroy|create|scale|header|footer|legend|endlegend|newpage|\|\|\||left to right|top to bottom)/i

  @spec convert(String.t()) :: {:ok, %{source: String.t(), warnings: list()}} | {:error, term()}
  def convert(text) when is_binary(text) do
    if PlantUmlComponent.component?(text),
      do: PlantUmlComponent.convert(text),
      else: convert_sequence(text)
  end

  defp convert_sequence(text) do
    text
    |> strip_block_comments()
    |> String.split(~r/\r\n|\r|\n/)
    |> Enum.with_index(1)
    |> Enum.map(fn {line, n} -> {String.trim(line), n} end)
    |> Enum.reduce(%{b: Builder.new(), stack: [], note: nil}, &line/2)
    |> flush_note()
    |> Map.fetch!(:b)
    |> Builder.finish("PlantUML")
  end

  defp strip_block_comments(text), do: Regex.replace(~r{/'.*?'/}s, text, "")

  # Nota de várias linhas: acumula até `end note`.
  defp line({text, _n}, %{note: {placement, targets, lines}} = st) do
    if text =~ ~r/^end\s*note$/i,
      do: flush_note(st),
      else: %{st | note: {placement, targets, lines ++ [text]}}
  end

  defp line({"", _n}, st), do: st
  defp line({"'" <> _, _n}, st), do: st

  defp line({text, n}, %{b: b, stack: stack} = st) do
    cond do
      text =~ ~r/^@(start|end)uml/i ->
        st

      caps = Regex.named_captures(~r/^title\s+(?<title>.+)$/i, text) ->
        %{st | b: Builder.title(b, caps["title"])}

      text =~ ~r/^end\s*box$/i ->
        %{st | b: Builder.close_box(b)}

      text =~ ~r/^end$/i ->
        case stack do
          [:unsupported | rest] -> %{st | stack: rest}
          [:block | rest] -> %{st | b: Builder.close(b), stack: rest}
          [] -> %{st | b: Builder.warn(b, n, "`end` sem bloco aberto")}
        end

      caps = Regex.named_captures(@re_box, text) ->
        label =
          caps["label"] |> String.replace(~r/#\w+/, "") |> String.trim() |> String.trim("\"")

        %{st | b: Builder.open_box(b, if(label == "", do: "Grupo", else: label))}

      caps = Regex.named_captures(@re_decl, text) ->
        %{st | b: declare(b, caps)}

      caps = Regex.named_captures(@re_section, text) ->
        %{st | b: Builder.section(b, caps["label"])}

      caps = Regex.named_captures(@re_block, text) ->
        label = blank_to(caps["label"], caps["kw"])
        %{st | b: Builder.open(b, label), stack: [:block | stack]}

      caps = Regex.named_captures(@re_else, text) ->
        %{st | b: Builder.branch(b, blank_to(caps["label"], "senão"))}

      text =~ ~r/^par\b/i ->
        %{
          st
          | b: Builder.warn(b, n, "`par` (paralelismo) — vire `step` manualmente"),
            stack: [:unsupported | stack]
        }

      text =~ ~r/^ref\s+over\b/i ->
        %{st | b: Builder.warn(b, n, "`ref over` (referência a outro diagrama) não é suportado")}

      text =~ ~r/^\.\.\./ ->
        %{st | b: Builder.warn(b, n, "atraso `#{text}` — o Brainagram não tem pausa na timeline")}

      text =~ ~r/^return\b/i ->
        %{st | b: Builder.warn(b, n, "`#{text}` — escreva o retorno como `B --> A : …`")}

      caps = Regex.named_captures(@re_note_inline, text) ->
        %{
          st
          | b:
              Builder.note(
                b,
                placement(caps["placement"]),
                targets(caps["targets"]),
                caps["text"]
              )
        }

      caps = Regex.named_captures(@re_note_open, text) ->
        %{st | note: {placement(caps["placement"]), targets(caps["targets"]), []}}

      caps = Regex.named_captures(@re_message, text) ->
        %{st | b: message(b, caps, n)}

      text =~ @silent ->
        st

      true ->
        %{st | b: Builder.warn(b, n, "linha não reconhecida: `#{text}`")}
    end
  end

  defp flush_note(%{note: nil} = st), do: st

  defp flush_note(%{note: {placement, targets, lines}} = st) do
    %{st | b: Builder.note(st.b, placement, targets, Enum.join(lines, " ")), note: nil}
  end

  defp declare(b, caps) do
    kind = Map.fetch!(@kinds, String.downcase(caps["kind"]))
    rest = caps["rest"]

    cond do
      m = Regex.named_captures(@re_quoted_as, rest) ->
        Builder.participant(b, m["id"], m["label"], kind)

      m = Regex.named_captures(@re_as_quoted, rest) ->
        Builder.participant(b, m["id"], m["label"], kind)

      m = Regex.named_captures(@re_as_plain, rest) ->
        Builder.participant(b, m["id"], m["label"], kind)

      m = Regex.named_captures(@re_plain, rest) ->
        Builder.participant(b, unquote_name(m["id"]), nil, kind)

      true ->
        b
    end
  end

  defp message(b, caps, n) do
    raw = caps["arrow"]
    arrow = Regex.replace(~r/\[[^\]]*\]/, raw, "")
    {from, to} = {unquote_name(caps["from"]), unquote_name(caps["to"])}
    {from, to} = if String.starts_with?(arrow, "<"), do: {to, from}, else: {from, to}

    kind =
      cond do
        String.contains?(arrow, "x") -> :fail
        String.contains?(arrow, ">>") or String.contains?(arrow, "<<") -> :async
        String.contains?(arrow, "--") -> :return
        String.contains?(arrow, ">") or String.contains?(arrow, "<") -> :sync
        true -> nil
      end

    if kind,
      do: Builder.message(b, from, to, kind, caps["text"]),
      else: Builder.warn(b, n, "seta `#{raw}` não reconhecida")
  end

  defp placement(p) do
    case String.downcase(p) do
      "over" -> :over
      "left" <> _ -> :left
      "right" <> _ -> :right
    end
  end

  defp targets(text),
    do: text |> String.split(",") |> Enum.map(&(&1 |> String.trim() |> unquote_name()))

  defp unquote_name("\"" <> _ = name), do: String.trim(name, "\"")
  defp unquote_name(name), do: name

  defp blank_to(text, default) do
    case String.trim(text || "") do
      "" -> default
      t -> t
    end
  end
end
