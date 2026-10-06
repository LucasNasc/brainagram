defmodule Brainagram.ArchitectureTest do
  @moduledoc """
  A regra de dependência, executável.

  Um diagrama de camadas no README envelhece em silêncio. Estes testes falham no
  CI no dia em que alguém adicionar o `alias` errado — que é o único momento em
  que a regra importa de verdade.
  """

  use ExUnit.Case, async: true

  defp sources(layer) do
    "lib/brainagram/#{layer}/**/*.ex"
    |> Path.wildcard()
    |> Enum.map(&{&1, &1 |> File.read!() |> code_only()})
  end

  # Documentação e comentário citam o que a camada *não* usa o tempo todo
  # ("não conhece Ecto") — analisar o arquivo cru transformaria a própria
  # explicação da regra em violação dela.
  defp code_only(source) do
    source
    |> String.replace(~r/"""(?:.|\n)*?"""/, "")
    |> String.replace(~r/^\s*#.*$/m, "")
  end

  defp offenders(layer, pattern) do
    for {path, code} <- sources(layer), Regex.match?(pattern, code), do: path
  end

  test "domínio, aplicação e shared não conhecem a infraestrutura" do
    for layer <- ~w(domain application shared) do
      assert offenders(layer, ~r/Brainagram\.Infrastructure/) == [],
             """
             `#{layer}/` referenciou Brainagram.Infrastructure.

             As implementações concretas entram por config/config.exs, nunca por
             alias. Se a camada precisa de algo novo da infraestrutura, o caminho
             é declarar uma porta.
             """
    end
  end

  test "o domínio não conhece Ecto nem Phoenix" do
    assert offenders("domain", ~r/\bEcto\b/) == [],
           "regra de negócio não pode depender de persistência"

    assert offenders("domain", ~r/\bPhoenix\b/) == [],
           "regra de negócio não pode depender do framework web"
  end

  test "a camada de aplicação usa Ecto só como biblioteca de validação" do
    # Ecto.Changeset é permitido (validação de comando); Repo e Query não.
    assert offenders("application", ~r/Ecto\.(Repo|Query|Schema)/) == [],
           "consulta e persistência pertencem à infraestrutura, atrás de uma porta"
  end

  test "a camada web fala com o barramento, não com repositórios" do
    web =
      "lib/brainagram_web/**/*.ex"
      |> Path.wildcard()
      |> Enum.map(&{&1, &1 |> File.read!() |> code_only()})

    violations =
      for {path, code} <- web,
          Regex.match?(~r/Brainagram\.(Infrastructure|Repo)\b/, code),
          do: path

    assert violations == [],
           "a web deve passar por Brainagram.Application.Bus"
  end

  test "todo comando e query declara um handler que existe e implementa o contrato" do
    messages =
      Path.wildcard("lib/brainagram/application/{commands,queries}/*.ex")
      |> Enum.map(fn path ->
        module =
          path
          |> Path.rootname()
          |> Path.split()
          |> Enum.take(-2)
          |> then(fn [dir, name] ->
            Module.concat([
              Brainagram.Application,
              Macro.camelize(dir),
              Macro.camelize(name)
            ])
          end)

        {path, module}
      end)

    assert messages != []

    for {path, module} <- messages do
      Code.ensure_loaded!(module)
      handler = module.handler()

      assert Code.ensure_loaded?(handler), "#{path}: handler #{inspect(handler)} não existe"

      assert function_exported?(handler, :handle, 1),
             "#{path}: #{inspect(handler)} precisa implementar handle/1"
    end
  end
end
