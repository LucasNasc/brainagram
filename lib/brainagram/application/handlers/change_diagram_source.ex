defmodule Brainagram.Application.Handlers.ChangeDiagramSource do
  @moduledoc "Carrega o agregado, pede a transição, grava se algo mudou."

  @behaviour Brainagram.Application.CommandHandler

  alias Brainagram.Application.Commands.ChangeDiagramSource
  alias Brainagram.Application.Handlers.Support
  alias Brainagram.Domain.Diagramming.Diagram

  @impl true
  def handle(%ChangeDiagramSource{} = command) do
    with {:ok, diagram} <- Support.load(command.slug),
         {:ok, updated, events} <- Diagram.change_source(diagram, command.source) do
      Support.persist_if_changed(diagram, updated, events)
    end
  end
end
