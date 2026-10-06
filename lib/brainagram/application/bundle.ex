defmodule Brainagram.Application.Bundle do
  @moduledoc """
  O pacote de exportação: vários diagramas, com os projetos deles, num JSON.

      {
        "format": "brainagram",
        "version": 1,
        "exported_at": "2026-09-29T12:00:00Z",
        "projects": [{"key": "abc123", "name": "Pagamentos", "color": "teal"}],
        "diagrams": [
          {"title": "Checkout", "project": "abc123", "visibility": "private",
           "source": "diagram sequence \\"Checkout\\"\\n…"}
        ]
      }

  O diagrama vai como o **fonte** (a DSL), que é a fonte da verdade: título,
  tipo, layout fixado e payloads estão todos ali. `project` aponta para a
  `key` de um projeto do próprio pacote — slugs do banco de origem não
  significam nada no de destino, então nenhum é reaproveitado ao importar.

  Um diagrama sozinho sai como `.brain` (só o fonte), não como pacote.
  """

  alias Brainagram.Shared.Text

  @format "brainagram"
  @version 1

  @type project :: %{key: String.t(), name: String.t(), color: String.t()}
  @type diagram :: %{
          title: String.t(),
          source: String.t(),
          visibility: String.t() | nil,
          project: String.t() | nil
        }
  @type t :: %{projects: [project()], diagrams: [diagram()]}

  @doc "Monta o JSON a partir das linhas de `DiagramReader.list_sources/1`."
  @spec encode([map()], DateTime.t()) :: String.t()
  def encode(rows, %DateTime{} = exported_at) do
    projects =
      rows
      |> Enum.filter(& &1.project)
      |> Enum.uniq_by(& &1.project)
      |> Enum.map(&%{key: &1.project, name: &1.project_name, color: &1.project_color})

    diagrams =
      Enum.map(rows, fn row ->
        %{title: row.title, project: row.project, visibility: row.visibility, source: row.source}
      end)

    Jason.encode!(
      %{
        format: @format,
        version: @version,
        exported_at: DateTime.to_iso8601(exported_at),
        projects: projects,
        diagrams: diagrams
      },
      pretty: true
    )
  end

  @doc "Lê um pacote. Qualquer coisa fora do formato é `:invalid_bundle`."
  @spec decode(String.t()) :: {:ok, t()} | {:error, :invalid_bundle}
  def decode(json) when is_binary(json) do
    with {:ok, %{"format" => @format, "diagrams" => diagrams} = data} when is_list(diagrams) <-
           Jason.decode(json),
         {:ok, projects} <- projects(Map.get(data, "projects", [])),
         {:ok, diagrams} <- diagrams(diagrams) do
      {:ok, %{projects: projects, diagrams: diagrams}}
    else
      _ -> {:error, :invalid_bundle}
    end
  end

  @doc "É um pacote nosso? (Olha o conteúdo, não a extensão.)"
  @spec bundle?(String.t()) :: boolean()
  def bundle?(text) when is_binary(text) do
    String.starts_with?(String.trim_leading(text), "{") and match?({:ok, _}, decode(text))
  end

  @doc "`brainagram-pagamentos-2026-09-29.json`"
  @spec filename(String.t(), DateTime.t()) :: String.t()
  def filename(scope, %DateTime{} = at) do
    "brainagram-#{Text.slugify(scope)}-#{Date.to_iso8601(DateTime.to_date(at))}.json"
  end

  defp projects(list) when is_list(list) do
    list
    |> Enum.reduce_while([], fn
      %{"key" => key, "name" => name} = p, acc when is_binary(key) and is_binary(name) ->
        {:cont, [%{key: key, name: name, color: p["color"]} | acc]}

      _, _ ->
        {:halt, :error}
    end)
    |> case do
      :error -> :error
      acc -> {:ok, Enum.reverse(acc)}
    end
  end

  defp projects(_), do: :error

  defp diagrams(list) do
    list
    |> Enum.reduce_while([], fn
      %{"source" => source} = d, acc when is_binary(source) ->
        {:cont,
         [
           %{
             title: d["title"],
             source: source,
             visibility: d["visibility"],
             project: d["project"]
           }
           | acc
         ]}

      _, _ ->
        {:halt, :error}
    end)
    |> case do
      :error -> :error
      acc -> {:ok, Enum.reverse(acc)}
    end
  end
end
