defmodule Brainagram.Domain.Diagramming.Import.Mermaid do
  @moduledoc """
  `sequenceDiagram` do Mermaid → DSL do Brainagram. `flowchart` e `graph` vão
  para `Import.MermaidFlowchart`, que gera arquitetura.

  Cobertura (spec 001, §9): participantes e atores (com `as` e com o tipo
  `@{ "type": "database" }`), `box` como grupo, mensagens síncronas (`->>`,
  `->`), retornos (`-->>`, `-->`), assíncronas (`-)`, `--)`), falhas (`-x`,
  `--x`), `Note over/left of/right of`, `title`, e `loop`/`alt`/`else`/`opt`/
  `critical`/`option`/`break` como passos.

  Ficam de fora, com aviso no topo do arquivo: `par`/`and` (paralelismo),
  `rect` (destaque), `destroy`, `link`/`links`, setas bidirecionais e qualquer
  linha não reconhecida. As mensagens de dentro desses blocos **não se perdem**
  — só a semântica do bloco.
  """

  alias Brainagram.Domain.Diagramming.Import.{Builder, MermaidFlowchart}

  @kind_types %{
    "actor" => :actor,
    "participant" => :participant,
    "boundary" => :boundary,
    "control" => :component,
    "entity" => :component,
    "database" => :database,
    "collections" => :database,
    "queue" => :queue
  }

  @re_participant ~r/^(?:create\s+)?(?<kind>participant|actor)\s+(?<rest>.+)$/i
  @re_alias ~r/^(?<name>.+?)\s+as\s+(?<label>.+)$/
  @re_type ~r/@\{[^}]*?"?type"?\s*:\s*"?(?<type>\w+)"?[^}]*\}/
  @re_message ~r/^(?<from>[^\s:>-][^:>]*?)\s*(?<arrow>-->>|->>|--x|-x|--\)|-\)|-->|->)\s*(?<act>[+-]?)\s*(?<to>[^:]+?)\s*(?::\s*(?<text>.*))?$/
  @re_bidirectional ~r/<<-->>|<<->>/
  @re_note ~r/^note\s+(?<placement>over|left of|right of)\s+(?<targets>[^:]+?)\s*:\s*(?<text>.*)$/i
  @re_block ~r/^(?<kw>loop|alt|opt|critical|break)\b\s*(?<label>.*)$/i
  @re_branch ~r/^(?<kw>else|option)\b\s*(?<label>.*)$/i
  @re_unsupported_block ~r/^(?<kw>par|rect)\b\s*(?<label>.*)$/i
  @re_box ~r/^box\b\s*(?<label>.*)$/i
  @colors ~r/^(?:transparent|aqua|purple|grey|gray|green|blue|red|yellow|orange|pink|white|black|lightblue|lightgreen|lightyellow|rgba?\([^)]*\)|#[0-9a-f]{3,8})\s+/i

  @spec convert(String.t()) :: {:ok, %{source: String.t(), warnings: list()}} | {:error, term()}
  def convert(text) when is_binary(text) do
    lines =
      text
      |> String.split(~r/\r\n|\r|\n/)
      |> Enum.with_index(1)
      |> Enum.map(fn {line, n} -> {String.trim(line), n} end)

    {front, rest} = front_matter(lines)

    case Enum.drop_while(rest, fn {line, _} -> line == "" or String.starts_with?(line, "%%") end) do
      [{header, hn} | body] ->
        cond do
          header =~ ~r/^sequenceDiagram\b/i ->
            front
            |> Enum.reduce(Builder.new(), &front_line/2)
            |> then(fn b -> Enum.reduce(body, {b, []}, &line/2) end)
            |> elem(0)
            |> Builder.finish("Mermaid")

          header =~ ~r/^(?:flowchart(?:-elk)?|graph)\b/i ->
            front
            |> Enum.reduce(Builder.new(), &front_line/2)
            |> MermaidFlowchart.convert({header, hn}, body)

          true ->
            {:error, :nothing_to_import}
        end

      [] ->
        {:error, :nothing_to_import}
    end
  end

  # `---\ntitle: X\n---` antes do diagrama
  defp front_matter([{"---", _} | rest]) do
    {inside, after_} = Enum.split_while(rest, fn {line, _} -> line != "---" end)
    {inside, Enum.drop(after_, 1)}
  end

  defp front_matter(lines), do: {[], lines}

  defp front_line({line, _n}, b) do
    case Regex.run(~r/^title:\s*(.+)$/i, line) do
      [_, title] -> Builder.title(b, String.trim(title, "\""))
      nil -> b
    end
  end

  # O estado carrega a pilha de blocos abertos para saber o que cada `end` fecha.
  defp line({"", _n}, acc), do: acc
  defp line({"%%" <> _, _n}, acc), do: acc

  defp line({text, n}, {b, stack}) do
    cond do
      text =~ ~r/^end$/i ->
        case stack do
          [:box | rest] -> {Builder.close_box(b), rest}
          [:unsupported | rest] -> {b, rest}
          [:block | rest] -> {Builder.close(b), rest}
          [] -> {Builder.warn(b, n, "`end` sem bloco aberto"), []}
        end

      caps = Regex.named_captures(~r/^title\s+(?<title>.+)$/i, text) ->
        {Builder.title(b, caps["title"]), stack}

      caps = Regex.named_captures(@re_participant, text) ->
        {participant(b, caps), stack}

      caps = Regex.named_captures(@re_box, text) ->
        {Builder.open_box(b, caps["label"] |> String.replace(@colors, "") |> blank_to("Grupo")),
         [:box | stack]}

      caps = Regex.named_captures(@re_block, text) ->
        {Builder.open(b, blank_to(caps["label"], caps["kw"])), [:block | stack]}

      caps = Regex.named_captures(@re_branch, text) ->
        {Builder.branch(b, blank_to(caps["label"], "senão")), stack}

      caps = Regex.named_captures(@re_unsupported_block, text) ->
        warning =
          case String.downcase(caps["kw"]) do
            "par" -> "`par` / `and` (paralelismo) — vire `step` manualmente"
            "rect" -> "`rect` (destaque de fundo) — o conteúdo foi mantido"
          end

        {Builder.warn(b, n, warning), [:unsupported | stack]}

      text =~ ~r/^and\b/i ->
        {b, stack}

      caps = Regex.named_captures(@re_note, text) ->
        {note(b, caps), stack}

      text =~ @re_bidirectional ->
        {Builder.warn(b, n, "seta bidirecional `#{text}` — escreva as duas mensagens"), stack}

      caps = Regex.named_captures(@re_message, text) ->
        {message(b, caps), stack}

      text =~ ~r/^(autonumber|activate|deactivate)\b/i ->
        {b, stack}

      text =~ ~r/^destroy\b/i ->
        {Builder.warn(b, n, "`#{text}` — o Brainagram não remove participantes no meio"), stack}

      text =~ ~r/^links?\b/i ->
        {Builder.warn(b, n, "`#{text}` — links de participante não são suportados"), stack}

      true ->
        {Builder.warn(b, n, "linha não reconhecida: `#{text}`"), stack}
    end
  end

  defp participant(b, caps) do
    rest = caps["rest"]
    type = Regex.named_captures(@re_type, rest)
    rest = Regex.replace(@re_type, rest, "") |> String.trim()

    kind =
      case type do
        %{"type" => t} -> Map.get(@kind_types, String.downcase(t), :participant)
        nil -> if String.downcase(caps["kind"]) == "actor", do: :actor, else: :participant
      end

    case Regex.named_captures(@re_alias, rest) do
      %{"name" => name, "label" => label} -> Builder.participant(b, name, label, kind)
      nil -> Builder.participant(b, rest, nil, kind)
    end
  end

  defp message(b, caps) do
    arrow =
      case caps["arrow"] do
        a when a in ["->>", "->"] -> :sync
        a when a in ["-->>", "-->"] -> :return
        a when a in ["-)", "--)"] -> :async
        a when a in ["-x", "--x"] -> :fail
      end

    Builder.message(b, caps["from"], caps["to"], arrow, caps["text"])
  end

  defp note(b, caps) do
    placement =
      case String.downcase(caps["placement"]) do
        "over" -> :over
        "left of" -> :left
        "right of" -> :right
      end

    targets = caps["targets"] |> String.split(",") |> Enum.map(&String.trim/1)
    Builder.note(b, placement, targets, caps["text"])
  end

  defp blank_to(text, default) do
    case String.trim(text || "") do
      "" -> default
      t -> t
    end
  end
end
