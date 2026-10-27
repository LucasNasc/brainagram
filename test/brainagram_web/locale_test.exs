defmodule BrainagramWeb.LocaleTest do
  use BrainagramWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Brainagram.Domain.Diagramming.Dsl.Parser
  alias BrainagramWeb.{ErrorMessages, Locale}

  describe "escolha do idioma" do
    test "normaliza o que vem do cookie e do navegador" do
      assert Locale.normalize("en") == "en"
      assert Locale.normalize("en-US") == "en"
      assert Locale.normalize("pt-BR") == "pt_BR"
      assert Locale.normalize("pt_BR") == "pt_BR"
      assert Locale.normalize("zh-CN") == "zh"
      assert Locale.normalize("zh-Hans") == "zh"
      assert Locale.normalize("ru-RU") == "ru"
      assert Locale.normalize("it") == "it"
      assert Locale.normalize("ja-JP") == "ja"
      assert Locale.normalize("hi-IN") == "hi"
      assert Locale.normalize("fr") == nil
    end

    test "cada idioma tem seu `<html lang>` e um nome no próprio idioma" do
      assert Enum.map(Locale.supported(), &Locale.html_lang/1) ==
               ~w(pt-BR en zh-CN ru it ja hi)

      assert Locale.html_lang("xx") == "pt-BR"
      assert Enum.all?(Locale.languages(), &(&1.name != "" and &1.short != ""))
    end

    test "o seletor oferece os sete idiomas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/new")

      for code <- Locale.supported() do
        assert has_element?(view, "#locale-menu #locale-#{code}[data-bg-locale=#{code}]")
      end
    end

    test "o navegador em japonês abre a interface em japonês", %{conn: conn} do
      conn = conn |> put_req_header("accept-language", "ja-JP,ja;q=0.9") |> get(~p"/")
      assert conn.assigns.locale == "ja"
      assert html_response(conn, 200) =~ ~s(<html lang="ja">)
    end

    test "sem cookie nem cabeçalho, português", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert conn.assigns.locale == "pt_BR"
      assert html_response(conn, 200) =~ ~s(<html lang="pt-BR">)
    end

    test "o cookie manda", %{conn: conn} do
      conn =
        conn
        |> put_req_header("accept-language", "pt-BR")
        |> put_req_cookie("bg_locale", "en")
        |> get(~p"/")

      assert conn.assigns.locale == "en"
      assert html_response(conn, 200) =~ ~s(<html lang="en">)
    end

    test "sem cookie, o primeiro idioma suportado do navegador", %{conn: conn} do
      conn = conn |> put_req_header("accept-language", "fr-FR,en;q=0.8,pt;q=0.5") |> get(~p"/")
      assert conn.assigns.locale == "en"
    end
  end

  describe "editor em inglês" do
    setup %{conn: conn} do
      {:ok, view, _html} = conn |> put_req_cookie("bg_locale", "en") |> live(~p"/new")
      %{view: view}
    end

    test "a bandeira dos EUA fica marcada e a interface fala inglês", %{view: view} do
      assert has_element?(view, "#locale-en[aria-checked=true]")
      assert has_element?(view, "#locale-pt_BR[aria-checked=false]")
      assert has_element?(view, "button", "Save")
      assert has_element?(view, "#clear-layout", "Release positions")
      assert has_element?(view, "#examples-menu", "Sequence — Checkout")
    end

    test "avisos e contagens no plural também", %{view: view} do
      tangled = Brainagram.Test.Fixtures.tangled_architecture_source()
      view |> element("form[phx-change=edit]") |> render_change(%{"source" => tangled})

      view |> element("#untangle-layout") |> render_click()
      # os números dependem da geometria; o que se testa aqui é o plural traduzido
      assert render(view) =~ ~r/Arrows tidied: \d+ → \d+ crossings/
    end

    test "erro de sintaxe traduzido na barra de erros", %{view: view} do
      html =
        view
        |> element("form[phx-change=edit]")
        |> render_change(%{"source" => "diagram sequence\nisto não é dsl"})

      assert html =~ "couldn&#39;t understand this line"
      assert has_element?(view, ".ba-validity--err", "1 error")
    end
  end

  test "editor em português: a bandeira do Brasil fica marcada", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/new")
    assert has_element?(view, "#locale-pt_BR[aria-checked=true]")
    assert has_element?(view, "button", "Salvar")
  end

  # o texto vem do .po de cada idioma: aqui só se confere que ele é usado
  for locale <- ~w(zh ru it ja hi) do
    test "editor em #{locale}: bandeira marcada e textos traduzidos", %{conn: conn} do
      locale = unquote(locale)

      translated =
        Gettext.with_locale(BrainagramWeb.Gettext, locale, fn ->
          Gettext.gettext(BrainagramWeb.Gettext, "Salvar")
        end)

      refute translated == "Salvar"

      {:ok, view, _html} = conn |> put_req_cookie("bg_locale", locale) |> live(~p"/new")
      assert has_element?(view, "#locale-#{locale}[aria-checked=true]")
      assert has_element?(view, "button", translated)
    end
  end

  describe "ErrorMessages" do
    test "erros do parser pelo código, com os valores no lugar" do
      {:error, [error]} = Parser.parse("diagram mindmap")
      assert error.code == :unknown_kind

      assert ErrorMessages.parse_error(error) =~ "tipo de diagrama desconhecido: mindmap"

      Gettext.with_locale(BrainagramWeb.Gettext, "en", fn ->
        assert ErrorMessages.parse_error(error) ==
                 "unknown diagram type: mindmap (use sequence or architecture)"

        assert ErrorMessages.describe(:not_found) == "Diagram not found."
      end)
    end
  end

  test "toda mensagem do português tem tradução em todos os idiomas" do
    for locale <- Locale.supported() -- ["pt_BR"] do
      files = Path.wildcard("priv/gettext/#{locale}/LC_MESSAGES/*.po")
      names = Enum.map(files, &Path.basename/1)
      assert "default.po" in names and "examples.po" in names, "faltam .po em #{locale}"
    end

    for file <- Path.wildcard("priv/gettext/*/LC_MESSAGES/*.po"),
        %{} = message <- Expo.PO.parse_file!(file).messages do
      untranslated =
        case message do
          %Expo.Message.Singular{msgstr: msgstr} ->
            msgstr in [[], [""]]

          %Expo.Message.Plural{msgstr: msgstr} ->
            Enum.any?(Map.values(msgstr), &(&1 in [[], [""]]))
        end

      refute untranslated, "sem tradução em #{file}: #{inspect(message.msgid)}"

      # `mix gettext.merge` preenche texto parecido como "fuzzy": é um chute
      # (costuma estar errado) e precisa ser revisado à mão
      refute "fuzzy" in List.flatten(message.flags),
             "tradução fuzzy (não revisada) em #{file}: #{inspect(message.msgid)}"
    end
  end
end
