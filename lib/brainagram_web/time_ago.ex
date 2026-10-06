defmodule BrainagramWeb.TimeAgo do
  @moduledoc """
  "há 3 min", "ontem", "12/09/2026" — quando um diagrama mudou, no idioma da
  interface. Até uma semana, relativo (é o que se lê de relance numa lista);
  depois, a data.
  """

  use Gettext, backend: BrainagramWeb.Gettext

  @spec format(DateTime.t() | NaiveDateTime.t() | nil, DateTime.t()) :: String.t()
  def format(at, now \\ DateTime.utc_now())

  def format(nil, _now), do: ""

  def format(%NaiveDateTime{} = at, now), do: format(DateTime.from_naive!(at, "Etc/UTC"), now)

  def format(%DateTime{} = at, now) do
    seconds = max(DateTime.diff(now, at, :second), 0)

    cond do
      seconds < 60 -> gettext("agora mesmo")
      seconds < 3_600 -> ngettext("há 1 min", "há %{count} min", div(seconds, 60))
      seconds < 86_400 -> ngettext("há 1 h", "há %{count} h", div(seconds, 3_600))
      seconds < 2 * 86_400 -> gettext("ontem")
      seconds < 7 * 86_400 -> ngettext("há 1 dia", "há %{count} dias", div(seconds, 86_400))
      true -> date(at)
    end
  end

  @doc "A data por extenso curto, no formato do idioma."
  @spec date(DateTime.t()) :: String.t()
  def date(%DateTime{} = at) do
    case Gettext.get_locale(BrainagramWeb.Gettext) do
      "en" -> Calendar.strftime(at, "%b %-d, %Y")
      locale when locale in ["zh", "ja"] -> Calendar.strftime(at, "%Y/%m/%d")
      "ru" -> Calendar.strftime(at, "%d.%m.%Y")
      _ -> Calendar.strftime(at, "%d/%m/%Y")
    end
  end
end
