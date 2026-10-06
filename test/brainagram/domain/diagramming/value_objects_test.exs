defmodule Brainagram.Domain.Diagramming.ValueObjectsTest do
  use ExUnit.Case, async: true

  alias Brainagram.Domain.Diagramming.ValueObjects.{Kind, Slug, Title, Visibility}

  describe "Slug" do
    test "aceita o formato de URL e rejeita o resto" do
      assert {:ok, _} = Slug.new("checkout")
      assert {:ok, _} = Slug.new("meu-fluxo_2")
      assert {:error, :invalid_slug} = Slug.new("ab")
      assert {:error, :invalid_slug} = Slug.new("com espaço")
      assert {:error, :invalid_slug} = Slug.new("-comeca-com-hifen")
      assert {:error, :invalid_slug} = Slug.new(nil)
    end

    test "normaliza caixa e espaços das pontas" do
      assert {:ok, slug} = Slug.new("  Checkout  ")
      assert Slug.to_string(slug) == "checkout"
    end

    @tag :regression
    test "generate/0 sempre produz um slug que new/1 aceita" do
      # Regressão: o gerador usava base64url, cujo alfabeto inclui `-` e `_`.
      # Cerca de 3% dos slugs gerados começavam com um deles e eram rejeitados
      # pelo próprio value object — falha rara, difícil de atribuir em produção.
      for _ <- 1..2_000 do
        gerado = Slug.to_string(Slug.generate())

        assert {:ok, _} = Slug.new(gerado), "slug gerado inválido: #{inspect(gerado)}"
      end
    end

    test "generate/0 não repete" do
      gerados = for _ <- 1..500, do: Slug.to_string(Slug.generate())
      assert length(Enum.uniq(gerados)) == 500
    end
  end

  describe "Title" do
    test "cai no padrão quando vazio e recusa quando longo demais" do
      assert {:ok, padrao} = Title.new(nil)
      assert Title.to_string(padrao) == "Sem título"

      assert {:ok, titulo} = Title.new("  Checkout  ")
      assert Title.to_string(titulo) == "Checkout"

      assert {:error, :title_too_long} = Title.new(String.duplicate("a", 161))
    end
  end

  describe "Kind e Visibility" do
    test "aceitam átomo e string, recusam desconhecido" do
      assert {:ok, :sequence} = Kind.new("sequence")
      assert {:ok, :architecture} = Kind.new(:architecture)
      assert {:error, :invalid_kind} = Kind.new("fluxograma")

      assert {:ok, :public} = Visibility.new(nil)
      assert {:ok, :private} = Visibility.new("private")
      assert {:ok, :public} = Visibility.new(true)
      assert {:error, :invalid_visibility} = Visibility.new("talvez")
    end
  end
end
