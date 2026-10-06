defmodule Brainagram.Application.Ports.ProjectReader do
  @moduledoc """
  Porta de leitura dos projetos. Mora na aplicação pelo mesmo motivo da
  `DiagramReader`: devolve read models.
  """

  alias Brainagram.Application.ReadModels.ProjectSummary

  @doc "Todos os projetos, em ordem alfabética, cada um com quantos diagramas tem."
  @callback list() :: [ProjectSummary.t()]

  @callback fetch_by_slug(String.t()) :: {:ok, ProjectSummary.t()} | {:error, :not_found}
end
