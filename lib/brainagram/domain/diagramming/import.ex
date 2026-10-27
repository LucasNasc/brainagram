defmodule Brainagram.Domain.Diagramming.Import do
  @moduledoc """
  Importação de diagramas de outras ferramentas para a DSL.

  Quem já escreve Mermaid ou PlantUML há anos só troca de ferramenta se o custo
  de migrar for perto de zero (spec 001, §1). Então: colar o texto, receber a
  DSL canônica — e, no topo dela, um comentário explicando o que não converteu.
  """

  alias Brainagram.Domain.Diagramming.Dsl.Parser
  alias Brainagram.Domain.Diagramming.Import.{Mermaid, PlantUml}

  @type format :: :mermaid | :plantuml | :brainagram
  @type result ::
          {:ok, %{source: String.t(), warnings: list(), format: format()}} | {:error, term()}

  @doc "Converte `text`. Com `:auto`, o formato é detectado pelo conteúdo."
  @spec convert(String.t(), format() | :auto) :: result()
  def convert(text, format \\ :auto)

  def convert(text, :auto), do: convert(text, detect(text))
  def convert(_text, nil), do: {:error, :unsupported_format}

  # Um `.brain` exportado daqui já é a DSL: entra como está (se compilar).
  def convert(text, :brainagram) do
    case Parser.parse(text) do
      {:ok, _ast} -> {:ok, %{source: text, warnings: [], format: :brainagram}}
      {:error, errors} -> {:error, {:syntax, errors}}
    end
  end

  def convert(text, format) when format in [:mermaid, :plantuml] do
    module = if format == :mermaid, do: Mermaid, else: PlantUml

    with {:ok, result} <- module.convert(text) do
      {:ok, Map.put(result, :format, format)}
    end
  end

  def convert(_text, _format), do: {:error, :unsupported_format}

  @doc """
  Adivinha o dialeto: `@startuml` é PlantUML; `sequenceDiagram`, `flowchart`
  e `graph` são Mermaid;
  texto que compila como a nossa DSL é Brainagram (um `.brain` exportado
  daqui). A DSL vem depois dos cabeçalhos explícitos porque `A ->> B` é válido
  nas duas línguas.
  """
  @spec detect(String.t()) :: format() | nil
  def detect(text) do
    cond do
      text =~ ~r/@startuml/i -> :plantuml
      text =~ ~r/^\s*sequenceDiagram\b/im -> :mermaid
      first_statement(text) =~ ~r/^(?:flowchart(?:-elk)?|graph)\b/i -> :mermaid
      String.trim(text) != "" and match?({:ok, _}, Parser.parse(text)) -> :brainagram
      text =~ ~r/^\s*(participant|actor)\s+.+\s+as\s+"/im -> :plantuml
      text =~ ~r/->>|-->>/ -> :mermaid
      text =~ ~r/^\s*[\w"]+\s*-+>\s*[\w"]+\s*:/m -> :plantuml
      true -> nil
    end
  end

  # A primeira linha que não é front matter (`---`…`---`), comentário `%%` ou
  # vazia: é onde o Mermaid diz o tipo do diagrama.
  defp first_statement(text) do
    lines = text |> String.split(~r/\r\n|\r|\n/) |> Enum.map(&String.trim/1)

    lines =
      case lines do
        ["---" | rest] -> rest |> Enum.drop_while(&(&1 != "---")) |> Enum.drop(1)
        lines -> lines
      end

    Enum.find(lines, "", &(&1 != "" and not String.starts_with?(&1, "%%")))
  end
end
