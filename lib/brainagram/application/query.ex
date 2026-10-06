defmodule Brainagram.Application.Query do
  @moduledoc """
  Uma query: intenção de **ler** estado.

  Queries não tocam no agregado e não emitem eventos. Elas leem pela
  `Ports.DiagramReader` e devolvem read models — structs moldados para quem vai
  exibir, não para quem vai aplicar regra de negócio.
  """

  defmacro __using__(opts) do
    quote do
      use Brainagram.Application.Message, unquote(opts)
    end
  end
end

defmodule Brainagram.Application.QueryHandler do
  @moduledoc """
  Contrato dos handlers de query.

  Sem eventos no retorno — leitura não muda nada, e o tipo de retorno é o lugar
  certo para essa garantia morar.
  """

  @callback handle(struct()) :: {:ok, term()} | {:error, term()}
end
