defmodule BrainagramWeb.Gettext do
  @moduledoc """
  Traduções da interface.

  Os textos em português são a própria chave (`gettext("Salvar")`): o
  português não precisa de arquivo, e `priv/gettext/<idioma>/LC_MESSAGES/*.po`
  traz os outros (`en`, `zh`, `ru`, `it`, `ja`, `hi`). Depois de mudar textos:

      mix gettext.extract --merge

  e preencher os `msgstr` vazios de cada idioma.
  """

  use Gettext.Backend,
    otp_app: :brainagram,
    default_locale: "pt_BR",
    locales: ~w(pt_BR en zh ru it ja hi)
end
