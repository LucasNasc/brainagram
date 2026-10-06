defmodule BrainagramWeb.HealthCheck do
  @moduledoc """
  `GET /health` → `200 ok`, para o healthcheck do container (Coolify, Docker).

  Fica no endpoint antes do log e da telemetria: a sonda bate a cada poucos
  segundos e não deve encher o log nem abrir sessão. Responde só que a
  aplicação está de pé — a web não fala com o banco diretamente (regra das
  camadas), e o próprio Repo já derruba a aplicação se o banco sumir.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: method, request_path: "/health"} = conn, _opts)
      when method in ["GET", "HEAD"] do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "ok")
    |> halt()
  end

  def call(conn, _opts), do: conn
end
