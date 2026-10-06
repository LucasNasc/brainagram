defmodule Brainagram.Application.Handlers.UpdateProject do
  @moduledoc "Renomeia/recolore. Nada diferente do atual não grava nem publica."

  @behaviour Brainagram.Application.CommandHandler

  alias Brainagram.Application.Commands.UpdateProject
  alias Brainagram.Application.Handlers.Support
  alias Brainagram.Domain.Diagramming.Project

  @impl true
  def handle(%UpdateProject{} = command) do
    with {:ok, project} <- Support.load_project(command.slug),
         {:ok, updated, events} <-
           Project.update(project, %{name: command.name, color: command.color}) do
      persist(project, updated, events)
    end
  end

  defp persist(project, _updated, []), do: {:ok, Project.slug_string(project), []}

  defp persist(_project, updated, events) do
    with {:ok, saved} <- Support.projects().update(updated) do
      {:ok, Project.slug_string(saved), events}
    end
  end
end
