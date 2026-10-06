defmodule Brainagram.Application.Handlers.CreateDiagram do
  @moduledoc """
  Orquestra a criação: pede ao agregado que se construa, entrega ao
  repositório, devolve os eventos.

  Note o que o handler *não* faz: não valida fonte, não deriva título, não
  escolhe slug. Tudo isso é regra e mora no agregado. Handler é encanamento.
  """

  @behaviour Brainagram.Application.CommandHandler

  alias Brainagram.Application.Commands.CreateDiagram
  alias Brainagram.Application.Handlers.Support
  alias Brainagram.Domain.Diagramming.Diagram

  @impl true
  def handle(%CreateDiagram{} = command) do
    with {:ok, project} <- Support.ensure_project(command.project),
         attrs = %{
           source: command.source,
           slug: command.slug,
           visibility: command.visibility,
           project: project
         },
         {:ok, diagram, events} <- Diagram.create(attrs),
         {:ok, saved} <- Support.repository().insert(diagram) do
      {:ok, Diagram.slug_string(saved), events}
    end
  end
end
