defmodule Brainagram.Domain.Diagramming.Ports.ProjectRepository do
  @moduledoc """
  Porta de escrita dos projetos. Mesmo desenho da `DiagramRepository`: fala
  em `%Project{}` e `%Slug{}`, nunca em changeset; listagem é leitura e vai
  pela `Application.Ports.ProjectReader`.
  """

  alias Brainagram.Domain.Diagramming.Project
  alias Brainagram.Domain.Diagramming.ValueObjects.Slug

  @callback insert(Project.t()) :: {:ok, Project.t()} | {:error, term()}
  @callback update(Project.t()) :: {:ok, Project.t()} | {:error, term()}
  @callback delete(Project.t()) :: :ok | {:error, term()}
  @callback fetch_by_slug(Slug.t()) :: {:ok, Project.t()} | {:error, :not_found}
end
