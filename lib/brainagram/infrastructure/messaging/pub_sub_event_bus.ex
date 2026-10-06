defmodule Brainagram.Infrastructure.Messaging.PubSubEventBus do
  @moduledoc """
  Implementação da porta de eventos sobre `Phoenix.PubSub`.

  Cada evento vai para dois tópicos: o do diagrama (`diagram:<slug>`) e o global
  (`diagrams`). O primeiro é a fundação da edição colaborativa — quando duas
  pessoas abrirem o mesmo `/d/:slug`, cada uma já é assinante do canal certo. O
  segundo serve listagens e métricas.

  A mensagem entregue é `{:domain_event, %Evento{}}`. A tupla nomeada evita que
  um `handle_info` de LiveView precise adivinhar a origem de um struct solto.
  """

  @behaviour Brainagram.Domain.Diagramming.Ports.EventBus

  alias Brainagram.Domain.Diagramming.Events

  @pubsub Brainagram.PubSub

  @impl true
  def publish(events) when is_list(events) do
    for event <- events, topic <- Events.topics(event) do
      Phoenix.PubSub.broadcast(@pubsub, topic, {:domain_event, event})
    end

    :ok
  end

  @impl true
  def subscribe(slug) when is_binary(slug) do
    Phoenix.PubSub.subscribe(@pubsub, "diagram:" <> slug)
  end

  @impl true
  def subscribe_all, do: Phoenix.PubSub.subscribe(@pubsub, "diagrams")

  @impl true
  def unsubscribe(slug) when is_binary(slug) do
    Phoenix.PubSub.unsubscribe(@pubsub, "diagram:" <> slug)
  end
end
