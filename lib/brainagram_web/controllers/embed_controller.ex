defmodule BrainagramWeb.EmbedController do
  @moduledoc """
  O player embutível: `/embed/:slug`, para colocar um diagrama numa página de
  outro site com `<iframe>`.

  Não é um LiveView. A cena é calculada aqui, uma vez, e vai junto com a página;
  o `embed.js` desenha e toca no navegador com o mesmo renderizador e a mesma
  linha do tempo do app. Assim funciona em qualquer iframe (sem cookie, sem
  WebSocket), pode ficar em cache e não pesa no servidor depois do primeiro
  acesso.

  Só diagramas públicos. Privado, inexistente ou com o embed desligado na
  instância: a mesma resposta 404 neutra, para não revelar que um diagrama
  privado existe.
  """

  use BrainagramWeb, :controller

  alias Brainagram.Application.Bus
  alias Brainagram.Application.Queries.GetDiagramBySlug
  alias BrainagramWeb.{EmbedHTML, Locale}

  @themes ~w(auto light dark)
  @controls ~w(full minimal none)

  def show(conn, %{"slug" => slug} = params) do
    locale = Locale.for_request(conn, params["lang"])
    Gettext.put_locale(BrainagramWeb.Gettext, locale)

    conn =
      conn
      |> put_view(html: EmbedHTML)
      |> put_root_layout(false)
      |> put_layout(false)
      |> assign(:html_lang, Locale.html_lang(locale))

    case public_diagram(slug) do
      {:ok, detail} -> player(conn, detail, options(params), locale)
      :unavailable -> unavailable(conn)
    end
  end

  defp public_diagram(slug) do
    with true <- enabled?(),
         {:ok, %{visibility: "public", scene: scene} = detail} when not is_nil(scene) <-
           Bus.ask(GetDiagramBySlug, %{slug: slug}) do
      {:ok, detail}
    else
      _ -> :unavailable
    end
  end

  defp player(conn, detail, opts, locale) do
    etag = etag(detail, opts, locale)

    conn =
      conn
      |> put_resp_header("etag", etag)
      |> put_resp_header("cache-control", "public, max-age=60, stale-while-revalidate=600")

    if etag in get_req_header(conn, "if-none-match") do
      send_resp(conn, 304, "")
    else
      render(conn, :show,
        detail: detail,
        scene_json: Jason.encode!(detail.scene, escape: :html_safe),
        opts: opts,
        presentation_url: url(conn, ~p"/d/#{detail.slug}")
      )
    end
  end

  defp unavailable(conn) do
    conn
    |> put_status(:not_found)
    |> put_resp_header("cache-control", "public, max-age=60")
    |> render(:unavailable)
  end

  defp enabled?, do: Keyword.get(Application.get_env(:brainagram, :embed, []), :enabled, true)

  # Opções da URL. Valor desconhecido volta ao padrão; nada da URL é repetido na
  # página sem passar por aqui.
  defp options(params) do
    %{
      theme: pick(params["theme"], @themes, "auto"),
      controls: pick(params["controls"], @controls, "full"),
      autoplay: params["autoplay"] in ["1", "true"],
      loop: params["loop"] in ["1", "true"],
      step: step(params["step"])
    }
  end

  defp pick(value, allowed, default), do: if(value in allowed, do: value, else: default)

  defp step(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 1 and n <= 500 -> n
      _ -> 1
    end
  end

  defp step(_value), do: 1

  # Muda quando o diagrama muda, quando as opções mudam ou o idioma muda.
  defp etag(detail, opts, locale) do
    key = :erlang.term_to_binary({detail.slug, detail.updated_at, opts, locale})
    ~s(W/") <> Base.url_encode64(:crypto.hash(:sha256, key), padding: false) <> ~s(")
  end
end
