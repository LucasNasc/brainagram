defmodule BrainagramWeb.ProxyHeadersTest do
  @moduledoc """
  Atrás do proxy (Coolify), a conexão precisa ter o esquema, a porta e o host
  que o navegador usou; senão a checagem de origem do LiveView recusa tudo.
  """

  use ExUnit.Case, async: true

  import Plug.Test

  alias BrainagramWeb.ProxyHeaders

  # Direto em req_headers: o Plug não deixa um teste definir "host" pela API.
  defp conn(headers) do
    %{conn(:get, "/") | host: "demo.exemplo.com", port: 4000, req_headers: headers}
  end

  test "sem proxy, nada muda" do
    rewritten = ProxyHeaders.rewrite(conn([]))
    assert {rewritten.scheme, rewritten.port} == {:http, 4000}
  end

  test "HTTPS terminado no proxy vira https na 443" do
    rewritten = ProxyHeaders.rewrite(conn([{"x-forwarded-proto", "https"}]))
    assert {rewritten.scheme, rewritten.port} == {:https, 443}
  end

  test "porta fora do padrão vem do Host ou do X-Forwarded-Port" do
    assert ProxyHeaders.rewrite(
             conn([{"x-forwarded-proto", "https"}, {"host", "demo.exemplo.com:8443"}])
           ).port ==
             8443

    assert ProxyHeaders.rewrite(
             conn([{"x-forwarded-proto", "https"}, {"x-forwarded-port", "9443"}])
           ).port ==
             9443
  end

  test "em cadeia de proxies vale o primeiro valor; host encaminhado é aplicado" do
    rewritten =
      ProxyHeaders.rewrite(
        conn([{"x-forwarded-proto", "https, http"}, {"x-forwarded-host", "outro.exemplo.com"}])
      )

    assert {rewritten.scheme, rewritten.host} == {:https, "outro.exemplo.com"}
  end

  test "a origem de outro site continua diferente da conexão" do
    rewritten = ProxyHeaders.rewrite(conn([{"x-forwarded-proto", "https"}]))
    origin = URI.parse("https://site-malicioso.exemplo")

    refute origin.host == rewritten.host
  end
end
