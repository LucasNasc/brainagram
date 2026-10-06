defmodule Brainagram.Domain.Diagramming.DiagramTest do
  @moduledoc """
  Testes do agregado. Sem banco, sem Ecto, sem aplicação — é o retorno direto
  de ter separado a entidade do schema.
  """

  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.Diagram
  alias Brainagram.Domain.Diagramming.Events
  alias Brainagram.Domain.Diagramming.ValueObjects.{Slug, Source, Title}
  alias Brainagram.Test.Fixtures

  @valid ~s(diagram sequence "Checkout"\nuser -> api : POST /orders)

  describe "create/1" do
    test "deriva título e tipo do fonte, nunca de campo digitado" do
      assert {:ok, diagram, _events} = Diagram.create(%{source: @valid})

      assert Title.to_string(diagram.title) == "Checkout"
      assert diagram.kind == :sequence
    end

    test "gera slug quando não informado e respeita o informado" do
      assert {:ok, gerado, _} = Diagram.create(%{source: @valid})
      assert {:ok, escolhido, _} = Diagram.create(%{source: @valid, slug: "meu-fluxo"})

      assert String.length(Slug.to_string(gerado.slug)) >= 3
      assert Slug.to_string(escolhido.slug) == "meu-fluxo"
    end

    test "recusa slug fora do formato" do
      assert {:error, :invalid_slug} = Diagram.create(%{source: @valid, slug: "NÃO Vale"})
    end

    test "recusa fonte que não compila, com a linha do problema" do
      assert {:error, {:syntax, [erro | _]}} =
               Diagram.create(%{source: "diagram sequence \"X\"\nlinha invalida"})

      assert erro.line == 2
    end

    test "nasce público por padrão e aceita privado" do
      assert {:ok, publico, _} = Diagram.create(%{source: @valid})
      assert {:ok, privado, _} = Diagram.create(%{source: @valid, visibility: "private"})

      assert Diagram.public?(publico)
      refute Diagram.public?(privado)
    end

    test "emite DiagramCreated com dados primitivos" do
      assert {:ok, _diagram, [%Events.DiagramCreated{} = event]} =
               Diagram.create(%{source: @valid})

      assert event.title == "Checkout"
      assert event.kind == "sequence"
      assert is_binary(event.slug)
    end
  end

  describe "change_source/2" do
    test "re-deriva título e tipo" do
      diagram = Fixtures.diagram!(%{source: @valid})

      assert {:ok, updated, [event]} =
               Diagram.change_source(diagram, ~s(diagram architecture "Plataforma"\na -> b))

      assert Title.to_string(updated.title) == "Plataforma"
      assert updated.kind == :architecture
      assert event.previous_kind == "sequence"
      assert event.kind == "architecture"
    end

    test "fonte idêntico não gera evento — é o sinal de 'nada mudou'" do
      diagram = Fixtures.diagram!(%{source: @valid})

      assert {:ok, same, []} = Diagram.change_source(diagram, @valid)
      assert Source.equal?(same.source, diagram.source)
    end

    test "fonte inválido não altera o agregado" do
      diagram = Fixtures.diagram!(%{source: @valid})

      assert {:error, {:syntax, _}} = Diagram.change_source(diagram, "?!?")
    end
  end

  describe "change_visibility/2" do
    test "alterna e emite evento" do
      diagram = Fixtures.diagram!()

      assert {:ok, privado, [%Events.DiagramVisibilityChanged{visibility: "private"}]} =
               Diagram.change_visibility(diagram, "private")

      refute Diagram.public?(privado)
    end

    test "mesma visibilidade não gera evento" do
      diagram = Fixtures.diagram!(%{visibility: "public"})
      assert {:ok, _same, []} = Diagram.change_visibility(diagram, "public")
    end

    test "valor desconhecido é recusado" do
      assert {:error, :invalid_visibility} =
               Diagram.change_visibility(Fixtures.diagram!(), "talvez")
    end
  end

  describe "fork/2" do
    test "copia o conteúdo sob slug novo e nasce privado" do
      origin = Fixtures.diagram!(%{source: @valid, visibility: "public"})

      assert {:ok, copy, events} = Diagram.fork(origin)

      assert Source.equal?(copy.source, origin.source)
      refute Slug.to_string(copy.slug) == Slug.to_string(origin.slug)
      refute Diagram.public?(copy)
      assert Enum.any?(events, &match?(%Events.DiagramForked{}, &1))
    end

    test "o evento de bifurcação guarda a origem" do
      origin = Fixtures.diagram!(%{slug: "original"})
      {:ok, copy, events} = Diagram.fork(origin)
      forked = Enum.find(events, &match?(%Events.DiagramForked{}, &1))

      assert forked.origin_slug == "original"
      assert forked.slug == Slug.to_string(copy.slug)
    end
  end

  test "scene/1 delega ao value object — o agregado não desenha" do
    diagram = Fixtures.diagram!(%{source: @valid})
    scene = Diagram.scene(diagram)

    assert scene.kind == :sequence
    assert scene.width > 0
  end
end
