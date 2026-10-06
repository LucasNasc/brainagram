defmodule Brainagram.Domain.Diagramming.Layout.Hints do
  @moduledoc """
  Posições fixadas à mão — o bloco `layout { }` do fonte.

      layout {
        pg at (420, 680)
        mq at (700, 420)
      }

  Duas faces:

    * `from_ast/1` extrai o que os motores de layout precisam: `%Hints{pinned:
      %{id => {x, y}}}`. Nó ausente do bloco é posicionado pelo automático;
      nó presente fica exatamente onde foi solto.
    * `pin/3`, `unpin/2` e `clear/1` reescrevem o fonte. O bloco fica **no fim
      do arquivo** para que uma sessão de arrastar mexa num trecho só, e a
      narrativa (nós, passos) continue sem coordenadas no meio.

  `unpin/2` é o inverso exato de `pin/3` para um nó que não estava fixado:
  `source |> pin(id, pos) |> unpin(id) == source`, byte a byte. É o que faz
  "arrastar e desfazer" não sujar o diff.
  """

  alias Brainagram.Domain.Diagramming.Dsl.{Ast, Editor, Parser, Printer, Span}

  defstruct pinned: %{}

  @type point :: {integer(), integer()}
  @type t :: %__MODULE__{pinned: %{String.t() => point()}}

  @doc "As posições fixadas, só para nós que existem — pino órfão é ignorado."
  @spec from_ast(Ast.t()) :: t()
  def from_ast(%Ast{pins: pins, nodes: nodes}) do
    ids = MapSet.new(nodes, & &1.id)

    pinned =
      for pin <- pins, MapSet.member?(ids, pin.id), into: %{}, do: {pin.id, {pin.x, pin.y}}

    %__MODULE__{pinned: pinned}
  end

  @spec pinned?(t(), String.t()) :: boolean()
  def pinned?(%__MODULE__{pinned: pinned}, id), do: Map.has_key?(pinned, id)

  @doc """
  Fixa `id` em `{x, y}`: atualiza a linha se o nó já está no bloco, acrescenta
  uma linha ao bloco se ele existe, ou cria o bloco no fim do arquivo.

  Fonte inválido volta intacto — não há como saber onde está o bloco.
  """
  @spec pin(String.t(), String.t(), point()) :: String.t()
  def pin(source, id, {x, y}) do
    line = Printer.pin({id, {round(x), round(y)}})

    case Parser.parse(source) do
      {:ok, %Ast{} = ast} ->
        case Enum.find(ast.pins, &(&1.id == id)) do
          %{spans: %{coords: %Span{} = coords}} ->
            Editor.replace(source, coords, "(#{round(x)}, #{round(y)})")

          nil ->
            add_to_block(source, ast, line)
        end

      {:error, _} ->
        source
    end
  end

  @doc "Solta `id`. Se era o único pino, o bloco inteiro sai — com o espaço que `pin/3` criou."
  @spec unpin(String.t(), String.t()) :: String.t()
  def unpin(source, id) do
    with {:ok, %Ast{} = ast} <- Parser.parse(source),
         %{span: %Span{} = span} <- Enum.find(ast.pins, &(&1.id == id)) do
      if length(ast.pins) == 1,
        do: remove_block(source, ast),
        else: Editor.remove_line(source, span)
    else
      _ -> source
    end
  end

  @doc "Apaga o bloco `layout` inteiro: tudo volta ao layout automático."
  @spec clear(String.t()) :: String.t()
  def clear(source) do
    case Parser.parse(source) do
      {:ok, %Ast{layout_span: %Span{}} = ast} -> remove_block(source, ast)
      _ -> source
    end
  end

  # ── privados ──────────────────────────────────────────────────────────────

  defp add_to_block(source, %Ast{layout_end_span: %Span{} = close} = ast, line) do
    indent =
      case ast.pins do
        [] -> Editor.indentation(source, ast.layout_span) <> "  "
        pins -> Editor.indentation(source, List.last(pins).span)
      end

    Editor.insert_line_before(source, close, indent <> line)
  end

  defp add_to_block(source, _ast, line) do
    nl = Editor.newline(source)
    block = Enum.join(["layout {", "  " <> line, "}"], nl)

    cond do
      source == "" -> block <> nl
      Editor.ends_with_newline?(source) -> source <> nl <> block <> nl
      true -> source <> nl <> nl <> block
    end
  end

  # Remove do cabeçalho `layout {` até o `}` e, junto, a linha em branco que
  # separava o bloco do resto — o inverso do que `add_to_block/3` acrescenta.
  defp remove_block(source, %Ast{layout_span: open, layout_end_span: close}) do
    {start, _stop, _next} = Editor.line_bounds(source, open.offset)
    {_start, stop, next} = Editor.line_bounds(source, close.offset)
    ended_with_newline? = next > stop

    head = binary_part(source, 0, start)
    tail = binary_part(source, next, byte_size(source) - next)

    # No fim do arquivo, o bloco veio com um separador: uma linha em branco antes
    # (arquivo que terminava com quebra) ou duas quebras (arquivo que não
    # terminava). Tirar exatamente isso é o que devolve o fonte original.
    head =
      cond do
        tail != "" -> head
        ended_with_newline? and blank_line_at_end?(head) -> chop_newline(head)
        ended_with_newline? -> head
        true -> head |> chop_newline() |> chop_newline()
      end

    head <> tail
  end

  defp chop_newline(text) do
    cond do
      String.ends_with?(text, "\r\n") -> binary_part(text, 0, byte_size(text) - 2)
      String.ends_with?(text, "\n") -> binary_part(text, 0, byte_size(text) - 1)
      String.ends_with?(text, "\r") -> binary_part(text, 0, byte_size(text) - 1)
      true -> text
    end
  end

  defp blank_line_at_end?(text) do
    String.ends_with?(text, "\n\n") or String.ends_with?(text, "\r\n\r\n") or
      String.ends_with?(text, "\r\r")
  end
end
