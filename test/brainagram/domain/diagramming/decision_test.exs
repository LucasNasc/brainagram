defmodule Brainagram.Domain.Diagramming.DecisionTest do
  @moduledoc "O nó `decision`: um losango com a pergunta dentro."

  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.{Layout, Scene}
  alias Brainagram.Domain.Diagramming.Dsl.{Parser, Printer}
  alias Brainagram.Domain.Diagramming.Render.Svg

  @flow """
  diagram architecture "Pedido"

  service  api     "API"
  decision estoque "Tem estoque para todos os itens?"
  service  pag     "Cobrança"
  external email   "E-mail"

  api -> estoque
  estoque -> pag : sim
  estoque -x email : não
  """

  defp scene!(source) do
    {:ok, ast} = Parser.parse(source)
    Layout.build(ast)
  end

  defp node(scene, id), do: Enum.find(scene.nodes, &(&1.id == id))

  test "é um tipo de nó da DSL e volta igual pelo printer" do
    {:ok, ast} = Parser.parse(@flow)
    assert Enum.find(ast.nodes, &(&1.id == "estoque")).kind == :decision
    assert "decision" in Parser.node_kinds()

    printed = Printer.print(ast)
    assert printed =~ ~s(decision estoque "Tem estoque para todos os itens?")
    assert {:ok, again} = Parser.parse(printed)
    assert Enum.map(again.nodes, & &1.kind) == Enum.map(ast.nodes, & &1.kind)
  end

  test "o losango é mais alto que as caixas e largo o bastante para a pergunta" do
    scene = scene!(@flow)
    q = node(scene, "estoque")

    assert q.h == Scene.decision_h()
    assert q.h > node(scene, "api").h
    # a faixa do meio (texto de ~20px de altura) cabe dentro do losango
    text = Scene.text_width(q.label, 13.5)
    assert text / q.w + 20 / q.h <= 1
  end

  for direction <- ["vertical", "horizontal"] do
    test "as setas chegam e saem pelas pontas (#{direction})" do
      scene =
        scene!(
          String.replace(@flow, ~s("Pedido"\n), ~s("Pedido"\ndirection #{unquote(direction)}\n))
        )

      q = node(scene, "estoque")

      tips = [
        {q.x + q.w / 2, q.y},
        {q.x + q.w, q.y + q.h / 2},
        {q.x + q.w / 2, q.y + q.h},
        {q.x, q.y + q.h / 2}
      ]

      # a ponta é arredondada para o pixel
      at_tip? = fn {x, y} ->
        Enum.any?(tips, fn {tx, ty} -> abs(x - tx) <= 1 and abs(y - ty) <= 1 end)
      end

      for edge <- scene.edges do
        if edge.from == "estoque",
          do: assert(at_tip?.({edge.x1, edge.y1}), "#{edge.id} sai fora da ponta"),
          else: assert(at_tip?.({edge.x2, edge.y2}), "#{edge.id} chega fora da ponta")
      end
    end
  end

  for direction <- ["vertical", "horizontal"] do
    test "sim e não saem por pontas diferentes e chegam aos destinos (#{direction})" do
      scene =
        scene!(
          String.replace(@flow, ~s("Pedido"\n), ~s("Pedido"\ndirection #{unquote(direction)}\n))
        )

      [yes, no] = Enum.filter(scene.edges, &(&1.from == "estoque"))

      assert {yes.x1, yes.y1} != {no.x1, no.y1}

      for edge <- [yes, no] do
        target = node(scene, edge.to)

        assert edge.x2 in target.x..(target.x + target.w) and
                 edge.y2 in target.y..(target.y + target.h),
               "#{edge.id} não chega em #{edge.to}"
      end
    end
  end

  test "o SVG desenha o losango com a pergunta centralizada" do
    scene = scene!(@flow)
    q = node(scene, "estoque")
    svg = Svg.render(scene)

    assert svg =~
             ~s(<g class="bg-node is-decision"><path class="bg-node-box" d="M #{q.x + q.w / 2} #{q.y} L #{q.x + q.w} )

    assert svg =~ ~s(text-anchor="middle">Tem estoque para todos os itens?</text>)
  end

  test "numa sequência, o cabeçalho do losango também cabe a pergunta" do
    scene = scene!("diagram sequence\ndecision q \"Pagamento aprovado?\"\nactor a\na -> q\n")
    q = node(scene, "q")
    assert Scene.text_width(q.label, 13.5) / q.w + 20 / q.h <= 1
  end
end
