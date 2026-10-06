defmodule Brainagram.Domain.Diagramming.PayloadTest do
  @moduledoc """
  O payload de uma mensagem: o balão com os dados que ela carrega, sob a seta
  no diagrama de sequência.
  """

  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.Authoring
  alias Brainagram.Domain.Diagramming.Dsl.{Parser, Printer}
  alias Brainagram.Domain.Diagramming.Render.Svg
  alias Brainagram.Test.Fixtures

  defp edges(source) do
    {:ok, ast} = Parser.parse(source)
    ast.steps |> Enum.flat_map(& &1.items) |> Enum.filter(&Map.has_key?(&1, :arrow))
  end

  defp edge(scene, id), do: Enum.find(scene.edges, &(&1.id == id))

  @fenced ~S'''
  diagram sequence "Pedido"
  step "Grava" {
    api -> db : INSERT
      payload """
      INSERT INTO orders (id)   # conteúdo, não comentário
      VALUES ($1)   -- // também
      """
    db --> api : ok
  }
  '''

  describe "parser" do
    test "`payload:` numa linha; várias linhas seguidas viram um payload só" do
      [edge] =
        edges("""
        user -> api : POST /orders
          payload: {"items": 3}   # comentário do fim sai
          payload: Authorization: Bearer abc
        """)

      assert edge.payload == ~s({"items": 3}\nAuthorization: Bearer abc)
      assert edge.spans.payload.line == 2
      assert edge.spans.payload_end.line == 3
    end

    test "bloco \"\"\": texto cru (# e // são conteúdo), sem o recuo do bloco" do
      [insert, ok] = edges(@fenced)

      assert insert.payload ==
               "INSERT INTO orders (id)   # conteúdo, não comentário\nVALUES ($1)   -- // também"

      assert insert.spans.payload.line == 4
      assert insert.spans.payload_end.line == 7
      assert ok.payload == nil
    end

    test "`dados:` é sinônimo" do
      assert [%{payload: "x"}] = edges("a -> b\n  dados: x")
    end

    test "linhas em branco e comentários entre a mensagem e o payload valem" do
      assert [%{payload: "x"}] = edges("a -> b\n\n  # contexto\n  payload: x")
    end

    test "payload solto é erro, na linha dele" do
      for source <- [
            "payload: x",
            "note over a : oi\npayload: x",
            "a -> b\nactor c\npayload: x",
            "step \"s\" {\n  a -> b\n}\npayload: x",
            ~s(note over a : oi\npayload """\nx\n""")
          ] do
        assert {:error, [%{code: :orphan_payload}]} = Parser.parse(source), source
      end
    end

    test "bloco sem fechar é erro na linha que abriu" do
      assert {:error, [%{code: :unclosed_payload, line: 2}]} =
               Parser.parse(~s(a -> b\npayload """\nabc))
    end
  end

  describe "printer" do
    test "uma linha limpa vira `payload:`; várias linhas ou # e // viram bloco" do
      {:ok, ast} =
        Parser.parse("a -> b\n  payload: {\"id\": 1}\nc -> d\n  payload: x\n  payload: y")

      printed = Printer.print(ast)

      assert printed =~ ~s(  payload: {"id": 1})
      assert printed =~ ~s(  payload """\n    x\n    y\n  """)

      assert Printer.payload("http://x # y") == [~s(  payload """), "    http://x # y", ~s(  """)]
    end

    test "formatar não perde payload e é idempotente" do
      {:ok, ast} = Parser.parse(@fenced)
      printed = Printer.print(ast)
      {:ok, again} = Parser.parse(printed)

      assert Printer.print(again) == printed
      assert Enum.map(edges(printed), & &1.payload) == Enum.map(edges(@fenced), & &1.payload)
    end
  end

  describe "autoria" do
    @src ~S'''
    user -> api : POST
      payload """
      {"a": 1}
      """
    api -> db : q
    '''

    test "apagar a seta leva o payload junto" do
      assert {:ok, "api -> db : q\n"} = Authoring.remove_edge(@src, "e1")
    end

    test "apagar o nó leva as setas e os payloads delas" do
      assert {:ok, "api -> db : q\n"} = Authoring.remove_node(@src, "user")
    end

    test "conectar entra depois do payload, não entre a seta e ele" do
      {:ok, source, _meta} =
        Authoring.connect_nodes("a -> b\n  payload: x\n", %{from: "b", to: "a"})

      assert source == "a -> b\n  payload: x\nb -> a\n"
    end

    test "set_payload cria, troca e apaga — com o recuo da mensagem" do
      {:ok, created} = Authoring.set_payload(@src, "e2", "SELECT *\nFROM t")
      assert created =~ ~s(api -> db : q\n  payload """\n    SELECT *\n    FROM t\n  """)
      assert Enum.map(edges(created), & &1.payload) == [~s({"a": 1}), "SELECT *\nFROM t"]

      {:ok, replaced} = Authoring.set_payload(@src, "e1", ~s({"b": 2}))
      assert replaced == ~s(user -> api : POST\n  payload: {"b": 2}\napi -> db : q\n)

      assert {:ok, "user -> api : POST\napi -> db : q\n"} =
               Authoring.set_payload(@src, "e1", "  \n")
    end

    test "set_payload pelo nome da operação, com recuo de passo" do
      source = "step \"s\" {\n  a -> b\n}\n"

      assert {:ok, "step \"s\" {\n  a -> b\n    payload: x\n}\n"} =
               Authoring.run(source, "set_payload", %{"id" => "e1", "payload" => "x"})

      assert {:error, :unknown_edge} = Authoring.run(source, "set_payload", %{"id" => "e9"})
    end
  end

  describe "layout de sequência" do
    @big ~S'''
    step "s" {
      a -> b : POST
        payload """
        {
          "customer_id": "c-123",
          "items": [1, 2, 3],
          "total": 199.90
        }
        """
      b --> a : ok
    }
    '''

    test "minimizado: chip sob a seta com a ponta nela, e só o chip ocupa espaço" do
      plain = Fixtures.scene!("step \"s\" {
  a -> b : POST
  b --> a : ok
}")
      scene = Fixtures.scene!(@big)
      first = edge(scene, "e1")
      %{chip: chip} = p = first.payload

      assert String.starts_with?(chip.label, ~s({ "customer_id"))
      assert String.ends_with?(chip.label, "…")
      assert chip.count == 5
      assert chip.h == 20
      assert p.tip_y > first.y and p.tip_y < chip.y
      assert p.tip_x == round((first.x1 + first.x2) / 2)

      # a próxima seta desce só o chip, não o balão inteiro
      next_y = edge(scene, "e2").y
      assert next_y > chip.y + chip.h
      assert next_y < p.y + p.h
      assert next_y - edge(plain, "e2").y < 40
      assert edge(plain, "e1")[:payload] == nil
    end

    test "o balão aberto começa no topo do chip, com o conteúdo, e dá tempo de leitura" do
      p = Fixtures.scene!(@big) |> edge("e1") |> Map.fetch!(:payload)

      assert p.y == p.chip.y
      assert length(p.lines) == 5
      assert p.h > p.chip.h
      assert p.hold == 1_200 + 110 * 5
    end

    test "chip de uma linha mostra o texto; linha longa é encurtada" do
      short = Fixtures.scene!(~s(a -> b
  payload: {"id": 1})) |> edge("e1")
      assert short.payload.chip.label == ~s({"id": 1})
      assert short.payload.chip.count == 1

      long = Fixtures.scene!("a -> b
  payload: " <> String.duplicate("x", 50)) |> edge("e1")
      assert String.length(long.payload.chip.label) == 28
      assert String.ends_with?(long.payload.chip.label, "…")
    end

    test "balão grande é aparado: 16 linhas, 64 caracteres; o texto inteiro vai junto" do
      long = Enum.map_join(1..20, "
", &("linha #{&1} " <> String.duplicate("x", 80)))
      scene = Fixtures.scene!(~s(a -> b
  payload """
#{long}
  """))
      p = edge(scene, "e1").payload

      assert length(p.lines) == 16
      assert List.last(p.lines) == "… +5"
      assert Enum.all?(p.lines, &(String.length(&1) <= 64))
      assert p.text == long
      assert p.hold == 2_600
    end

    test "auto-chamada: chip e balão sob o laço, à direita da raia" do
      scene = Fixtures.scene!("a -> a : valida
  payload: ok")
      e = edge(scene, "e1")
      assert e.payload.x > e.x1
      assert e.payload.chip.x > e.x1
      assert e.payload.y > e.y
    end

    test "a cena cresce para caber o balão aberto na última raia" do
      wide = String.duplicate("x", 62)
      scene = Fixtures.scene!("a -> b
b -> c
  payload: #{wide}")
      p = edge(scene, "e2").payload
      assert scene.width >= p.x + p.w
    end

    test "o SVG de fora do navegador desenha o chip, com o texto escapado" do
      svg = "a -> b
  payload: <x> & \"y\"" |> Fixtures.scene!() |> Svg.render()

      assert svg =~ ~s(class="bg-payload-chip")
      assert svg =~ "&lt;x&gt; &amp; &quot;y&quot;"
    end
  end
end
