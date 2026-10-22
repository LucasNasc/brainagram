defmodule BrainagramWeb.Locale do
  @moduledoc """
  Idioma da interface: português do Brasil (padrão), inglês, chinês
  simplificado, russo, italiano, japonês ou hindi.

  A escolha mora no cookie `bg_locale`, gravado pelo seletor de bandeiras no
  navegador. Sem cookie, vale o primeiro idioma suportado do
  `Accept-Language`; sem nada, português.

    * Como plug, põe o idioma no processo da requisição, na sessão (para o
      LiveView) e em `conn.assigns.locale` (para o `<html lang>`).
    * Como `on_mount`, faz o mesmo no processo do LiveView — o Gettext guarda
      o idioma por processo.
  """

  import Plug.Conn

  @cookie "bg_locale"
  @default "pt_BR"
  # {código Gettext, `<html lang>`, nome no próprio idioma, sigla do seletor}.
  # O nome fica no idioma dele de propósito: é como quem o fala o procura.
  @languages [
    {"pt_BR", "pt-BR", "Português (Brasil)", "PT"},
    {"en", "en", "English", "EN"},
    {"zh", "zh-CN", "简体中文", "ZH"},
    {"ru", "ru", "Русский", "RU"},
    {"it", "it", "Italiano", "IT"},
    {"ja", "ja", "日本語", "JA"},
    {"hi", "hi", "हिन्दी", "HI"}
  ]
  @supported Enum.map(@languages, &elem(&1, 0))

  @type locale :: String.t()

  @doc "Os idiomas oferecidos, na ordem do seletor."
  @spec supported() :: [locale()]
  def supported, do: @supported

  @doc "Os idiomas do seletor: `%{code, lang, name, short}`."
  @spec languages() :: [%{code: locale(), lang: String.t(), name: String.t(), short: String.t()}]
  def languages do
    for {code, lang, name, short} <- @languages,
        do: %{code: code, lang: lang, name: name, short: short}
  end

  @spec cookie() :: String.t()
  def cookie, do: @cookie

  @doc "O valor de `<html lang>` (`pt-BR`, `en`, `zh-CN`…); português se desconhecido."
  @spec html_lang(locale() | nil) :: String.t()
  for {code, lang, _name, _short} <- @languages do
    def html_lang(unquote(code)), do: unquote(lang)
  end

  def html_lang(_), do: "pt-BR"

  # ── plug ──────────────────────────────────────────────────────────────────

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    locale = normalize(conn.cookies[@cookie]) || from_header(conn) || @default
    Gettext.put_locale(BrainagramWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
  end

  # ── LiveView ──────────────────────────────────────────────────────────────

  def on_mount(:default, _params, session, socket) do
    locale = normalize(session["locale"]) || @default
    Gettext.put_locale(BrainagramWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  @doc """
  O idioma de quem não tem sessão (o player embutido em outro site): o que a
  URL pede (`?lang=`), senão o do navegador, senão inglês.
  """
  @spec for_request(Plug.Conn.t(), String.t() | nil) :: locale()
  def for_request(conn, explicit) do
    normalize(explicit) || from_header(conn) || "en"
  end

  # ── privados ──────────────────────────────────────────────────────────────

  @doc false
  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    case value |> String.replace("-", "_") |> String.downcase() do
      "en" <> _ -> "en"
      "pt" <> _ -> "pt_BR"
      "zh" <> _ -> "zh"
      "ru" <> _ -> "ru"
      "it" <> _ -> "it"
      "ja" <> _ -> "ja"
      "hi" <> _ -> "hi"
      _ -> nil
    end
  end

  # `Accept-Language: en-US,en;q=0.9,pt;q=0.8` → o primeiro que a gente fala.
  defp from_header(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first("")
    |> String.split(",")
    |> Enum.map(&(&1 |> String.split(";") |> hd() |> String.trim()))
    |> Enum.find_value(&normalize/1)
  end
end
