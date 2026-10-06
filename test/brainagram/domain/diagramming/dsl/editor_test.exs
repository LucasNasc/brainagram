defmodule Brainagram.Domain.Diagramming.Dsl.EditorTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Brainagram.Domain.Diagramming.Dsl.{Editor, Span}
  alias Brainagram.Test.DslGenerators

  defp span_at(source, text) do
    {offset, length} = :binary.match(source, text)
    Span.new(1, offset + 1, offset, length)
  end

  describe "replace/3" do
    test "troca só o trecho" do
      source = ~s(service api "API"  # porta de entrada\n)

      assert Editor.replace(source, span_at(source, "API\""), "Gateway\"") ==
               ~s(service api "Gateway"  # porta de entrada\n)
    end
  end

  describe "insert_line/3 e insert_line_before/3" do
    test "entra logo depois da linha do span" do
      assert Editor.insert_line("a\nb\nc", span_at("a\nb\nc", "b"), "X") == "a\nb\nX\nc"
    end

    test "depois da última linha, com ou sem quebra final" do
      assert Editor.insert_line("a\nb", span_at("a\nb", "b"), "X") == "a\nb\nX"
      assert Editor.insert_line("a\nb\n", span_at("a\nb\n", "b"), "X") == "a\nb\nX\n"
    end

    test "entra antes da linha do span" do
      assert Editor.insert_line_before("a\n}\n", span_at("a\n}\n", "}"), "  X") == "a\n  X\n}\n"
    end

    test "respeita \\r\\n" do
      source = "a\r\nb\r\n"
      assert Editor.insert_line(source, span_at(source, "a"), "X") == "a\r\nX\r\nb\r\n"
    end
  end

  describe "remove_line/2" do
    test "linha do meio sai com a sua quebra" do
      assert Editor.remove_line("a\nb\nc\n", span_at("a\nb\nc\n", "b")) == "a\nc\n"
    end

    test "última linha sem quebra leva a quebra anterior" do
      assert Editor.remove_line("a\nb", span_at("a\nb", "b")) == "a"
    end

    test "arquivo de uma linha só fica vazio" do
      assert Editor.remove_line("a -> b", span_at("a -> b", "a -> b")) == ""
    end

    test "o comentário da linha vai junto, os outros ficam" do
      source = "# topo\na -> b # tchau\nb -> c # fica\n"
      assert Editor.remove_line(source, span_at(source, "a -> b")) == "# topo\nb -> c # fica\n"
    end

    test "respeita \\r\\n" do
      assert Editor.remove_line("a\r\nb\r\nc", span_at("a\r\nb\r\nc", "b")) == "a\r\nc"
    end
  end

  describe "append_line/2" do
    test "mantém o arquivo terminando como terminava" do
      assert Editor.append_line("a\n", "b") == "a\nb\n"
      assert Editor.append_line("a", "b") == "a\nb"
      assert Editor.append_line("", "b") == "b"
    end
  end

  test "indentation/2 devolve os espaços do começo da linha" do
    source = "step \"x\" {\n\t  a -> b\n}"
    assert Editor.indentation(source, span_at(source, "a -> b")) == "\t  "
  end

  property "edição cirúrgica só toca o span informado" do
    check all({source, span, novo} <- DslGenerators.edit(), max_runs: 300) do
      editado = Editor.replace(source, span, novo)

      assert fora_do_span(source, span) ==
               fora_do_span(editado, %{span | length: byte_size(novo)})
    end
  end

  defp fora_do_span(text, span) do
    stop = Span.stop(span)
    {binary_part(text, 0, span.offset), binary_part(text, stop, byte_size(text) - stop)}
  end
end
