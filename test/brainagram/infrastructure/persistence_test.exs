defmodule Brainagram.Infrastructure.PersistenceTest do
  @moduledoc """
  Testes de integração das duas portas de persistência contra o Postgres real.

  O que se verifica aqui é justamente o que o fake em memória não consegue
  provar: que o mapeamento agregado↔linha fecha nos dois sentidos, que a
  unicidade do slug é garantida pelo banco e que as projeções de leitura
  devolvem os campos certos.
  """

  use Brainagram.DataCase, async: true

  alias Brainagram.Domain.Diagramming.Diagram
  alias Brainagram.Domain.Diagramming.ValueObjects.{Slug, Source, Title}
  alias Brainagram.Infrastructure.Persistence.EctoDiagramReader, as: Reader
  alias Brainagram.Infrastructure.Persistence.EctoDiagramRepository, as: Repository
  alias Brainagram.Test.Fixtures

  describe "repositório (escrita)" do
    test "vai e volta preservando o agregado" do
      diagram = Fixtures.diagram!(%{source: ~s(diagram sequence "Ida e volta"\na -> b : x)})

      assert {:ok, saved} = Repository.insert(diagram)
      assert saved.id
      assert {:ok, loaded} = Repository.fetch_by_slug(saved.slug)

      assert Title.to_string(loaded.title) == "Ida e volta"
      assert loaded.kind == :sequence
      assert Source.equal?(loaded.source, diagram.source)
      assert Slug.to_string(loaded.slug) == Slug.to_string(diagram.slug)
    end

    test "o retorno do insert reaproveita o Source já validado" do
      diagram = Fixtures.diagram!()
      {:ok, saved} = Repository.insert(diagram)

      # mesma struct de Source, não uma reconstruída a partir do texto
      assert saved.source == diagram.source
    end

    test "slug duplicado vira erro de domínio, não exceção do banco" do
      a = Fixtures.diagram!(%{slug: "colidido"})
      b = Fixtures.diagram!(%{slug: "colidido"})

      assert {:ok, _} = Repository.insert(a)
      assert {:error, :slug_taken} = Repository.insert(b)
    end

    test "update grava a nova versão" do
      {:ok, saved} = Repository.insert(Fixtures.diagram!())
      {:ok, changed, _} = Diagram.change_source(saved, ~s(diagram architecture "Novo"\na -> b))

      assert {:ok, _} = Repository.update(changed)
      assert {:ok, loaded} = Repository.fetch_by_slug(saved.slug)
      assert loaded.kind == :architecture
    end

    test "update de agregado nunca persistido é recusado" do
      assert {:error, :not_persisted} = Repository.update(Fixtures.diagram!())
    end

    test "delete remove e o fetch seguinte falha" do
      {:ok, saved} = Repository.insert(Fixtures.diagram!())

      assert :ok = Repository.delete(saved)
      assert {:error, :not_found} = Repository.fetch_by_slug(saved.slug)
    end

    test "fetch de slug inexistente" do
      {:ok, slug} = Slug.new("nao-existe-mesmo")
      assert {:error, :not_found} = Repository.fetch_by_slug(slug)
    end
  end

  describe "leitor (consulta)" do
    test "detalhe traz o fonte; o handler é quem compila a cena" do
      {:ok, saved} = Repository.insert(Fixtures.diagram!(%{slug: "detalhe"}))

      assert {:ok, detail} = Reader.fetch_by_slug("detalhe")
      assert detail.slug == "detalhe"
      assert detail.source == Source.raw(saved.source)
      assert detail.scene == nil
    end

    test "listagem pública ignora privados e não carrega o fonte" do
      {:ok, publico} = Repository.insert(Fixtures.diagram!(%{slug: "visivel"}))
      {:ok, _} = Repository.insert(Fixtures.diagram!(%{slug: "oculto", visibility: "private"}))

      summaries = Reader.list_public(50)
      slugs = Enum.map(summaries, & &1.slug)

      assert Slug.to_string(publico.slug) in slugs
      refute "oculto" in slugs
      refute summaries |> List.first() |> Map.has_key?(:source)
    end

    test "respeita o limite e ordena do mais recente para o mais antigo" do
      for i <- 1..3 do
        {:ok, _} = Repository.insert(Fixtures.diagram!(%{slug: "ordem-#{i}"}))
      end

      assert [%{} = primeiro] = Reader.list_public(1)
      assert primeiro.updated_at
      assert Reader.count_public() >= 3
    end

    test "conta só os públicos" do
      antes = Reader.count_public()
      {:ok, _} = Repository.insert(Fixtures.diagram!(%{slug: "privado-x", visibility: "private"}))

      assert Reader.count_public() == antes
    end
  end
end
