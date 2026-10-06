defmodule Brainagram.Application.Handlers.ImportDiagrams do
  @moduledoc """
  Importa cada arquivo pelo trilho de sempre: o fonte passa pelo agregado
  (`Diagram.create/1` — só entra se compilar), o projeto pelo dele.

  Devolve `%{created: [%{slug, title}], projects: [nome], failed: [%{name,
  reason}]}` e os eventos de tudo o que entrou.
  """

  @behaviour Brainagram.Application.CommandHandler

  alias Brainagram.Application.{Bundle, Ports}
  alias Brainagram.Application.Commands.ImportDiagrams
  alias Brainagram.Application.Handlers.Support
  alias Brainagram.Domain.Diagramming.{Authoring, Diagram, Import, Project}
  alias Brainagram.Domain.Diagramming.Dsl.Parser

  @empty %{created: [], projects: [], failed: []}

  @impl true
  def handle(%ImportDiagrams{files: files, project: target}) do
    with {:ok, target} <- Support.ensure_project(target) do
      {report, events} =
        Enum.reduce(files, {@empty, []}, fn file, acc -> import_file(file, target, acc) end)

      report = Map.new(report, fn {k, v} -> {k, Enum.reverse(v)} end)
      {:ok, report, events}
    end
  end

  defp import_file(file, target, {report, events}) do
    name = to_string(file["name"] || file[:name] || "")
    content = file["content"] || file[:content]

    cond do
      not is_binary(content) or not String.valid?(content) ->
        {fail(report, name, :not_text), events}

      Bundle.bundle?(content) ->
        {:ok, bundle} = Bundle.decode(content)
        import_bundle(bundle, name, target, {report, events})

      true ->
        case Import.convert(content, format_of(name)) do
          {:ok, %{source: source}} ->
            create(titled(source, name), target, nil, name, {report, events})

          {:error, reason} ->
            {fail(report, name, reason), events}
        end
    end
  end

  # Os projetos do pacote viram projetos daqui (o de mesmo nome é reaproveitado);
  # diagrama sem projeto no pacote vai para o projeto escolhido na tela.
  defp import_bundle(bundle, name, target, acc) do
    existing = Map.new(Ports.project_reader().list(), &{normalize(&1.name), &1.slug})

    {keys, acc} =
      Enum.reduce(bundle.projects, {%{}, acc}, fn project, {keys, {report, events}} ->
        case Map.fetch(existing, normalize(project.name)) do
          {:ok, slug} ->
            {Map.put(keys, project.key, slug), {report, events}}

          :error ->
            case create_project(project) do
              {:ok, slug, new_events} ->
                report = Map.update!(report, :projects, &[project.name | &1])
                {Map.put(keys, project.key, slug), {report, events ++ new_events}}

              {:error, reason} ->
                {keys, {fail(report, "#{name} · #{project.name}", reason), events}}
            end
        end
      end)

    Enum.reduce(bundle.diagrams, acc, fn diagram, acc ->
      project = if diagram.project, do: Map.get(keys, diagram.project, target), else: target
      label = "#{name} · #{diagram.title || "?"}"
      create(diagram.source, project, diagram.visibility, label, acc)
    end)
  end

  defp create_project(%{name: name, color: color}) do
    with {:ok, project, events} <- Project.create(%{name: name, color: color || nil}),
         {:ok, saved} <- Support.projects().insert(project) do
      {:ok, Project.slug_string(saved), events}
    else
      # cor que esta versão não conhece: entra com a padrão
      {:error, :invalid_project_color} -> create_project(%{name: name, color: nil})
      {:error, reason} -> {:error, reason}
    end
  end

  defp create(source, project, visibility, label, {report, events}) do
    attrs = %{source: source, project: project, visibility: visibility}

    with {:ok, diagram, new_events} <- Diagram.create(attrs),
         {:ok, saved} <- Support.repository().insert(diagram) do
      item = %{slug: Diagram.slug_string(saved), title: Diagram.title_string(saved)}
      {Map.update!(report, :created, &[item | &1]), events ++ new_events}
    else
      {:error, reason} -> {fail(report, label, reason), events}
    end
  end

  # Arquivo sem título no cabeçalho: o nome do arquivo vira o título.
  defp titled(source, filename) do
    with {:ok, %{title: nil}} <- Parser.parse(source),
         title when title != "" <- filename |> Path.rootname() |> String.trim(),
         {:ok, renamed} <- Authoring.rename_title(source, title) do
      renamed
    else
      _ -> source
    end
  end

  # A extensão, quando diz o formato, vale mais que adivinhar: um `.brain` com
  # erro de sintaxe deve dizer a linha do erro, não "formato desconhecido".
  defp format_of(name) do
    case name |> Path.extname() |> String.downcase() do
      ".brain" -> :brainagram
      ext when ext in [".mmd", ".mermaid"] -> :mermaid
      ext when ext in [".puml", ".plantuml"] -> :plantuml
      _ -> :auto
    end
  end

  defp fail(report, name, reason),
    do: Map.update!(report, :failed, &[%{name: name, reason: reason} | &1])

  defp normalize(name), do: name |> String.trim() |> String.downcase()
end
