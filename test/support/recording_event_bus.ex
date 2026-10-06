defmodule Brainagram.Test.RecordingEventBus do
  @moduledoc """
  Barramento de eventos que entrega na caixa de mensagens do próprio teste.

  Como a publicação é síncrona no processo que despachou o comando,
  `send(self(), ...)` chega no teste. Permite `assert_received {:domain_event,
  %DiagramCreated{}}` sem PubSub, sem espera e sem sleep.
  """

  @behaviour Brainagram.Domain.Diagramming.Ports.EventBus

  @impl true
  def publish(events) when is_list(events) do
    Enum.each(events, &send(self(), {:domain_event, &1}))
    :ok
  end

  @impl true
  def subscribe(_slug), do: :ok

  @impl true
  def unsubscribe(_slug), do: :ok

  @impl true
  def subscribe_all, do: :ok
end
