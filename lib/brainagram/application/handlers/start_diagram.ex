defmodule Brainagram.Application.Handlers.StartDiagram do
  @moduledoc """
  Cria um diagrama a partir do modelo inicial do tipo escolhido. O título vai
  para o cabeçalho do fonte, e daí o agregado o deriva como sempre.
  """

  @behaviour Brainagram.Application.CommandHandler

  alias Brainagram.Application.Commands.StartDiagram
  alias Brainagram.Application.Handlers.Support
  alias Brainagram.Domain.Diagramming.{Diagram, Templates}

  @impl true
  def handle(%StartDiagram{} = command) do
    kind = if command.kind == "architecture", do: :architecture, else: :sequence
    lang = Enum.find(Templates.langs(), :pt, &(Atom.to_string(&1) == command.lang))
    source = Templates.starter(kind, command.title, lang)

    with {:ok, project} <- Support.ensure_project(command.project),
         {:ok, diagram, events} <- Diagram.create(%{source: source, project: project}),
         {:ok, saved} <- Support.repository().insert(diagram) do
      {:ok, Diagram.slug_string(saved), events}
    end
  end
end
