defmodule Brainagram.Application.QueryHandlers.ListProjects do
  @moduledoc "Duas leituras e nenhum agregado: projetos com contagem e os totais."

  @behaviour Brainagram.Application.QueryHandler

  alias Brainagram.Application.Ports
  alias Brainagram.Application.Queries.ListProjects

  @impl true
  def handle(%ListProjects{}) do
    counts = Ports.diagram_reader().counts()
    {:ok, %{projects: Ports.project_reader().list(), all: counts.all, none: counts.none}}
  end
end
