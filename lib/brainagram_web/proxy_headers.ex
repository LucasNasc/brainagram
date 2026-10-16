defmodule BrainagramWeb.ProxyHeaders do
  @moduledoc """
  Aplica os cabeçalhos `X-Forwarded-*` do proxy (Caddy/Traefik do Coolify) à
  conexão: esquema, porta e host que o navegador realmente usou.

  Atrás do proxy o app recebe `http` na porta 4000, mas o navegador abre a
  página em `https` na 443. A checagem de origem do WebSocket do LiveView
  (`check_origin: :conn`) compara esquema, host e porta, então sem isto toda
  conexão era recusada com 403 ("Sem conexão" / "O servidor não respondeu").

  Roda antes de tudo no endpoint, inclusive antes do despacho dos sockets,
  que o Phoenix faz antes dos plugs da aplicação. Confiar nesses cabeçalhos é
  seguro para a checagem de origem: um navegador não deixa uma página de outro
  site definir `X-Forwarded-*`, e o `Origin` dela continua sendo o dela.
  """

  @spec rewrite(Plug.Conn.t()) :: Plug.Conn.t()
  def rewrite(conn) do
    conn
    |> rewrite_proto()
    |> rewrite_port()
    |> rewrite_host()
  end

  defp rewrite_proto(conn) do
    case header(conn, "x-forwarded-proto") do
      proto when proto in ["https", "wss"] ->
        %{conn | scheme: :https, port: host_port(conn) || 443}

      proto when proto in ["http", "ws"] ->
        %{conn | scheme: :http, port: host_port(conn) || 80}

      _none ->
        conn
    end
  end

  # A porta que o navegador usou, quando não é a padrão, vem no Host
  # (`exemplo.com:8443`), e o proxy repassa o Host como chegou.
  defp host_port(conn) do
    with host when is_binary(host) <- header(conn, "host"),
         [_name, port] <- String.split(host, ":", parts: 2),
         {port, ""} <- Integer.parse(port) do
      port
    else
      _ -> nil
    end
  end

  defp rewrite_port(conn) do
    with value when is_binary(value) <- header(conn, "x-forwarded-port"),
         {port, ""} <- Integer.parse(value) do
      %{conn | port: port}
    else
      _ -> conn
    end
  end

  defp rewrite_host(conn) do
    case header(conn, "x-forwarded-host") do
      nil -> conn
      host -> %{conn | host: host |> String.split(":") |> hd()}
    end
  end

  # Com vários proxies em cadeia, vale o primeiro valor (o do navegador).
  defp header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [value | _] -> value |> String.split(",") |> hd() |> String.trim() |> String.downcase()
      [] -> nil
    end
  end
end
