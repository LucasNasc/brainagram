defmodule Brainagram.Domain.Diagramming.Dsl.ParserTest do
  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.Dsl.{Edge, Note, Parser}

  describe "declarações" do
    test "lê tipo e título do diagrama" do
      assert {:ok, ast} = Parser.parse(~s(diagram sequence "Meu fluxo"))
      assert ast.kind == :sequence
      assert ast.title == "Meu fluxo"
    end

    test "aceita aliases em português" do
      assert {:ok, ast} = Parser.parse(~s(diagram arquitetura "X"))
      assert ast.kind == :architecture
    end

    test "rejeita tipo desconhecido" do
      assert {:error, [%{line: 1, message: msg}]} = Parser.parse("diagram fluxograma")
      assert msg =~ "desconhecido"
    end

    test "usa o id humanizado quando não há rótulo" do
      assert {:ok, ast} = Parser.parse("participant order_service")
      assert [%{id: "order_service", label: "Order Service"}] = ast.nodes
    end

    test "declara automaticamente nós usados em setas" do
      assert {:ok, ast} = Parser.parse("a -> b : oi")
      assert Enum.map(ast.nodes, & &1.id) == ["a", "b"]
    end

    test "redeclarar depois de usar mantém a ordem e aplica o rótulo" do
      assert {:ok, ast} = Parser.parse("a -> b\ndatabase b \"Postgres\"")
      assert [%{id: "a"}, %{id: "b", label: "Postgres", kind: :database}] = ast.nodes
    end
  end

  describe "setas" do
    test "mapeia cada operador para seu tipo" do
      src = """
      a -> b
      b --> a
      a ->> c
      c -x a
      """

      assert {:ok, ast} = Parser.parse(src)
      arrows = ast.steps |> Enum.flat_map(& &1.items) |> Enum.map(& &1.arrow)
      assert arrows == [:sync, :return, :async, :fail]
    end

    test "sem step explícito, cada mensagem vira um passo" do
      assert {:ok, ast} = Parser.parse("a -> b : um\nb -> c : dois")
      assert length(ast.steps) == 2
      assert Enum.map(ast.steps, & &1.label) == ["um", "dois"]
    end

    test "mensagens soltas antes de steps viram um passo inicial" do
      src = """
      a -> b : setup
      step "Real" {
        b -> c : vai
      }
      """

      assert {:ok, ast} = Parser.parse(src)
      assert Enum.map(ast.steps, &{&1.index, &1.label}) == [{0, "Contexto inicial"}, {1, "Real"}]
    end
  end

  describe "blocos" do
    test "step agrupa mensagens na ordem escrita" do
      src = """
      step "Um" {
        a -> b : x
        b --> a : y
      }
      """

      assert {:ok, ast} = Parser.parse(src)
      assert [%{label: "Um", items: [%Edge{label: "x"}, %Edge{label: "y"}]}] = ast.steps
    end

    test "group registra os nós declarados dentro dele" do
      src = """
      group "Core" {
        service api "API"
        service worker "Worker"
      }
      """

      assert {:ok, ast} = Parser.parse(src)
      assert [%{label: "Core", node_ids: ["api", "worker"]}] = ast.groups
      assert Enum.all?(ast.nodes, &(&1.group == "Core"))
    end

    test "acusa bloco não fechado" do
      assert {:error, errors} = Parser.parse(~s(step "X" {\n  a -> b))
      assert Enum.any?(errors, &(&1.message =~ "nunca foi fechado"))
    end

    test "acusa fechamento sem abertura" do
      assert {:error, [%{line: 1, message: msg}]} = Parser.parse("}")
      assert msg =~ "sem bloco aberto"
    end

    test "recusa aninhamento" do
      src = ~s(step "A" {\n  group "B" {\n  }\n})
      assert {:error, errors} = Parser.parse(src)
      assert Enum.any?(errors, &(&1.message =~ "aninhados"))
    end
  end

  describe "notas e comentários" do
    test "parseia note over com múltiplos alvos" do
      assert {:ok, ast} = Parser.parse("note over a, b : cuidado aqui")

      assert [%Note{placement: :over, target_ids: ["a", "b"], text: "cuidado aqui"}] =
               Enum.flat_map(ast.steps, & &1.items)
    end

    test "ignora comentários mas preserva # dentro de aspas" do
      assert {:ok, ast} = Parser.parse(~s(a -> b : GET /x # isto some\nparticipant c "tag #1"))
      [edge] = ast.steps |> Enum.flat_map(& &1.items) |> Enum.filter(&match?(%Edge{}, &1))
      assert edge.label == "GET /x"
      assert Enum.find(ast.nodes, &(&1.id == "c")).label == "tag #1"
    end
  end

  test "coleta todos os erros, não só o primeiro" do
    assert {:error, errors} = Parser.parse("linha ruim um\nlinha ruim dois\na -> b")
    assert Enum.map(errors, & &1.line) == [1, 2]
  end
end
