defmodule Brainagram.Application.Handlers.ChangeDiagramVisibility do
  @moduledoc "Publica ou despublica um diagrama."

  @behaviour Brainagram.Application.CommandHandler

  alias Brainagram.Application.Commands.ChangeDiagramVisibility
  alias Brainagram.Application.Handlers.Support
  alias Brainagram.Domain.Diagramming.Diagram

  @impl true
  def handle(%ChangeDiagramVisibility{} = command) do
    with {:ok, diagram} <- Support.load(command.slug),
         {:ok, updated, events} <- Diagram.change_visibility(diagram, command.visibility) do
      Support.persist_if_changed(diagram, updated, events)
    end
  end
end
