defmodule Brainagram.Application.Handlers.DeleteProject do
  @moduledoc """
  Exclui um projeto sem apagar nenhum diagrama.

  A ordem importa: primeiro os diagramas saem do projeto, depois o projeto é
  removido. Ao contrário, haveria um instante com diagramas apontando para um
  projeto que não existe mais. Cada diagrama que saiu vira um `DiagramMoved`,
  para quem estiver com ele aberto saber que mudou de lugar.
  """

  @behaviour Brainagram.Application.CommandHandler

  alias Brainagram.Application.Commands.DeleteProject
  alias Brainagram.Application.Handlers.Support
  alias Brainagram.Domain.Diagramming.{Events, Project}

  @impl true
  def handle(%DeleteProject{} = command) do
    with {:ok, project} <- Support.load_project(command.slug),
         {:ok, detached} <- Support.repository().detach_project(project.slug),
         :ok <- Support.projects().delete(project) do
      moved = Enum.map(detached, &Events.detached(&1, project.slug))
      {:ok, Project.slug_string(project), moved ++ Project.deletion_events(project)}
    end
  end
end
