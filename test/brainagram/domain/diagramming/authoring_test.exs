defmodule Brainagram.Domain.Diagramming.AuthoringTest do
  @moduledoc """
  Fases B, C e D da spec 001: cada gesto do canvas como edição cirúrgica.

  O critério que atravessa todos: o gesto muda o que apontou e **nada mais** —
  comentários, alinhamento e ordem das outras linhas ficam como estavam.
  """

  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.Authoring
  alias Brainagram.Domain.Diagramming.Dsl.Parser
  alias Brainagram.Domain.Diagramming.Layout.Hints
  alias Brainagram.Test.Fixtures

  @arch """
  diagram architecture "Plataforma"   # visão de alto nível

  # entrada
  service  api "API (Phoenix)"
  database pg  "PostgreSQL"   # principal

  group "Dados" {
    queue mq "RabbitMQ"
  }

  step "Leitura" {
    api -> pg : SELECT   # leitura quente
  }

  step "Escrita" {
    api ->> mq : publica
  }
  """

  defp edge_id(source, from, to) do
    {:ok, ast} = Parser.parse(source)

    ast.steps
    |> Enum.flat_map(& &1.items)
    |> Enum.find(&(Map.get(&1, :from) == from and Map.get(&1, :to) == to))
    |> Map.fetch!(:id)
  end

  defp node!(source, id) do
    {:ok, ast} = Parser.parse(source)
    Enum.find(ast.nodes, &(&1.id == id))
  end

  describe "fase B — rótulos e setas" do
    test "renomear um nó troca só o texto entre aspas e preserva os comentários" do
      assert {:ok, edited} = Authoring.rename_node_label(@arch, "pg", "Postgres 16")
      assert edited == String.replace(@arch, ~s("PostgreSQL"), ~s("Postgres 16"))
    end

    test "renomear nó declarado sem rótulo acrescenta as aspas depois do id" do
      source = "service api\napi -> db\n"

      assert {:ok, "service api \"Gateway\"\napi -> db\n"} =
               Authoring.rename_node_label(source, "api", "Gateway")
    end

    test "renomear nó que só aparece numa seta cria a declaração" do
      assert {:ok, edited} = Authoring.rename_node_label("a -> b : oi\n", "b", "Banco")
      assert edited == "participant b \"Banco\"\na -> b : oi\n"
    end

    test "aspas no nome viram aspas tipográficas; nome vazio é recusado" do
      assert {:ok, edited} = Authoring.rename_node_label(@arch, "api", ~s(API "v2"))
      assert edited =~ ~s("API ”v2”")
      assert {:error, :blank_label} = Authoring.rename_node_label(@arch, "api", "   ")
    end

    test "trocar o rótulo de uma seta mexe só no texto depois de `:`" do
      id = edge_id(@arch, "api", "pg")
      assert {:ok, edited} = Authoring.relabel_edge(@arch, id, "SELECT * FROM pedidos")

      assert edited ==
               String.replace(@arch, "api -> pg : SELECT ", "api -> pg : SELECT * FROM pedidos ")
    end

    test "seta sem rótulo ganha `: texto`; rótulo vazio remove" do
      assert {:ok, "a -> b : oi\n"} =
               Authoring.relabel_edge("a -> b\n", edge_id("a -> b\n", "a", "b"), "oi")

      assert {:ok, "a -> b\n"} =
               Authoring.relabel_edge("a -> b : oi\n", edge_id("a -> b : oi\n", "a", "b"), "")
    end

    test "rótulo com # seria comentário e é recusado" do
      id = edge_id(@arch, "api", "pg")
      assert {:error, :invalid_label} = Authoring.relabel_edge(@arch, id, "pedido #42")
    end

    test "trocar o tipo da seta troca só o operador" do
      id = edge_id(@arch, "api", "pg")

      for {arrow, token} <- [return: "-->", async: "->>", fail: "-x", sync: "->"] do
        assert {:ok, edited} = Authoring.change_edge_arrow(@arch, id, arrow)
        assert edited == String.replace(@arch, "api -> pg", "api #{token} pg")
      end
    end

    test "apagar uma seta remove a linha dela e nada mais" do
      id = edge_id(@arch, "api", "pg")
      assert {:ok, edited} = Authoring.remove_edge(@arch, id)
      assert edited == String.replace(@arch, "  api -> pg : SELECT   # leitura quente\n", "")
    end

    test "apagar um nó leva junto setas, notas e posição fixada dele" do
      source =
        @arch <> "\nnote over pg : cuidado\n\nlayout {\n  pg at (1, 2)\n  api at (3, 4)\n}\n"

      assert {:ok, edited} = Authoring.remove_node(source, "pg")

      refute edited =~ "pg"
      assert edited =~ "api ->> mq : publica"
      assert edited =~ "api at (3, 4)"
      assert edited =~ "# entrada"
    end

    test "desfazer é voltar ao texto anterior: o original fica intacto" do
      {:ok, edited} = Authoring.rename_node_label(@arch, "pg", "Outro")
      refute edited == @arch
      assert {:ok, back} = Authoring.rename_node_label(edited, "pg", "PostgreSQL")
      assert back == @arch
    end
  end

  describe "fase C — criar e conectar" do
    test "novo nó entra depois da última declaração solta, com a indentação dela" do
      assert {:ok, edited, %{node_id: "cache_redis"}} =
               Authoring.add_node(@arch, %{label: "Cache Redis"})

      assert edited =~
               ~s(database pg  "PostgreSQL"   # principal\nservice cache_redis "Cache Redis"\n)
    end

    test "o id não colide com os existentes" do
      {:ok, once, %{node_id: "api_2"}} = Authoring.add_node(@arch, %{label: "API"})
      assert {:ok, _, %{node_id: "api_3"}} = Authoring.add_node(once, %{label: "API"})
    end

    test "novo nó dentro de um grupo, com o tipo pedido" do
      assert {:ok, edited, %{node_id: "redis"}} =
               Authoring.add_node(@arch, %{label: "Redis", kind: "database", group: "Dados"})

      assert edited =~ ~s(  queue mq "RabbitMQ"\n  database redis "Redis"\n}\n)
      assert %{group: "Dados", kind: :database} = node!(edited, "redis")
    end

    test "novo nó com posição já nasce fixado" do
      {:ok, edited, %{node_id: id}} = Authoring.add_node(@arch, %{label: "S3", at: {400, 300}})
      {:ok, ast} = Parser.parse(edited)
      assert Hints.from_ast(ast).pinned[id] == {400, 300}
    end

    test "tipo padrão segue o diagrama" do
      {:ok, _, %{node_id: id}} = Authoring.add_node("diagram sequence\na -> b\n", %{label: "C"})
      {:ok, edited, _} = Authoring.add_node("diagram sequence\na -> b\n", %{label: "C"})
      assert node!(edited, id).kind == :participant
    end

    test "conectar num passo explícito entra antes do `}` do passo" do
      assert {:ok, edited, %{edge_id: id}} =
               Authoring.connect_nodes(@arch, %{
                 from: "pg",
                 to: "api",
                 arrow: :return,
                 label: "linhas",
                 step: 0
               })

      assert edited =~ "  api -> pg : SELECT   # leitura quente\n  pg --> api : linhas\n}"
      assert edge_id(edited, "pg", "api") == id
    end

    test "sem passo indicado, entra no último" do
      {:ok, edited, _} = Authoring.connect_nodes(@arch, %{from: "mq", to: "pg"})
      assert edited =~ "  api ->> mq : publica\n  mq -> pg\n}"
    end

    test "em diagrama de mensagens soltas, a seta nova fica solta depois da do passo" do
      source = "a -> b : um\nb -> a : dois\n"
      {:ok, edited, _} = Authoring.connect_nodes(source, %{from: "a", to: "b", step: 0})
      assert edited == "a -> b : um\na -> b\nb -> a : dois\n"
    end

    test "sem nenhuma mensagem, a seta entra antes do bloco layout" do
      source = "service a\nservice b\n\nlayout {\n  a at (1, 2)\n}\n"
      {:ok, edited, _} = Authoring.connect_nodes(source, %{from: "a", to: "b"})
      assert edited == "service a\nservice b\n\na -> b\nlayout {\n  a at (1, 2)\n}\n"
    end

    test "conectar nó inexistente é recusado" do
      assert {:error, :unknown_node} = Authoring.connect_nodes(@arch, %{from: "api", to: "nada"})
    end

    test "aceite: 10 nós e 12 setas construídos do zero, sem digitar" do
      source =
        Enum.reduce(1..10, "diagram architecture \"Do zero\"\n", fn i, acc ->
          {:ok, next, _} = Authoring.add_node(acc, %{label: "Serviço #{i}"})
          next
        end)

      pairs = [
        {1, 2},
        {2, 3},
        {3, 4},
        {4, 5},
        {5, 6},
        {6, 7},
        {7, 8},
        {8, 9},
        {9, 10},
        {1, 5},
        {2, 8},
        {3, 10}
      ]

      source =
        Enum.reduce(pairs, source, fn {a, b}, acc ->
          {:ok, next, _} =
            Authoring.connect_nodes(acc, %{
              from: "servico_#{a}",
              to: "servico_#{b}",
              label: "chama #{b}"
            })

          next
        end)

      scene = Fixtures.scene!(source)
      assert length(scene.nodes) == 10
      assert length(scene.edges) == 12
      # o fonte gerado compila de novo para a mesma cena
      assert Fixtures.scene!(source) == scene
    end
  end

  describe "fase D — arrastar e fixar" do
    test "fixar cria o bloco layout no fim; soltar de novo atualiza a linha" do
      {:ok, pinned} = Authoring.pin_node(@arch, "pg", {420, 680})
      assert pinned == @arch <> "\nlayout {\n  pg at (420, 680)\n}\n"

      {:ok, moved} = Authoring.pin_node(pinned, "pg", {424, 688})
      assert moved == @arch <> "\nlayout {\n  pg at (424, 688)\n}\n"
    end

    test "fixar nó que não existe é recusado" do
      assert {:error, :unknown_node} = Authoring.pin_node(@arch, "nada", {1, 2})
    end

    test "reorganizar apaga o bloco e devolve o texto de antes" do
      {:ok, pinned} = Authoring.pin_node(@arch, "pg", {420, 680})
      assert {:ok, @arch} = Authoring.clear_layout_hints(pinned)
    end

    test "arrastar para dentro de um grupo move a declaração com o comentário" do
      assert {:ok, edited} = Authoring.move_node_to_group(@arch, "pg", "Dados")

      assert edited =~ ~s(  queue mq "RabbitMQ"\n  database pg  "PostgreSQL"   # principal\n}\n)
      refute edited =~ ~s(\ndatabase pg  "PostgreSQL"   # principal\n\ngroup)
      assert node!(edited, "pg").group == "Dados"
    end

    test "arrastar para fora do grupo devolve a declaração ao topo" do
      assert {:ok, edited} = Authoring.move_node_to_group(@arch, "mq", nil)
      assert node!(edited, "mq").group == nil
      assert edited =~ ~s(group "Dados" {\n}\n)
    end

    test "grupo desconhecido é recusado; o mesmo grupo não muda nada" do
      assert {:error, :unknown_group} = Authoring.move_node_to_group(@arch, "pg", "Nada")
      assert {:ok, @arch} = Authoring.move_node_to_group(@arch, "mq", "Dados")
    end

    test "soltar num grupo fixa a posição e move numa edição só" do
      assert {:ok, edited} = Authoring.drop_node(@arch, "pg", {500, 300}, "Dados")
      assert node!(edited, "pg").group == "Dados"
      assert edited =~ "pg at (500, 300)"
    end
  end

  describe "fase E — teclado" do
    test "Alt+↓ troca o passo com o de baixo e leva o cursor junto" do
      line = 12
      assert {:ok, edited, %{line: new_line}} = Authoring.move_step(@arch, line, :down)

      assert edited =~ ~s(step "Escrita" {\n  api ->> mq : publica\n}\n\nstep "Leitura" {)
      assert new_line == line + 4
      assert edited |> String.split("\n") |> Enum.at(new_line - 1) =~ "api -> pg"
    end

    test "Alt+↑ no primeiro passo não faz nada" do
      assert {:ok, @arch, %{line: 12}} = Authoring.move_step(@arch, 12, :up)
    end

    test "alternar o tipo troca só a palavra do cabeçalho" do
      assert {:ok, edited} = Authoring.switch_kind(@arch)
      assert edited == String.replace(@arch, "diagram architecture", "diagram sequence")
    end

    test "formatar usa o printer canônico" do
      assert {:ok, formatted, %{comments_dropped: true}} = Authoring.format(@arch)
      assert formatted =~ ~s[diagram architecture "Plataforma"\n\nservice  api "API (Phoenix)"]
      refute formatted =~ "#"
    end
  end

  describe "segurança do patch" do
    test "fonte inválido não é editável pelo canvas" do
      assert {:error, {:syntax, _}} = Authoring.rename_node_label("isso não é dsl", "a", "b")
    end

    test "operação desconhecida por nome" do
      assert {:error, :unknown_operation} = Authoring.run(@arch, "explodir", %{})
    end

    test "run/3 aceita os parâmetros como vêm da interface" do
      id = edge_id(@arch, "api", "pg")

      assert {:ok, edited} =
               Authoring.run(@arch, "change_arrow", %{"id" => id, "arrow" => "async"})

      assert edited =~ "api ->> pg"

      assert {:ok, pinned} =
               Authoring.run(@arch, "drop", %{"id" => "pg", "x" => "120.6", "y" => 80})

      assert pinned =~ "pg at (121, 80)"
    end
  end
end
