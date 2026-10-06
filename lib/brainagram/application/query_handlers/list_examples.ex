defmodule Brainagram.Application.QueryHandlers.ListExamples do
  @moduledoc "Exemplos oferecidos no editor."

  @behaviour Brainagram.Application.QueryHandler

  alias Brainagram.Application.Ports
  alias Brainagram.Application.Queries.ListExamples

  @impl true
  def handle(%ListExamples{}), do: {:ok, Ports.example_catalog().all()}
end
