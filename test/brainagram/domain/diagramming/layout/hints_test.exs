defmodule Brainagram.Domain.Diagramming.Layout.HintsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Brainagram.Domain.Diagramming.Dsl.Parser
  alias Brainagram.Domain.Diagramming.Layout.Hints
  alias Brainagram.Test.DslGenerators

  @base "diagram architecture \"X\"\n\nservice api \"API\"\ndatabase pg \"PG\"\n\napi -> pg : SELECT\n"

  describe "pin/3" do
    test "sem bloco, cria um no fim do arquivo" do
      assert Hints.pin(@base, "pg", {420, 680}) ==
               @base <> "\nlayout {\n  pg at (420, 680)\n}\n"
    end

    test "com bloco, acrescenta uma linha antes do `}` com a indentação dele" do
      source = @base <> "\nlayout {\n    api at (1, 2)\n}\n"

      assert Hints.pin(source, "pg", {3, 4}) ==
               @base <> "\nlayout {\n    api at (1, 2)\n    pg at (3, 4)\n}\n"
    end

    test "nó já fixado: troca só as coordenadas" do
      source = @base <> "\nlayout {\n  pg at (1, 2)   # antes\n}\n"

      assert Hints.pin(source, "pg", {10, 20}) ==
               @base <> "\nlayout {\n  pg at (10, 20)   # antes\n}\n"
    end

    test "arredonda coordenadas fracionárias" do
      assert Hints.pin(@base, "pg", {10.4, 19.6}) =~ "pg at (10, 20)"
    end
  end

  describe "unpin/2 e clear/1" do
    test "soltar o último pino remove o bloco e o espaço que ele trouxe" do
      assert @base |> Hints.pin("pg", {1, 2}) |> Hints.unpin("pg") == @base
    end

    test "soltar um de dois pinos remove só a linha dele" do
      source = @base <> "\nlayout {\n  api at (1, 2)\n  pg at (3, 4)\n}\n"
      assert Hints.unpin(source, "pg") == @base <> "\nlayout {\n  api at (1, 2)\n}\n"
    end

    test "clear/1 apaga o bloco inteiro" do
      source = @base <> "\nlayout {\n  api at (1, 2)\n  pg at (3, 4)\n}\n"
      assert Hints.clear(source) == @base
    end

    test "sem bloco, clear/1 não muda nada" do
      assert Hints.clear(@base) == @base
    end
  end

  test "from_ast/1 ignora pino de nó que não existe mais" do
    {:ok, ast} = Parser.parse("a -> b\nlayout {\n  b at (1, 2)\n  sumiu at (3, 4)\n}")
    assert Hints.from_ast(ast).pinned == %{"b" => {1, 2}}
  end

  property "arrastar e desfazer volta ao byte original" do
    check all({source, node_id, posicao} <- DslGenerators.drag(), max_runs: 300) do
      assert source == source |> Hints.pin(node_id, posicao) |> Hints.unpin(node_id)
    end
  end

  property "fixar produz um fonte válido com o nó na posição pedida" do
    check all({source, node_id, {x, y}} <- DslGenerators.drag(), max_runs: 150) do
      assert {:ok, ast} = source |> Hints.pin(node_id, {x, y}) |> Parser.parse()
      assert Hints.from_ast(ast).pinned[node_id] == {x, y}
    end
  end
end
