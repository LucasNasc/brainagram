defmodule BrainagramWeb.EmbedHeaders do
  @moduledoc """
  Cabeçalhos da página embutível (`/embed/:slug`).

  O resto do app manda `frame-ancestors 'self'` (o padrão do Phoenix), então
  nenhum outro site consegue exibi-lo num iframe. Só esta rota libera, porque
  não tem ação nenhuma para um clickjacking aproveitar: é um player só de
  leitura, sem sessão e sem cookie.

  A política de conteúdo é estreita: script, estilo e fonte só da própria
  instância, nada de conexões de rede, nenhum formulário. Os dados do diagrama
  vão num bloco `application/json`, que o navegador não executa.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn
    |> put_resp_header("content-security-policy", policy())
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
    |> put_resp_header("x-content-type-options", "nosniff")
  end

  @doc "Quem pode embutir: a lista de BRAINAGRAM_EMBED_ORIGINS, ou qualquer site."
  @spec frame_ancestors() :: String.t()
  def frame_ancestors do
    case Application.get_env(:brainagram, :embed, [])[:origins] do
      list when is_list(list) and list != [] -> Enum.join(list, " ")
      _any -> "*"
    end
  end

  defp policy do
    Enum.join(
      [
        "default-src 'none'",
        "script-src 'self'",
        # o renderizador posiciona elementos com `style` inline
        "style-src 'self' 'unsafe-inline'",
        "font-src 'self'",
        "img-src 'self' data:",
        "connect-src 'none'",
        "frame-ancestors #{frame_ancestors()}",
        "base-uri 'none'",
        "form-action 'none'"
      ],
      "; "
    )
  end
end
