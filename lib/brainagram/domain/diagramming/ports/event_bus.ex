defmodule Brainagram.Domain.Diagramming.Ports.EventBus do
  @moduledoc """
  Porta de saída para eventos de domínio — publicação e assinatura.

  O domínio produz eventos; entregar é detalhe. Hoje a implementação é
  `Phoenix.PubSub`; amanhã pode ser Oban, Broadway ou um broker externo — sem
  tocar em nada dentro de `domain/`.

  A assinatura mora aqui junto com a publicação porque quem escuta precisa da
  mesma noção de tópico que quem emite. Separar em duas portas só faria as duas
  terem que concordar sobre o formato do tópico por fora do contrato.
  """

  alias Brainagram.Domain.Diagramming.Events

  @callback publish([Events.t()]) :: :ok
  @callback subscribe(slug :: String.t()) :: :ok | {:error, term()}
  @callback unsubscribe(slug :: String.t()) :: :ok

  @doc "Assina todos os eventos (o tópico global) — para listagens que se atualizam sozinhas."
  @callback subscribe_all() :: :ok | {:error, term()}
end
