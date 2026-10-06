defmodule Brainagram.Application.Handlers.MoveDiagram do
  @moduledoc """
  Muda o diagrama de projeto. O handler confere que o projeto de destino
  existe — o agregado só conhece a referência, não o outro agregado.
  """

  @behaviour Brainagram.Application.CommandHandler

  alias Brainagram.Application.Commands.MoveDiagram
  alias Brainagram.Application.Handlers.Support
  alias Brainagram.Domain.Diagramming.Diagram

  @impl true
  def handle(%MoveDiagram{} = command) do
    with {:ok, diagram} <- Support.load(command.slug),
         {:ok, project} <- Support.ensure_project(command.project),
         {:ok, updated, events} <- Diagram.move_to_project(diagram, project) do
      Support.persist_if_changed(diagram, updated, events)
    end
  end
end
