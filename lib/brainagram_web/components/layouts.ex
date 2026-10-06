defmodule BrainagramWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BrainagramWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="ba-app">
      <header class="ba-topbar">
        <.link navigate={~p"/"} class="ba-topbar__brand" aria-label={gettext("Brainagram, início")}>
          <.logo wordmark />
        </.link>
        <span class="ba-topbar__spacer"></span>
        <.theme_toggle />
      </header>

      <main class="ba-app__main">
        <div class="ba-app__content">
          {render_slot(@inner_block)}
        </div>
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="ba-toasts" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Sem conexão.")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Tentando reconectar…")}
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("O servidor não respondeu.")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Tentando reconectar…")}
      </.flash>
    </div>
    """
  end

  @doc """
  Alternância de tema: Sistema, Claro e Escuro.

  O `<head>` em root.html.heex aplica o tema antes do carregamento; a opção
  ativa é destacada pelo CSS a partir do `data-theme` do `<html>`.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="ba-seg ba-theme" role="group" aria-label={gettext("Tema")}>
      <button
        type="button"
        class="ba-seg__opt"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label={gettext("Tema do sistema")}
        title={gettext("Sistema")}
      >
        <.icon name="hero-computer-desktop-micro" class="ba-ico--16" />
      </button>
      <button
        type="button"
        class="ba-seg__opt"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label={gettext("Tema claro")}
        title={gettext("Claro")}
      >
        <.icon name="hero-sun-micro" class="ba-ico--16" />
      </button>
      <button
        type="button"
        class="ba-seg__opt"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label={gettext("Tema escuro")}
        title={gettext("Escuro")}
      >
        <.icon name="hero-moon-micro" class="ba-ico--16" />
      </button>
    </div>
    """
  end

  @doc """
  Seletor de idioma: a bandeira do idioma atual abre um menu com os sete
  idiomas (bandeira + nome no próprio idioma).

  A troca é feita no navegador (`assets/js/brainagram/locale.js`): grava o
  cookie lido por `BrainagramWeb.Locale`, guarda o código ainda não salvo e
  recarrega a página já no idioma novo. As bandeiras são SVG — emoji de
  bandeira não aparece no Windows.
  """
  attr :locale, :string, required: true

  def locale_toggle(assigns) do
    languages = BrainagramWeb.Locale.languages()

    assigns =
      assign(assigns,
        languages: languages,
        current: Enum.find(languages, hd(languages), &(&1.code == assigns.locale))
      )

    ~H"""
    <details class="ba-dropdown ba-locale" id="locale-menu">
      <summary
        class="ba-btn ba-btn--ghost ba-btn--sm ba-locale__current"
        aria-label={gettext("Idioma: %{name}", name: @current.name)}
        title={gettext("Idioma")}
      >
        <.flag code={@current.code} />
        <span>{@current.short}</span>
        <.icon name="hero-chevron-down-micro" />
      </summary>
      <div
        class="ba-menu ba-dropdown__menu ba-locale__menu"
        role="menu"
        aria-label={gettext("Idioma")}
      >
        <button
          :for={language <- @languages}
          type="button"
          class="ba-menu__item ba-locale__opt"
          role="menuitemradio"
          id={"locale-#{language.code}"}
          data-bg-locale={language.code}
          aria-checked={to_string(language.code == @locale)}
          lang={language.lang}
        >
          <.flag code={language.code} />
          <span>{language.name}</span>
          <span class="ba-locale__code">{language.short}</span>
        </button>
      </div>
    </details>
    """
  end

  attr :code, :string, required: true

  defp flag(%{code: "pt_BR"} = assigns) do
    ~H"""
    <svg class="ba-flag" viewBox="0 0 20 14" aria-hidden="true">
      <rect class="ba-flag__green" width="20" height="14" />
      <path class="ba-flag__yellow" d="M10 1.7 18.3 7 10 12.3 1.7 7Z" />
      <circle class="ba-flag__blue" cx="10" cy="7" r="3.3" />
      <path class="ba-flag__band" d="M6.8 6.2Q10 5.3 13.2 7.5" />
    </svg>
    """
  end

  defp flag(%{code: "en"} = assigns) do
    assigns =
      assign(assigns,
        stripes: for(i <- 0..12, rem(i, 2) == 0, do: i * 14 / 13),
        stars: for(row <- 0..2, col <- 0..3, do: {1.3 + col * 2.1, 1.3 + row * 2.3})
      )

    ~H"""
    <svg class="ba-flag" viewBox="0 0 20 14" aria-hidden="true">
      <rect class="ba-flag__white" width="20" height="14" />
      <rect :for={y <- @stripes} class="ba-flag__red" y={y} width="20" height={14 / 13} />
      <rect class="ba-flag__navy" width="9" height={14 * 7 / 13} />
      <circle :for={{x, y} <- @stars} class="ba-flag__white" cx={x} cy={y} r="0.45" />
    </svg>
    """
  end

  defp flag(%{code: "zh"} = assigns) do
    assigns =
      assign(assigns,
        big: star(3.4, 3.5, 2.1),
        small:
          for({x, y} <- [{6.8, 1.4}, {8.2, 2.8}, {8.2, 4.9}, {6.8, 6.3}], do: star(x, y, 0.7))
      )

    ~H"""
    <svg class="ba-flag" viewBox="0 0 20 14" aria-hidden="true">
      <rect class="ba-flag__cn-red" width="20" height="14" />
      <polygon class="ba-flag__cn-yellow" points={@big} />
      <polygon :for={points <- @small} class="ba-flag__cn-yellow" points={points} />
    </svg>
    """
  end

  defp flag(%{code: "ru"} = assigns) do
    ~H"""
    <svg class="ba-flag" viewBox="0 0 20 14" aria-hidden="true">
      <rect class="ba-flag__white" width="20" height="14" />
      <rect class="ba-flag__ru-blue" y={14 / 3} width="20" height={14 / 3} />
      <rect class="ba-flag__ru-red" y={28 / 3} width="20" height={14 / 3} />
    </svg>
    """
  end

  defp flag(%{code: "it"} = assigns) do
    ~H"""
    <svg class="ba-flag" viewBox="0 0 20 14" aria-hidden="true">
      <rect class="ba-flag__white" width="20" height="14" />
      <rect class="ba-flag__it-green" width={20 / 3} height="14" />
      <rect class="ba-flag__it-red" x={40 / 3} width={20 / 3} height="14" />
    </svg>
    """
  end

  defp flag(%{code: "ja"} = assigns) do
    ~H"""
    <svg class="ba-flag" viewBox="0 0 20 14" aria-hidden="true">
      <rect class="ba-flag__white" width="20" height="14" />
      <circle class="ba-flag__jp-red" cx="10" cy="7" r="4.2" />
    </svg>
    """
  end

  defp flag(%{code: "hi"} = assigns) do
    assigns =
      assign(assigns,
        spokes:
          for i <- 0..11 do
            angle = i * :math.pi() / 6
            {10 + 1.9 * :math.cos(angle), 7 + 1.9 * :math.sin(angle)}
          end
      )

    ~H"""
    <svg class="ba-flag" viewBox="0 0 20 14" aria-hidden="true">
      <rect class="ba-flag__white" width="20" height="14" />
      <rect class="ba-flag__in-saffron" width="20" height={14 / 3} />
      <rect class="ba-flag__in-green" y={28 / 3} width="20" height={14 / 3} />
      <circle class="ba-flag__in-wheel" cx="10" cy="7" r="1.9" />
      <line :for={{x, y} <- @spokes} class="ba-flag__in-spoke" x1="10" y1="7" x2={x} y2={y} />
      <circle class="ba-flag__in-hub" cx="10" cy="7" r="0.4" />
    </svg>
    """
  end

  # Estrela de 5 pontas centrada em (cx, cy), com a ponta para cima.
  defp star(cx, cy, r) do
    0..9
    |> Enum.map(fn i ->
      radius = if rem(i, 2) == 0, do: r, else: r * 0.382
      angle = -:math.pi() / 2 + i * :math.pi() / 5

      "#{Float.round(cx + radius * :math.cos(angle), 2)},#{Float.round(cy + radius * :math.sin(angle), 2)}"
    end)
    |> Enum.join(" ")
  end
end
