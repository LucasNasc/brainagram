defmodule Brainagram.Application.Handlers.ForkDiagram do
  @moduledoc "Duplica um diagrama existente sob um slug novo."

  @behaviour Brainagram.Application.CommandHandler

  alias Brainagram.Application.Commands.ForkDiagram
  alias Brainagram.Application.Handlers.Support
  alias Brainagram.Domain.Diagramming.Diagram

  @impl true
  def handle(%ForkDiagram{} = command) do
    with {:ok, origin} <- Support.load(command.slug),
         {:ok, copy, events} <- Diagram.fork(origin),
         {:ok, saved} <- Support.repository().insert(copy) do
      {:ok, Diagram.slug_string(saved), events}
    end
  end
end
