defmodule Brainagram.Application.Handlers.CreateProject do
  @moduledoc "Cria o projeto pelo agregado e grava. Devolve o slug."

  @behaviour Brainagram.Application.CommandHandler

  alias Brainagram.Application.Commands.CreateProject
  alias Brainagram.Application.Handlers.Support
  alias Brainagram.Domain.Diagramming.Project

  @impl true
  def handle(%CreateProject{} = command) do
    attrs = %{name: command.name, color: command.color, slug: command.slug}

    with {:ok, project, events} <- Project.create(attrs),
         {:ok, saved} <- Support.projects().insert(project) do
      {:ok, Project.slug_string(saved), events}
    end
  end
end
