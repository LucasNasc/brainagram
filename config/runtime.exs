import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/brainagram start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :brainagram, BrainagramWeb.Endpoint, server: true
end

# Modo demo (playground público): BRAINAGRAM_DEMO=true troca o banco por um
# cache em memória (Brainagram.Infrastructure.Cache.Store) e mostra um aviso de
# playground em todas as telas. Os diagramas valem para todos os visitantes e
# somem com o tempo e a cada reinício. Para uso de verdade, deixe desligado.
demo? =
  System.get_env("BRAINAGRAM_DEMO", "false") |> String.downcase() |> then(&(&1 in ~w(true 1 yes)))

if demo? do
  config :brainagram, demo_mode: true

  config :brainagram, :ports,
    diagram_repository: Brainagram.Infrastructure.Cache.CacheDiagramRepository,
    diagram_reader: Brainagram.Infrastructure.Cache.CacheDiagramReader,
    project_repository: Brainagram.Infrastructure.Cache.CacheProjectRepository,
    project_reader: Brainagram.Infrastructure.Cache.CacheProjectReader
end

# Diagramas embutidos em outros sites por <iframe> (/embed/:slug). Só os
# públicos aparecem. BRAINAGRAM_EMBED=false desliga para a instância inteira;
# BRAINAGRAM_EMBED_ORIGINS restringe quais sites podem embutir (separados por
# vírgula; sem ela, qualquer site).
config :brainagram, :embed,
  enabled:
    System.get_env("BRAINAGRAM_EMBED", "true")
    |> String.downcase()
    |> then(&(&1 not in ~w(false 0 no off))),
  origins:
    System.get_env("BRAINAGRAM_EMBED_ORIGINS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

if config_env() == :prod and not demo? do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # TLS com o banco (a maioria dos serviços gerenciados exige):
  #   DATABASE_SSL=false   (padrão) sem TLS — banco na mesma rede/container
  #   DATABASE_SSL=true    criptografa, sem conferir o certificado do servidor
  #   DATABASE_SSL=verify  criptografa e confere o certificado (CAs do sistema;
  #                        ou o arquivo de DATABASE_SSL_CA_FILE, para CA própria)
  database_ssl =
    case System.get_env("DATABASE_SSL", "false") |> String.downcase() do
      value when value in ~w(false 0 off no) ->
        []

      value when value in ~w(true 1 on yes require) ->
        [ssl: [verify: :verify_none]]

      "verify" ->
        ca = System.get_env("DATABASE_SSL_CA_FILE")

        [
          ssl:
            [
              verify: :verify_peer,
              server_name_indication: URI.parse(database_url).host |> to_charlist()
            ] ++
              if(ca, do: [cacertfile: ca], else: [cacerts: :public_key.cacerts_get()])
        ]

      other ->
        raise "DATABASE_SSL must be false, true or verify (got #{inspect(other)})"
    end

  config :brainagram,
         Brainagram.Infrastructure.Persistence.Repo,
         [
           url: database_url,
           pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
           socket_options: maybe_ipv6
         ] ++ database_ssl
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Uma chave curta só estouraria na primeira requisição com sessão (erro 500
  # em toda página); melhor o container nem subir, com a causa no log.
  if byte_size(secret_key_base) < 64 do
    raise """
    environment variable SECRET_KEY_BASE is too short (#{byte_size(secret_key_base)} bytes, needs at least 64).
    Generate one with: mix phx.gen.secret  (or: openssl rand -base64 48)
    """
  end

  host = System.get_env("PHX_HOST") || "example.com"

  # Origens aceitas no WebSocket do LiveView. Sem PHX_CHECK_ORIGIN, vale o host
  # da própria requisição (:conn): funciona atrás do proxy em qualquer domínio
  # (inclusive o gerado pelo Coolify) sem aceitar páginas de outros sites. Um
  # PHX_HOST diferente do domínio acessado não derruba mais a conexão. Para
  # fixar: PHX_CHECK_ORIGIN=https://demo.exemplo.com,https://outro.exemplo.com
  check_origin =
    case System.get_env("PHX_CHECK_ORIGIN", "") |> String.trim() do
      "" -> :conn
      list -> list |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    end

  port = String.to_integer(System.get_env("PORT") || "4000")

  config :brainagram, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :brainagram, BrainagramWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: check_origin,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :brainagram, BrainagramWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :brainagram, BrainagramWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
