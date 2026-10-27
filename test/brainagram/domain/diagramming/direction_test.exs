defmodule Brainagram.Domain.Diagramming.DirectionTest do
  @moduledoc "`direction horizontal` e a fila como cilindro deitado."

  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.{Authoring, Layout}
  alias Brainagram.Domain.Diagramming.Dsl.{Parser, Printer}
  alias Brainagram.Domain.Diagramming.Layout.Untangle
  alias Brainagram.Domain.Diagramming.Render.Svg

  @flow """
  diagram architecture "Pedidos"
  direction horizontal

  actor web "Loja"
  service api "API"
  queue mq "Eventos"
  database pg "Postgres"

  web -> api : POST /orders
  api -> pg : INSERT
  api ->> mq : order.paid
  """

  defp scene!(source) do
    {:ok, ast} = Parser.parse(source)
    Layout.build(ast)
  end

  defp node(scene, id), do: Enum.find(scene.nodes, &(&1.id == id))

  describe "a linha `direction`" do
    test "horizontal e os sinônimos do Mermaid; vertical é o padrão" do
      for value <- ~w(horizontal LR rl) do
        {:ok, ast} = Parser.parse("diagram architecture\ndirection #{value}\na -> b")
        assert ast.direction == :horizontal
        assert ast.direction_span.line == 2
      end

      for value <- ~w(vertical TB td BT) do
        {:ok, ast} = Parser.parse("diagram architecture\ndirection #{value}\na -> b")
        assert ast.direction == :vertical
      end

      {:ok, ast} = Parser.parse("diagram architecture\na -> b")
      assert ast.direction == :vertical
      assert ast.direction_span == nil
    end

    test "valor desconhecido é erro com linha" do
      assert {:error, [error]} = Parser.parse("diagram architecture\ndirection diagonal")
      assert error.code == :unknown_direction
      assert error.line == 2
      assert error.bindings == %{direction: "diagonal"}
    end

    test "o printer escreve só o horizontal, logo abaixo do cabeçalho" do
      {:ok, ast} = Parser.parse(@flow)
      printed = Printer.print(ast)
      assert printed =~ ~s(diagram architecture "Pedidos"\ndirection horizontal\n\n)
      assert {:ok, %{direction: :horizontal}} = Parser.parse(printed)

      {:ok, vertical} = Parser.parse("diagram architecture\ndirection vertical\na -> b")
      refute Printer.print(vertical) =~ "direction"
    end
  end

  describe "layout deitado" do
    test "as camadas andam para a direita e as setas saem pela lateral" do
      scene = scene!(@flow)
      assert scene.direction == :horizontal

      web = node(scene, "web")
      api = node(scene, "api")
      pg = node(scene, "pg")

      assert api.x >= web.x + web.w
      assert pg.x >= api.x + api.w

      edge = Enum.find(scene.edges, &(&1.from == "web"))
      assert edge.x1 == web.x + web.w
      assert edge.x2 == api.x
      assert scene.width >= pg.x + pg.w
    end

    test "as caixas não se sobrepõem e a cena cobre todas" do
      scene = scene!(@flow)

      for a <- scene.nodes, b <- scene.nodes, a.id < b.id do
        refute a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h,
               "#{a.id} e #{b.id} se sobrepõem"
      end

      assert Enum.all?(scene.nodes, &(&1.y + &1.h <= scene.height))
    end

    test "nenhum rótulo de seta cobre uma caixa no exemplo deitado" do
      scene = scene!(File.read!("examples/import/mermaid/order-pipeline.brain"))
      assert scene.direction == :horizontal

      for edge <- scene.edges, edge.label, node <- scene.nodes do
        w = Brainagram.Domain.Diagramming.Scene.text_width(edge.label, 12) + 12

        left =
          case edge.label_anchor do
            "middle" -> edge.label_x - w / 2
            "end" -> edge.label_x - w + 6
            _ -> edge.label_x - 6
          end

        top = edge.label_y - 13

        refute left < node.x + node.w and node.x < left + w and top < node.y + node.h and
                 node.y < top + 18,
               "o rótulo #{inspect(edge.label)} cobre #{node.id}"
      end
    end

    test "em pé continua de cima para baixo" do
      scene = scene!(String.replace(@flow, "direction horizontal\n", ""))
      assert scene.direction == :vertical
      assert node(scene, "api").y > node(scene, "web").y
    end

    test "uma posição fixada fica exatamente onde foi solta" do
      scene = scene!(@flow <> "\nlayout {\n  pg at (900, 400)\n}\n")
      assert %{x: 900, y: 400, pinned: true} = node(scene, "pg")
    end

    test "organizar setas grava posições do plano real" do
      source = """
      diagram architecture
      direction horizontal
      a -> c
      b -> d
      a -> d
      b -> c
      c -> e
      d -> e
      """

      assert {:ok, %{source: edited}} = Untangle.run(source)
      assert edited =~ "direction horizontal"
      scene = scene!(edited)
      assert node(scene, "e").x > node(scene, "a").x
    end
  end

  describe "alternar direção" do
    test "deita inserindo a linha abaixo do cabeçalho e levanta tirando-a" do
      source = "diagram architecture \"X\"\n\n# a API\nservice api\napi -> db\n"

      assert {:ok, horizontal, %{unpinned: false}} = Authoring.switch_direction(source)

      assert horizontal ==
               "diagram architecture \"X\"\ndirection horizontal\n\n# a API\nservice api\napi -> db\n"

      assert {:ok, ^source, _} = Authoring.switch_direction(horizontal)
    end

    test "troca `direction vertical` escrito à mão" do
      source = "diagram architecture\ndirection vertical\na -> b\n"
      assert {:ok, edited, _} = Authoring.run(source, "switch_direction", %{})
      assert edited == "diagram architecture\ndirection horizontal\na -> b\n"
    end

    test "solta as posições fixadas, que eram da outra orientação" do
      source = "diagram architecture\na -> b\n\nlayout {\n  a at (100, 100)\n}\n"
      assert {:ok, edited, %{unpinned: true}} = Authoring.switch_direction(source)
      refute edited =~ "layout"
      assert edited =~ "direction horizontal"
    end

    test "sequência não tem direção" do
      assert {:error, :not_architecture} =
               Authoring.switch_direction("diagram sequence\na -> b\n")
    end
  end

  describe "fila como cilindro deitado" do
    test "o SVG desenha corpo com tampas e a face da direita" do
      scene = scene!(@flow)
      mq = node(scene, "mq")
      svg = Svg.render(scene)

      assert svg =~
               ~s(<g class="bg-node is-queue"><path class="bg-node-box" d="M #{mq.x + 12} #{mq.y} )

      assert svg =~ ~s(<path class="bg-node-cap" d="M #{mq.x + mq.w - 12} #{mq.y} A 12 )
      assert svg =~ ~s(<g class="bg-node is-service"><rect class="bg-node-box")
    end

    test "a caixa da fila ganha a largura das tampas" do
      scene = scene!("diagram architecture\nqueue a \"Fila\"\nservice b \"Fila\"\na -> b")
      assert node(scene, "a").w == node(scene, "b").w + 24
    end
  end
end
