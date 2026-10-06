defmodule Brainagram.Application.Ports.ExampleCatalog do
  @moduledoc """
  Porta do catálogo de exemplos do editor.

  Hoje a implementação é estática, em módulo. Vira porta mesmo assim porque o
  destino provável é outro: exemplos curados vindos do banco, ou os diagramas
  públicos mais copiados. Quando isso acontecer, nada acima muda.
  """

  alias Brainagram.Application.ReadModels.Example

  @callback all() :: [Example.t()]
  @callback fetch(slug :: String.t()) :: {:ok, Example.t()} | {:error, :not_found}
  @callback default_source() :: String.t()
end
