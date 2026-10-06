defmodule Brainagram.Domain.Diagramming.Dsl.SpansTest do
  @moduledoc """
  Fase A da spec 001: a AST sabe onde cada coisa está no texto.

  Aceite: para cada exemplo do catálogo, `Editor.replace/3` em qualquer span
  troca só aquele trecho — o resto do arquivo permanece byte a byte idêntico.
  E o span aponta para o lugar certo: o texto que ele cobre é o valor do campo.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Brainagram.Domain.Diagramming.Dsl.{Editor, Parser, Span}
  alias Brainagram.Test.{DslGenerators, Fixtures}

  @catalog ~w(checkout arquitetura cqrs minimo)

  defp assert_spans_exact(source) do
    {:ok, ast} = Parser.parse(source)

    for {span, expected} <- DslGenerators.expected_spans(ast), expected != nil do
      assert Span.slice(source, span) == expected,
             "span #{inspect(span)} cobre #{inspect(Span.slice(source, span))}, esperado #{inspect(expected)}"
    end

    ast
  end

  defp assert_only_span_changes(source, span, text) do
    edited = Editor.replace(source, span, text)
    stop = Span.stop(span)
    suffix = byte_size(source) - stop

    assert binary_part(edited, 0, span.offset) == binary_part(source, 0, span.offset)

    assert binary_part(edited, byte_size(edited) - suffix, suffix) ==
             binary_part(source, stop, suffix)

    assert binary_part(edited, span.offset, byte_size(text)) == text
  end

  describe "catálogo" do
    for slug <- @catalog do
      test "#{slug}: cada span cobre exatamente o seu campo" do
        assert_spans_exact(Fixtures.source(unquote(slug)))
      end

      test "#{slug}: trocar qualquer span não mexe em mais nada" do
        source = Fixtures.source(unquote(slug))
        {:ok, ast} = Parser.parse(source)
        spans = DslGenerators.editable_spans(ast)

        assert spans != []
        for span <- spans, do: assert_only_span_changes(source, span, "TROCADO")
      end
    end
  end

  describe "posições" do
    test "linha, coluna e offset em bytes, inclusive depois de acentos" do
      source = ~s(diagram sequence "Ação"\n  database pg "Pedidos"  # banco\n)
      {:ok, ast} = Parser.parse(source)
      [node] = ast.nodes

      assert %Span{line: 2, column: 3} = node.span
      assert %Span{line: 2, column: 16} = node.spans.label
      assert Span.slice(source, node.spans.label) == "Pedidos"
      assert Span.slice(source, node.span) == ~s(database pg "Pedidos")
      assert Span.slice(source, ast.spans.title) == "Ação"
    end

    test "\\r\\n não desloca os offsets" do
      source = "a -> b : um\r\nb --> a : dois\r\n"
      {:ok, ast} = Parser.parse(source)
      [%{items: [first]}, %{items: [second]}] = ast.steps

      assert Span.slice(source, first.spans.label) == "um"
      assert Span.slice(source, second.spans.arrow) == "-->"
      assert second.span.line == 2
    end

    test "nó criado só por aparecer numa seta não tem span" do
      {:ok, ast} = Parser.parse("a -> b")
      assert Enum.all?(ast.nodes, &is_nil(&1.span))
    end

    test "passos implícitos não têm span; explícitos têm abertura e fechamento" do
      {:ok, ast} = Parser.parse("x -> y\nstep \"S\" {\n  y -> x\n}")
      [implicit, explicit] = ast.steps

      assert implicit.implicit and is_nil(implicit.span)
      refute explicit.implicit
      assert explicit.span.line == 2
      assert explicit.end_span.line == 4
    end

    test "o bloco layout vira pinos com posição" do
      source = "a -> b\n\nlayout {\n  b at (40, 80)\n}\n"
      {:ok, ast} = Parser.parse(source)

      assert [%{id: "b", x: 40, y: 80} = pin] = ast.pins
      assert Span.slice(source, pin.spans.coords) == "(40, 80)"
      assert ast.layout_span.line == 3
      assert ast.layout_end_span.line == 5
    end

    test "posição fora do bloco layout é erro com linha" do
      assert {:error, [%{line: 1, message: msg}]} = Parser.parse("api at (1, 2)")
      assert msg =~ "layout"
    end
  end

  property "em qualquer fonte gerado, cada span cobre o seu campo" do
    check all(source <- DslGenerators.source(), max_runs: 200) do
      assert_spans_exact(source)
    end
  end
end
