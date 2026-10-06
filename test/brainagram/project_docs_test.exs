defmodule Brainagram.ProjectDocsTest do
  @moduledoc """
  Os documentos do repositório (READMEs, guia de contribuição, código de
  conduta…) dizem coisas sobre o código: a versão, quantos testes existem,
  quantos idiomas a interface fala. Badge estático envelhece em silêncio; estes
  testes falham no dia em que o número do badge deixar de ser verdade, e quando
  um link entre os documentos quebrar.
  """

  use ExUnit.Case, async: true

  @readmes ~w(README.md README.pt-BR.md)
  @docs @readmes ++
          ~w(CONTRIBUTING.md CONTRIBUTING.pt-BR.md CODE_OF_CONDUCT.md
             CODE_OF_CONDUCT.pt-BR.md SECURITY.md SUPPORT.md CHANGELOG.md
             .github/PULL_REQUEST_TEMPLATE.md)

  describe "badges" do
    test "o badge do CI aponta para um workflow que existe" do
      for readme <- @readmes do
        workflow = badge(readme, ~r/actions\/workflows\/([\w.-]+)\/badge\.svg/)

        assert File.exists?(".github/workflows/#{workflow}"),
               "#{readme}: workflow #{workflow} não existe"
      end
    end

    test "a versão é a do mix.exs" do
      version = Mix.Project.config()[:version]

      for readme <- @readmes do
        assert badge(readme, ~r/badge\/vers(?:ion|%C3%A3o)-([^-]+)-/) == version,
               "#{readme}: o badge de versão precisa mostrar #{version} (mix.exs)"
      end
    end

    test "o Elixir mínimo é o do mix.exs" do
      "~> " <> minimum = Mix.Project.config()[:elixir]

      for readme <- @readmes do
        assert badge(readme, ~r/badge\/Elixir-([\d.]+)%2B-/) == minimum,
               "#{readme}: o badge do Elixir precisa mostrar #{minimum}+"
      end
    end

    test "Phoenix e LiveView na versão instalada" do
      for {app, pattern} <- [
            phoenix: ~r/badge\/Phoenix-([\d.]+)-/,
            phoenix_live_view: ~r/badge\/LiveView-([\d.]+)-/
          ],
          readme <- @readmes do
        assert badge(readme, pattern) == major_minor(app),
               "#{readme}: o badge de #{app} precisa mostrar #{major_minor(app)}"
      end
    end

    test "a quantidade de idiomas é a do seletor" do
      count = length(BrainagramWeb.Locale.supported())

      for readme <- @readmes do
        assert badge(readme, ~r/badge\/(?:languages|idiomas)-(\d+)-/) == to_string(count),
               "#{readme}: o badge de idiomas precisa mostrar #{count}"
      end
    end

    # O badge mostra a contagem arredondada para baixo, de 50 em 50
    # ("350+"), então só muda quando a suíte cruza uma dezena de cinquenta.
    test "a quantidade de testes não está desatualizada nem exagerada" do
      floor = div(count_tests(), 50) * 50

      for readme <- @readmes do
        assert badge(readme, ~r/badge\/(?:tests|testes)-(\d+)%2B/) == to_string(floor),
               """
               #{readme}: a suíte tem #{count_tests()} testes; o badge precisa mostrar #{floor}+.
               Atualize o número nos dois READMEs.
               """
      end
    end

    test "o Contributor Covenant citado é o do código de conduta" do
      [version] =
        Regex.run(
          ~r/Contributor Covenant\]\([^)]*\), version ([\d.]+)/,
          read("CODE_OF_CONDUCT.md"),
          capture: :all_but_first
        )

      for readme <- @readmes do
        assert badge(readme, ~r/Contributor%20Covenant-([\d.]+)-/) == version
      end
    end
  end

  describe "documentos" do
    test "os links relativos apontam para arquivos e seções que existem" do
      broken =
        for doc <- @docs,
            target <- links(read(doc)),
            not String.starts_with?(target, ["http", "mailto:", "../../"]),
            problem = check_link(doc, target),
            problem != nil,
            do: "#{doc} → #{target} (#{problem})"

      assert broken == [], "links quebrados:\n" <> Enum.join(broken, "\n")
    end

    test "as imagens dos cabeçalhos existem" do
      for doc <- @docs,
          [src] <- Regex.scan(~r/(?:src|srcset)="([^"]+)"/, read(doc), capture: :all_but_first),
          not String.starts_with?(src, "http") do
        assert File.exists?(Path.join(Path.dirname(doc), src)), "#{doc}: imagem #{src} não existe"
      end
    end

    test "o changelog tem a seção Unreleased" do
      assert read("CHANGELOG.md") =~ ~r/^## \[Unreleased\]$/m
    end
  end

  # ── apoio ─────────────────────────────────────────────────────────────────

  defp read(path), do: File.read!(path)

  defp badge(readme, pattern) do
    case Regex.run(pattern, read(readme), capture: :all_but_first) do
      [value] -> value
      nil -> flunk("#{readme}: badge não encontrado (#{inspect(pattern)})")
    end
  end

  defp major_minor(app) do
    app
    |> Application.spec(:vsn)
    |> to_string()
    |> String.split(".")
    |> Enum.take(2)
    |> Enum.join(".")
  end

  defp count_tests do
    "test/**/*_test.exs"
    |> Path.wildcard()
    |> Enum.map(fn file ->
      ~r/^\s*(?:test|property)\s+"/m |> Regex.scan(read(file)) |> length()
    end)
    |> Enum.sum()
  end

  defp links(markdown) do
    markdown
    |> strip_code()
    |> then(&Regex.scan(~r/\]\(([^)\s]+)\)/, &1, capture: :all_but_first))
    |> List.flatten()
  end

  defp check_link(doc, target) do
    {path, anchor} =
      case String.split(target, "#", parts: 2) do
        [path, anchor] -> {path, anchor}
        [path] -> {path, nil}
      end

    file = if path == "", do: doc, else: Path.join(Path.dirname(doc), path)

    cond do
      not File.exists?(file) ->
        "arquivo não existe"

      anchor && String.ends_with?(file, ".md") && anchor not in anchors(file) ->
        "seção não existe"

      true ->
        nil
    end
  end

  # As âncoras que o GitHub gera para os títulos: minúsculas, sem pontuação,
  # espaços viram hífens (letras acentuadas ficam).
  defp anchors(file) do
    ~r/^#+ (.+)$/m
    |> Regex.scan(file |> read() |> strip_code(), capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(fn title ->
      title
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^\p{L}\p{N}\- _]/u, "")
      |> String.replace(" ", "-")
    end)
  end

  defp strip_code(markdown), do: String.replace(markdown, ~r/```.*?```/s, "")
end
