defmodule Brainagram.Application.Handlers.DeleteDiagram do
  @moduledoc """
  Remove um diagrama.

  Os eventos são montados **antes** do delete: depois de apagado, o agregado
  não existe mais para contar o que aconteceu com ele.
  """

  @behaviour Brainagram.Application.CommandHandler

  alias Brainagram.Application.Commands.DeleteDiagram
  alias Brainagram.Application.Handlers.Support
  alias Brainagram.Domain.Diagramming.Diagram

  @impl true
  def handle(%DeleteDiagram{} = command) do
    with {:ok, diagram} <- Support.load(command.slug) do
      events = Diagram.deletion_events(diagram)

      case Support.repository().delete(diagram) do
        :ok -> {:ok, Diagram.slug_string(diagram), events}
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
