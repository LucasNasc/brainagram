defmodule Brainagram.Shared.Text do
  @moduledoc """
  Utilitários de texto sem dependência de nenhuma camada.

  Regra do diretório `shared/`: só entra aqui o que é genuinamente transversal
  e livre de regra de negócio. Se uma função precisa saber o que é um diagrama,
  ela pertence ao domínio, não aqui.
  """

  @doc """
  Transforma um identificador em rótulo legível.

      iex> Brainagram.Shared.Text.humanize("order_service")
      "Order Service"
  """
  @spec humanize(String.t()) :: String.t()
  def humanize(id) when is_binary(id) do
    id
    |> String.replace(~r/[_\-.]+/, " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc """
  Versão ASCII, minúscula e hifenizada de um texto — para nomes de arquivo e URLs.

      iex> Brainagram.Shared.Text.slugify("Checkout com pagamento assíncrono")
      "checkout-com-pagamento-assincrono"
  """
  @spec slugify(String.t() | nil) :: String.t()
  def slugify(nil), do: ""

  def slugify(text) when is_binary(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/[^A-Za-z0-9\s-]/u, "")
    |> String.downcase()
    |> String.replace(~r/[\s_-]+/, "-")
    |> String.trim("-")
  end

  @spec blank?(term()) :: boolean()
  def blank?(nil), do: true
  def blank?(value) when is_binary(value), do: String.trim(value) == ""
  def blank?(_), do: false

  @spec presence(term()) :: String.t() | nil
  def presence(value), do: if(blank?(value), do: nil, else: value)
end
