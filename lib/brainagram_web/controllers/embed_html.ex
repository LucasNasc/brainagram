defmodule BrainagramWeb.EmbedHTML do
  @moduledoc """
  As páginas do player embutível: o diagrama com uma barra de reprodução, ou o
  aviso de que ele não está disponível. Documento HTML completo, sem o layout
  do app: vive dentro do iframe de outro site.
  """

  use BrainagramWeb, :html

  embed_templates "embed_html/*"

  attr :url, :string, required: true
  attr :floating, :boolean, default: false

  @doc "O link para o diagrama no Brainagram: na barra, ou no canto sem barra."
  def embed_brand(assigns) do
    ~H"""
    <a
      class={["ba-embed__brand", @floating && "ba-embed__brand--floating"]}
      href={@url}
      target="_blank"
      rel="noopener"
      title={gettext("Abrir no Brainagram")}
    >
      <.logo size={16} /><span class="ba-embed__brand-text">Brainagram</span>
    </a>
    """
  end

  @doc "O valor de `data-theme` no `<html>`: nenhum no automático (segue o sistema)."
  def theme_attr("auto"), do: nil
  def theme_attr(theme), do: theme
end
