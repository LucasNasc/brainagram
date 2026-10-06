defmodule Brainagram.Domain.Diagramming.Dsl.Editor do
  @moduledoc """
  Edições cirúrgicas sobre o fonte.

  Cada função aplica o **menor patch possível**: trocar um rótulo altera os
  bytes daquele rótulo e nada mais. Comentários, alinhamento e ordem das
  declarações ficam intactos — é o que mantém o diff de "arrastei uma caixa"
  do tamanho do gesto, e não do arquivo.

  Todas são funções puras `texto -> texto`, sem estado e sem parse: quem chama
  já tem os `%Span{}` (vindos da AST) e decide *o que* mudar; aqui só se decide
  *como* mudar os bytes. A validação do resultado é de quem chama — ver
  `Brainagram.Domain.Diagramming.Authoring`.

  A quebra de linha inserida segue a do próprio arquivo (`\\r\\n` ou `\\n`).
  """

  alias Brainagram.Domain.Diagramming.Dsl.Span

  @doc "Troca o trecho coberto pelo span por `text`."
  @spec replace(String.t(), Span.t(), String.t()) :: String.t()
  def replace(source, %Span{} = span, text) when is_binary(text) do
    head = binary_part(source, 0, span.offset)
    tail = binary_part(source, Span.stop(span), byte_size(source) - Span.stop(span))
    head <> text <> tail
  end

  @doc "Insere `text` na posição `offset`, sem quebra de linha."
  @spec insert_at(String.t(), non_neg_integer(), String.t()) :: String.t()
  def insert_at(source, offset, text) do
    binary_part(source, 0, offset) <>
      text <> binary_part(source, offset, byte_size(source) - offset)
  end

  @doc "Insere `text` como uma linha nova logo depois da linha que contém o span."
  @spec insert_line(String.t(), Span.t(), String.t()) :: String.t()
  def insert_line(source, %Span{} = after_span, text) do
    nl = newline(source)
    {_start, stop, _next} = line_bounds(source, Span.stop(after_span))
    insert_at(source, stop, nl <> text)
  end

  @doc "Insere `text` como uma linha nova logo antes da linha que contém o span."
  @spec insert_line_before(String.t(), Span.t(), String.t()) :: String.t()
  def insert_line_before(source, %Span{} = span, text) do
    {start, _stop, _next} = line_bounds(source, span.offset)
    insert_at(source, start, text <> newline(source))
  end

  @doc "Acrescenta `text` como última linha, preservando se o arquivo termina com quebra."
  @spec append_line(String.t(), String.t()) :: String.t()
  def append_line("", text), do: text

  def append_line(source, text) do
    nl = newline(source)

    if ends_with_newline?(source),
      do: source <> text <> nl,
      else: source <> nl <> text
  end

  @doc """
  Remove as linhas inteiras que o span toca, com a quebra de linha delas.

  Na última linha do arquivo quem sai é a quebra *anterior* — senão sobraria
  uma linha em branco no fim onde antes não havia.
  """
  @spec remove_line(String.t(), Span.t()) :: String.t()
  def remove_line(source, %Span{} = span) do
    {start, _stop, _next} = line_bounds(source, span.offset)
    {_start, stop, next} = line_bounds(source, max(Span.stop(span) - 1, span.offset))

    cond do
      next < byte_size(source) or stop < next ->
        cut(source, start, next)

      start > 0 ->
        # última linha sem quebra final: leva junto a quebra que a precedia
        cut(source, start - newline_before_length(source, start), stop)

      true ->
        cut(source, start, stop)
    end
  end

  @doc "Remove as linhas de `from` até `to` (inclusive), como `remove_line/2`."
  @spec remove_lines(String.t(), Span.t(), Span.t()) :: String.t()
  def remove_lines(source, %Span{} = from, %Span{} = to) do
    remove_line(source, %Span{from | length: Span.stop(to) - from.offset})
  end

  @doc "A indentação (espaços e tabs) da linha que contém o span."
  @spec indentation(String.t(), Span.t()) :: String.t()
  def indentation(source, %Span{} = span) do
    {start, stop, _next} = line_bounds(source, span.offset)
    line = binary_part(source, start, stop - start)
    [indent] = Regex.run(~r/^[ \t]*/, line)
    indent
  end

  @doc """
  Limites da linha que contém `offset`: `{início, fim_sem_quebra, início_da_próxima}`.
  """
  @spec line_bounds(String.t(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def line_bounds(source, offset) do
    size = byte_size(source)
    offset = min(max(offset, 0), size)

    start =
      case :binary.matches(binary_part(source, 0, offset), ["\n", "\r"]) do
        [] -> 0
        matches -> matches |> List.last() |> then(fn {pos, len} -> pos + len end)
      end

    rest = binary_part(source, offset, size - offset)

    case :binary.match(rest, ["\r\n", "\n", "\r"]) do
      :nomatch -> {start, size, size}
      {pos, len} -> {start, offset + pos, offset + pos + len}
    end
  end

  @doc "A quebra de linha usada no arquivo — `\\n` quando não há nenhuma."
  @spec newline(String.t()) :: String.t()
  def newline(source) do
    case :binary.match(source, ["\r\n", "\n", "\r"]) do
      :nomatch -> "\n"
      {pos, len} -> binary_part(source, pos, len)
    end
  end

  @spec ends_with_newline?(String.t()) :: boolean()
  def ends_with_newline?(source),
    do: String.ends_with?(source, "\n") or String.ends_with?(source, "\r")

  defp cut(source, from, to) do
    binary_part(source, 0, from) <> binary_part(source, to, byte_size(source) - to)
  end

  defp newline_before_length(source, start) do
    if start >= 2 and binary_part(source, start - 2, 2) == "\r\n", do: 2, else: 1
  end
end
