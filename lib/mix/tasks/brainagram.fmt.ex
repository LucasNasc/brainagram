defmodule Mix.Tasks.Brainagram.Fmt do
  @shortdoc "Formata arquivos .brain com o printer canônico"

  @moduledoc """
  Formata diagramas `.brain` do repositório com a forma canônica da DSL — a
  mesma do comando "Formatar" do editor (`Dsl.Printer`).

      mix brainagram.fmt                      # todos os **/*.brain
      mix brainagram.fmt docs/fluxos/*.brain
      mix brainagram.fmt --check-formatted    # para CI: falha se algo mudaria

  O printer canônico não preserva comentários. Arquivos com `#` ou `//` são
  pulados com aviso, a menos que se passe `--drop-comments`.

  Reusa exatamente os módulos de domínio: não sobe Phoenix nem banco.
  """

  use Mix.Task

  alias Brainagram.Domain.Diagramming.Dsl.{Parser, Printer}

  @switches [check_formatted: :boolean, drop_comments: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("compile", [])
    {opts, patterns, _} = OptionParser.parse(argv, strict: @switches)
    files = files(patterns)

    if files == [], do: Mix.shell().info("Nenhum arquivo .brain encontrado.")

    results = Enum.map(files, &format_file(&1, opts))

    failed = Enum.filter(results, &match?({:error, _}, &1))
    unformatted = Enum.filter(results, &match?({:unformatted, _}, &1))

    cond do
      failed != [] ->
        Mix.raise("#{length(failed)} arquivo(s) com erro de sintaxe")

      opts[:check_formatted] && unformatted != [] ->
        Mix.raise(
          "arquivos que não estão formatados:\n" <>
            Enum.map_join(unformatted, "\n", fn {:unformatted, f} -> "  * #{f}" end)
        )

      true ->
        :ok
    end
  end

  defp files([]) do
    "**/*.brain"
    |> Path.wildcard()
    |> Enum.reject(&String.starts_with?(&1, ["_build/", "deps/", "node_modules/"]))
  end

  defp files(patterns), do: patterns |> Enum.flat_map(&Path.wildcard/1) |> Enum.uniq()

  defp format_file(file, opts) do
    source = File.read!(file)

    case Parser.parse(source) do
      {:error, errors} ->
        Enum.each(errors, &Mix.shell().error("#{file}:#{&1.line}: #{&1.message}"))
        {:error, file}

      {:ok, ast} ->
        formatted = Printer.print(ast)

        cond do
          formatted == source ->
            {:ok, file}

          Parser.comments?(source) and !opts[:drop_comments] ->
            Mix.shell().info(
              "#{file}: tem comentários, pulado (use --drop-comments para formatar mesmo assim)"
            )

            {:ok, file}

          opts[:check_formatted] ->
            {:unformatted, file}

          true ->
            File.write!(file, formatted)
            Mix.shell().info("formatado: #{file}")
            {:ok, file}
        end
    end
  end
end
