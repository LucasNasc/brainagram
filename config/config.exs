# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :brainagram,
  ecto_repos: [Brainagram.Infrastructure.Persistence.Repo],
  generators: [timestamp_type: :utc_datetime]

# Ligação entre as portas (declaradas no domínio e na aplicação) e as
# implementações concretas. É o único lugar onde as camadas de cima passam a
# saber que existe Postgres e PubSub do outro lado — em qualquer outro arquivo,
# um `alias` para dentro de `Infrastructure` seria violação da regra de
# dependência. Testes trocam estes valores para rodar sem banco.
config :brainagram, :ports,
  diagram_repository: Brainagram.Infrastructure.Persistence.EctoDiagramRepository,
  diagram_reader: Brainagram.Infrastructure.Persistence.EctoDiagramReader,
  project_repository: Brainagram.Infrastructure.Persistence.EctoProjectRepository,
  project_reader: Brainagram.Infrastructure.Persistence.EctoProjectReader,
  event_bus: Brainagram.Infrastructure.Messaging.PubSubEventBus,
  example_catalog: Brainagram.Infrastructure.Catalog.StaticExampleCatalog

# Configures the endpoint
config :brainagram, BrainagramWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BrainagramWeb.ErrorHTML, json: BrainagramWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Brainagram.PubSub,
  live_view: [signing_salt: "brZX142a"]

# Configure esbuild (the version is required). Empacota o JS e o CSS: o
# CSS é puro (sem framework), e o esbuild só resolve os @import de
# assets/css/app.css. Saída: priv/static/assets/{js,css}/app.{js,css}.
config :esbuild,
  version: "0.25.4",
  brainagram: [
    args:
      ~w(js/app.js css/app.css --bundle --target=es2022 --outbase=. --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Tipos dos arquivos que a importação aceita (o upload do LiveView só aceita
# extensões com tipo MIME conhecido). Mudou aqui: `mix deps.compile mime --force`.
config :mime, :types, %{
  "text/x-brainagram" => ["brain"],
  "text/x-mermaid" => ["mmd", "mermaid"],
  "text/x-plantuml" => ["puml", "plantuml"]
}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
