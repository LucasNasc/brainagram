defmodule Brainagram.Application.QueryHandlers.ListPublicDiagrams do
  @moduledoc "Listagem pública, direto do leitor — sem agregado no caminho."

  @behaviour Brainagram.Application.QueryHandler

  alias Brainagram.Application.Ports
  alias Brainagram.Application.Queries.ListPublicDiagrams

  @default_limit 50

  @impl true
  def handle(%ListPublicDiagrams{limit: limit}) do
    {:ok, Ports.diagram_reader().list_public(limit || @default_limit)}
  end
end
