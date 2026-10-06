defmodule Mix.Tasks.Brainagram.Render do
  @shortdoc "Gera SVG ou PNG de um diagrama .brain (para CI)"

  @moduledoc """
  Renderiza um diagrama `.brain` no seu estado final, fora do navegador.

      mix brainagram.render docs/checkout.brain                  # → docs/checkout.svg
      mix brainagram.render docs/checkout.brain -o out/c.svg
      mix brainagram.render docs/checkout.brain --format png --scale 2

  O SVG é gerado em Elixir puro (`Render.Svg`), com as cores do tema claro. O
  PNG rasteriza esse SVG com a primeira ferramenta disponível no `PATH`:
  `resvg`, `rsvg-convert` ou `magick` (ImageMagick).
  """

  use Mix.Task

  alias Brainagram.Domain.Diagramming.Render.Svg
  alias Brainagram.Domain.Diagramming.ValueObjects.Source

  @switches [output: :string, format: :string, scale: :integer]
  @aliases [o: :output, f: :format]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("compile", [])
    {opts, args, _} = OptionParser.parse(argv, strict: @switches, aliases: @aliases)

    input =
      case args do
        [file] ->
          file

        _ ->
          Mix.raise(
            "uso: mix brainagram.render ARQUIVO.brain [-o saída] [--format svg|png] [--scale 2]"
          )
      end

    format = opts[:format] || infer_format(opts[:output]) || "svg"
    output = opts[:output] || Path.rootname(input) <> "." <> format

    svg =
      case input |> File.read!() |> Source.new() do
        {:ok, source} ->
          source |> Source.scene() |> Svg.render()

        {:error, {:syntax, errors}} ->
          Mix.raise(Enum.map_join(errors, "\n", &"#{input}:#{&1.line}: #{&1.message}"))

        {:error, reason} ->
          Mix.raise("#{input}: #{inspect(reason)}")
      end

    File.mkdir_p!(Path.dirname(output))

    case format do
      "svg" -> File.write!(output, svg)
      "png" -> rasterize(svg, output, opts[:scale] || 2)
      other -> Mix.raise("formato desconhecido: #{other} (use svg ou png)")
    end

    Mix.shell().info("gerado: #{output}")
  end

  defp infer_format(nil), do: nil
  defp infer_format(path), do: path |> Path.extname() |> String.trim_leading(".") |> blank()

  defp blank(""), do: nil
  defp blank(ext), do: ext

  defp rasterize(svg, output, scale) do
    tmp = Path.join(System.tmp_dir!(), "brainagram-#{System.unique_integer([:positive])}.svg")
    File.write!(tmp, svg)

    try do
      {exe, args} =
        cond do
          exe = System.find_executable("resvg") ->
            {exe, ["--zoom", to_string(scale), tmp, output]}

          exe = System.find_executable("rsvg-convert") ->
            {exe, ["-z", to_string(scale), "-o", output, tmp]}

          exe = System.find_executable("magick") ->
            {exe, ["-density", to_string(96 * scale), tmp, output]}

          true ->
            Mix.raise("para PNG, instale resvg, rsvg-convert ou ImageMagick (ou gere SVG)")
        end

      case System.cmd(exe, args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {out, code} -> Mix.raise("#{Path.basename(exe)} falhou (#{code}): #{out}")
      end
    after
      File.rm(tmp)
    end
  end
end
