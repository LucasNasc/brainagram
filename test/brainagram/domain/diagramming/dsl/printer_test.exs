defmodule Brainagram.Domain.Diagramming.Dsl.PrinterTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Brainagram.Domain.Diagramming.Dsl.{Parser, Printer}
  alias Brainagram.Test.{DslGenerators, Fixtures}

  # A AST impressa e relida é a mesma a menos do que depende de *onde* as coisas
  # estão (linha, spans) e dos ids que o parser numera por ordem de aparição.
  def normalize(ast) do
    %{
      kind: ast.kind,
      title: ast.title,
      nodes: Enum.map(ast.nodes, &Map.take(&1, [:id, :label, :kind, :group])),
      groups: Enum.map(ast.groups, &Map.take(&1, [:label, :node_ids])),
      steps:
        Enum.map(ast.steps, fn step ->
          %{
            index: step.index,
            label: step.label,
            implicit: step.implicit,
            items: Enum.map(step.items, &item/1)
          }
        end),
      pins: Enum.map(ast.pins, &Map.take(&1, [:id, :x, :y]))
    }
  end

  defp item(%{from: _} = edge), do: Map.take(edge, [:from, :to, :label, :arrow])
  defp item(note), do: Map.take(note, [:placement, :target_ids, :text])

  test "forma canônica: cabeçalho, nós alinhados, grupos, passos, layout" do
    source = """
    diagram architecture "Plataforma"
    service api "API"   # comentário some na formatação
    database  pg "PostgreSQL"
    group "Dados" {
        queue mq "RabbitMQ"
    }
    step "Leitura" {
    api -> pg : SELECT
    }
    layout {
    pg at (420, 680)
    }
    """

    {:ok, ast} = Parser.parse(source)

    assert Printer.print(ast) == """
           diagram architecture "Plataforma"

           service  api "API"
           database pg  "PostgreSQL"

           group "Dados" {
             queue mq "RabbitMQ"
           }

           step "Leitura" {
             api -> pg : SELECT
           }

           layout {
             pg at (420, 680)
           }
           """
  end

  test "mensagens soltas continuam soltas (passos implícitos)" do
    {:ok, ast} = Parser.parse("a -> b : oi\nb --> a")

    assert Printer.print(ast) ==
             "diagram sequence\n\nparticipant a \"A\"\nparticipant b \"B\"\n\na -> b : oi\nb --> a\n"
  end

  for slug <- ~w(checkout arquitetura cqrs minimo) do
    test "#{slug}: imprimir e reler dá a mesma AST" do
      {:ok, ast} = Parser.parse(Fixtures.source(unquote(slug)))
      assert {:ok, again} = Parser.parse(Printer.print(ast))
      assert normalize(again) == normalize(ast)
    end
  end

  property "o printer é reversível" do
    check all(ast <- DslGenerators.ast(), max_runs: 200) do
      assert {:ok, again} = Parser.parse(Printer.print(ast))
      assert normalize(again) == normalize(ast)
    end
  end

  property "formatar duas vezes não muda nada" do
    check all(ast <- DslGenerators.ast(), max_runs: 100) do
      once = Printer.print(ast)
      {:ok, reparsed} = Parser.parse(once)
      assert Printer.print(reparsed) == once
    end
  end
end
