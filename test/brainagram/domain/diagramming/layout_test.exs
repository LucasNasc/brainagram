defmodule Brainagram.Domain.Diagramming.LayoutTest do
  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.Scene
  alias Brainagram.Domain.Diagramming.ValueObjects.Source
  alias Brainagram.Test.Fixtures

  defp compile!(src), do: Fixtures.scene!(src)

  describe "sequência" do
    test "raias ficam em ordem e não se sobrepõem" do
      scene = compile!("a -> b\nb -> c")
      xs = Enum.map(scene.nodes, & &1.x)
      assert xs == Enum.sort(xs)

      pairs = Enum.zip(scene.nodes, tl(scene.nodes))
      assert Enum.all?(pairs, fn {l, r} -> l.x + l.w <= r.x end)
    end

    test "rótulo longo afasta as raias o suficiente para caber" do
      curto = compile!("a -> b : ok")
      longo = compile!("a -> b : uma mensagem consideravelmente mais longa que a outra")

      assert largura_entre(longo) > largura_entre(curto)
    end

    test "mensagens descem monotonicamente na ordem dos passos" do
      scene = compile!(Fixtures.sequence_source())
      ys = Enum.map(scene.edges, & &1.y)
      assert ys == Enum.sort(ys)
    end

    test "auto-chamada vira curva, não linha reta" do
      scene = compile!("a -> a : valida")
      [edge] = scene.edges
      assert edge.self
      assert edge.path =~ "C"
    end

    test "chamada síncrona abre barra de ativação e retorno fecha" do
      scene = compile!("a -> b : call\nb --> a : resp")
      [bar] = scene.activations
      assert bar.node == "b"

      [call, ret] = scene.edges
      assert bar.y1 == call.y
      assert bar.y2 == ret.y
    end

    test "ativação sem retorno é fechada no fim do diagrama" do
      scene = compile!("a -> b : call")
      [bar] = scene.activations
      assert bar.y2 > bar.y1
      assert bar.y2 <= scene.height
    end

    test "tudo cabe dentro do canvas declarado" do
      scene = compile!(Fixtures.sequence_source())

      assert Enum.all?(scene.nodes, &(&1.x + &1.w <= scene.width))
      assert Enum.all?(scene.edges, &(&1.y <= scene.height))
      assert Enum.all?(scene.notes, &(&1.y + &1.h <= scene.height))
    end

    test "cada passo conhece suas arestas" do
      scene = compile!(Fixtures.sequence_source())
      todas = scene.edges |> Enum.map(& &1.id) |> MapSet.new()
      dos_passos = scene.steps |> Enum.flat_map(& &1.edge_ids) |> MapSet.new()

      assert MapSet.equal?(todas, dos_passos)
      assert Enum.all?(scene.steps, &(&1.duration > 0))
    end
  end

  describe "arquitetura" do
    test "camadas seguem a direção das arestas" do
      scene = compile!("diagram architecture\na -> b\nb -> c")
      y = Map.new(scene.nodes, &{&1.id, &1.y})

      assert y["a"] < y["b"]
      assert y["b"] < y["c"]
    end

    test "grafo cíclico não trava e produz uma cena" do
      scene = compile!("diagram architecture\na -> b\nb -> c\nc -> a")
      assert length(scene.nodes) == 3
      assert scene.height > 0
    end

    test "grupos ocupam faixas horizontais disjuntas" do
      src = """
      diagram architecture

      group "Um" {
        node a "A"
        node b "B"
      }
      group "Dois" {
        node c "C"
        node d "D"
      }

      a -> b
      b -> c
      c -> d
      """

      scene = compile!(src)
      [um, dois] = Enum.sort_by(scene.groups, & &1.x)

      assert um.x + um.w <= dois.x, "as caixas de grupo não podem se sobrepor em X"
    end

    test "nenhum rótulo se sobrepõe a outro" do
      scene = compile!(Fixtures.architecture_source())

      caixas =
        scene.edges
        |> Enum.reject(&is_nil(&1.label))
        |> Enum.map(fn e ->
          w = Scene.text_width(e.label, 12.0) + 14
          x = if e.label_anchor == "middle", do: e.label_x - w / 2, else: e.label_x * 1.0
          %{x: x, y: e.label_y - 8, w: w, h: 16}
        end)

      for a <- caixas, b <- caixas, a != b do
        refute sobrepoe?(a, b), "rótulos sobrepostos: #{inspect(a)} e #{inspect(b)}"
      end
    end

    test "aresta que pula camadas sai do vão das duas caixas e desce por um corredor" do
      # a→d pula duas camadas; a→b→c→d define a profundidade.
      scene = compile!("diagram architecture\na -> b\nb -> c\nc -> d\na -> d : longa")

      longa = Enum.find(scene.edges, &(&1.label == "longa"))
      a = Enum.find(scene.nodes, &(&1.id == "a"))
      d = Enum.find(scene.nodes, &(&1.id == "d"))

      esquerda = min(a.x, d.x)
      direita = max(a.x + a.w, d.x + d.w)

      assert Enum.any?(pontos(longa.path), fn {x, _y} -> x < esquerda or x > direita end),
             "a aresta longa deveria sair para um corredor, não descer entre as caixas"
    end

    test "a aresta longa não passa por dentro das caixas do caminho" do
      scene = compile!("diagram architecture\na -> b\nb -> c\nc -> d\na -> d : longa")

      longa = Enum.find(scene.edges, &(&1.label == "longa"))
      intermediarios = Enum.filter(scene.nodes, &(&1.id in ["b", "c"]))

      for node <- intermediarios, {x, y} <- pontos(longa.path) do
        dentro? =
          x > node.x and x < node.x + node.w and y > node.y and y < node.y + node.h

        refute dentro?, "o caminho passa por dentro da caixa #{node.id} em (#{x}, #{y})"
      end
    end

    test "nós ficam dentro do canvas" do
      scene = compile!(Fixtures.architecture_source())
      assert Enum.all?(scene.nodes, &(&1.x >= 0 and &1.x + &1.w <= scene.width))
      assert Enum.all?(scene.nodes, &(&1.y + &1.h <= scene.height))
    end
  end

  test "toda cena é serializável em JSON" do
    for slug <- ["checkout", "arquitetura", "cqrs", "minimo"] do
      scene = compile!(Fixtures.source(slug))
      assert {:ok, json} = Jason.encode(scene)
      assert byte_size(json) > 100
    end
  end

  test "o layout é determinístico — mesmo fonte, mesma cena" do
    src = Fixtures.sequence_source()
    assert compile!(src) == compile!(src)
  end

  test "Source só existe se compilar" do
    assert {:ok, %Source{}} = Source.new("a -> b")
    assert {:error, {:syntax, _}} = Source.new("isso não é DSL")
  end

  defp sobrepoe?(a, b) do
    a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
  end

  describe "arquitetura com ciclo" do
    # cliente manda comando, o sistema devolve evento ao cliente
    @ciclo """
    diagram architecture
    actor c "Cliente"
    service a "A"
    service b "B"
    service d "D"
    c -> a : comando
    a -> b
    b -> d
    d -> c : evento
    """

    test "o ciclo não estica a cena: cada nó numa camada, a volta sobe" do
      scene = compile!(@ciclo)
      ys = scene.nodes |> Enum.map(& &1.y) |> Enum.uniq()

      assert length(ys) == 4
      assert scene.height < 1_200

      volta = Enum.find(scene.edges, &(&1.from == "d"))
      assert volta.y2 < volta.y1
    end

    test "rótulos e rotas de contorno cabem na largura da cena" do
      scene = compile!(@ciclo <> "layout {
  c at (56, 92)
}
")

      for edge <- scene.edges, {x, _y} <- pontos(edge.path) do
        assert x <= scene.width, "#{edge.id} sai da cena em x=#{x}"
      end
    end
  end

  # Todos os pontos citados no caminho, seja qual for o comando (M, L, Q, C).
  # Para uma polilinha ortogonal com cantos arredondados isso cobre o traçado
  # inteiro, já que não há curva longa entre dois pontos distantes.
  defp pontos(path) do
    ~r/-?\d+(?:\.\d+)?/
    |> Regex.scan(path)
    |> List.flatten()
    |> Enum.map(&elem(Float.parse(&1), 0))
    |> Enum.chunk_every(2, 2, :discard)
    |> Enum.map(fn [x, y] -> {x, y} end)
  end

  defp largura_entre(scene) do
    [a, b] = Enum.take(scene.nodes, 2)
    b.cx - a.cx
  end
end
