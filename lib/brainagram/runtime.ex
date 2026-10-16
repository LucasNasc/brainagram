defmodule Brainagram.Runtime do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # No modo demo não há banco: o cache em memória faz o papel do Repo.
    storage =
      if Application.get_env(:brainagram, :demo_mode, false),
        do: Brainagram.Infrastructure.Cache.Store,
        else: Brainagram.Infrastructure.Persistence.Repo

    children = [
      BrainagramWeb.Telemetry,
      storage,
      {DNSCluster, query: Application.get_env(:brainagram, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Brainagram.PubSub},
      # Start a worker by calling: Brainagram.Worker.start_link(arg)
      # {Brainagram.Worker, arg},
      # Start to serve requests, typically the last entry
      BrainagramWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Brainagram.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BrainagramWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
