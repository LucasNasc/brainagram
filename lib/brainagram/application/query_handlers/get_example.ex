defmodule Brainagram.Application.QueryHandlers.GetExample do
  @moduledoc "Um exemplo pelo slug."

  @behaviour Brainagram.Application.QueryHandler

  alias Brainagram.Application.Ports
  alias Brainagram.Application.Queries.GetExample

  @impl true
  def handle(%GetExample{slug: slug}), do: Ports.example_catalog().fetch(slug)
end
