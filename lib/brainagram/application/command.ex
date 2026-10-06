defmodule Brainagram.Application.Command do
  @moduledoc """
  Um comando: intenção de **mudar** estado.

  Comandos podem falhar por regra de negócio, sempre passam pelo agregado e
  sempre produzem eventos. Nomeiam-se no imperativo (`CreateDiagram`), nunca
  como um CRUD genérico.
  """

  defmacro __using__(opts) do
    quote do
      use Brainagram.Application.Message, unquote(opts)
    end
  end
end

defmodule Brainagram.Application.CommandHandler do
  @moduledoc """
  Contrato dos handlers de comando.

  A tripla de retorno `{:ok, resultado, eventos}` é o ponto do desenho: o
  handler nunca publica evento por conta própria. Ele **devolve** o que
  aconteceu e o barramento publica depois da transação — assim um evento nunca
  vaza para o mundo por causa de uma escrita que acabou falhando.
  """

  @callback handle(struct()) :: {:ok, term(), [struct()]} | {:error, term()}
end
