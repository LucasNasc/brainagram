defmodule Brainagram.Domain.Diagramming.LayoutPinsTest do
  @moduledoc "Fase D da spec 001: os motores de layout respeitam o bloco `layout`."

  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.Authoring
  alias Brainagram.Test.Fixtures

  defp node(scene, id), do: Enum.find(scene.nodes, &(&1.id == id))

  defp overlap?(a, b) do
    a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
  end

  describe "arquitetura" do
    setup do
      %{source: Fixtures.architecture_source()}
    end

    test "nó fixado fica exatamente onde foi solto", %{source: source} do
      {:ok, pinned} = Authoring.pin_node(source, "pg", {904, 120})
      scene = Fixtures.scene!(pinned)

      assert %{x: 904, y: 120, pinned: true} = node(scene, "pg")
      assert scene.has_layout
      refute node(scene, "api").pinned
    end

    test "os demais desviam da caixa fixada", %{source: source} do
      auto = Fixtures.scene!(source)
      api = node(auto, "api")

      # solta o Redis bem em cima da API
      {:ok, pinned} = Authoring.pin_node(source, "redis", {api.x, api.y})
      scene = Fixtures.scene!(pinned)
      redis = node(scene, "redis")

      for other <- scene.nodes, other.id != "redis" do
        refute overlap?(other, redis), "#{other.id} ficou em cima do nó fixado"
      end
    end

    test "fixar o destino acima da origem desenha a seta subindo", %{source: source} do
      {:ok, pinned} = Authoring.pin_node(source, "s3", {40, 0})
      scene = Fixtures.scene!(pinned)
      edge = Enum.find(scene.edges, &(&1.to == "s3"))

      assert edge.y2 < edge.y1
    end

    test "cena cresce para caber o nó fixado longe", %{source: source} do
      {:ok, pinned} = Authoring.pin_node(source, "s3", {3000, 2000})
      scene = Fixtures.scene!(pinned)
      assert scene.width >= 3000 and scene.height >= 2000
    end

    test "apagar o bloco layout restaura o automático", %{source: source} do
      {:ok, pinned} = Authoring.pin_node(source, "pg", {904, 120})
      {:ok, cleared} = Authoring.clear_layout_hints(pinned)

      assert cleared == source
      assert Fixtures.scene!(cleared) == Fixtures.scene!(source)
    end
  end

  describe "sequência" do
    test "participante fixado fica no x pedido; o y continua o do cabeçalho" do
      source = Fixtures.sequence_source()
      auto = Fixtures.scene!(source)
      {:ok, pinned} = Authoring.pin_node(source, "db", {60, 900})
      scene = Fixtures.scene!(pinned)

      assert %{x: 60, pinned: true} = node(scene, "db")
      assert node(scene, "db").y == node(auto, "db").y

      for a <- scene.nodes, b <- scene.nodes, a.id < b.id do
        refute a.x < b.x + b.w and b.x < a.x + a.w, "#{a.id} e #{b.id} se sobrepõem"
      end
    end
  end

  test "cada nó informa o grupo para o canvas saber onde caiu" do
    scene = Fixtures.scene!(Fixtures.architecture_source())
    assert node(scene, "pg").group == "Dados"
    assert node(scene, "s3").group == nil
  end
end
