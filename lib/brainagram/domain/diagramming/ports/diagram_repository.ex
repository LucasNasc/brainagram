defmodule Brainagram.Domain.Diagramming.Ports.DiagramRepository do
  @moduledoc """
  Porta de escrita: como o agregado entra e sai da persistência.

  Fica no domínio porque é o domínio quem declara o que precisa; a
  infraestrutura é que se adapta (inversão de dependência). O contrato fala em
  `%Diagram{}` e `%Slug{}` — nunca em changeset, query ou schema.

  Deliberadamente não há `list/1` aqui. Listagem é leitura, e leitura não passa
  pelo agregado: vai pela `Application.Ports.DiagramReader`. É essa separação
  que o CQRS compra.
  """

  alias Brainagram.Domain.Diagramming.Diagram
  alias Brainagram.Domain.Diagramming.ValueObjects.Slug

  @callback insert(Diagram.t()) :: {:ok, Diagram.t()} | {:error, term()}
  @callback update(Diagram.t()) :: {:ok, Diagram.t()} | {:error, term()}
  @callback delete(Diagram.t()) :: :ok | {:error, term()}
  @callback fetch_by_slug(Slug.t()) :: {:ok, Diagram.t()} | {:error, :not_found}

  @doc """
  Tira do projeto todos os diagramas dele — a regra de "excluir um projeto
  não apaga os diagramas". Uma operação só, e não um `update/1` por
  diagrama, porque um projeto pode ter centenas deles. Devolve os slugs
  movidos, para o handler contar a história em eventos.
  """
  @callback detach_project(Slug.t()) :: {:ok, [String.t()]}
end
