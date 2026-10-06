defmodule Brainagram.Domain.Diagramming.Layout.UntangleTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Brainagram.Domain.Diagramming.Authoring
  alias Brainagram.Domain.Diagramming.Dsl.Parser
  alias Brainagram.Domain.Diagramming.Layout.{Hints, Quality, Untangle}
  alias Brainagram.Test.{DslGenerators, Fixtures}

  setup do
    %{source: Fixtures.tangled_architecture_source()}
  end

  defp overlap?(a, b),
    do: a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h

  test "desembaraça: bem menos cruzamentos, nenhuma seta por cima de caixa", %{source: source} do
    assert {:ok, result} = Untangle.run(source)

    assert result.improved
    assert result.after.crossings * 2 < result.before.crossings
    assert result.after.node_hits == 0
    assert result.after.group_hits == 0
    assert Quality.score(result.after) < Quality.score(result.before)
  end

  test "as métricas devolvidas são as do desenho que o editor vai mostrar", %{source: source} do
    {:ok, result} = Untangle.run(source)
    assert result.after == result.source |> Fixtures.scene!() |> Quality.measure()
  end

  test "só o bloco layout muda: soltar as posições devolve o texto original", %{source: source} do
    {:ok, %{source: organized}} = Untangle.run(source)

    assert organized =~ "layout {"
    assert organized =~ ~s(database pg "Postgres"   # principal)
    assert Hints.clear(organized) == source
  end

  test "grupos não se sobrepõem, caixas também não", %{source: source} do
    {:ok, %{source: organized}} = Untangle.run(source)
    scene = Fixtures.scene!(organized)

    for list <- [scene.groups, scene.nodes],
        {a, i} <- Enum.with_index(list),
        {b, j} <- Enum.with_index(list),
        i < j do
      refute overlap?(a, b), "#{a.id} e #{b.id} se sobrepõem"
    end
  end

  test "é determinístico e idempotente", %{source: source} do
    {:ok, first} = Untangle.run(source)
    assert {:ok, ^first} = Untangle.run(source)

    assert {:ok, %{improved: false, source: same}} = Untangle.run(first.source)
    assert same == first.source
  end

  test "o exemplo de arquitetura do catálogo também melhora" do
    {:ok, result} = Untangle.run(Fixtures.architecture_source())

    assert result.improved
    assert result.after.crossings < result.before.crossings
  end

  test "sequência não se organiza (as setas já não se cruzam)" do
    assert {:error, :not_architecture} = Untangle.run(Fixtures.sequence_source())
  end

  test "fonte inválido volta como erro de sintaxe" do
    assert {:error, {:syntax, _}} = Untangle.run(~s(diagram architecture "x"\na ->))
  end

  property "nunca piora e sempre deixa um fonte válido" do
    check all(
            source <- DslGenerators.source(kind: "architecture"),
            max_runs: 40
          ) do
      assert {:ok, result} = Untangle.run(source)
      assert {:ok, _} = Parser.parse(result.source)
      assert Quality.score(result.after) <= Quality.score(result.before)
      if not result.improved, do: assert(result.source == source)
    end
  end

  describe "Authoring" do
    test "untangle devolve o fonte novo e as métricas", %{source: source} do
      assert {:ok, organized, %{improved: true, before: before, after: after_}} =
               Authoring.run(source, "untangle", %{})

      assert organized =~ "layout {"
      assert after_.crossings < before.crossings
    end

    test "sem melhora, o fonte volta igual", %{source: source} do
      {:ok, organized, _meta} = Authoring.untangle(source)
      assert {:ok, ^organized, %{improved: false}} = Authoring.untangle(organized)
    end
  end
end
