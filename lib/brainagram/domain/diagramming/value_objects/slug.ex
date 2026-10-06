defmodule Brainagram.Domain.Diagramming.ValueObjects.Slug do
  @moduledoc """
  Identificador público e compartilhável de um diagrama (`/d/:slug`).

  É value object e não uma string solta porque carrega invariantes reais:
  formato estável de URL, tamanho limitado e imutabilidade. Um `%Slug{}` em
  qualquer assinatura de função já provou que passou por validação.
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}

  @format ~r/\A[a-z0-9][a-z0-9_-]{2,63}\z/
  @generated_bytes 8

  @spec new(String.t() | t()) :: {:ok, t()} | {:error, :invalid_slug}
  def new(%__MODULE__{} = slug), do: {:ok, slug}

  def new(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()

    if Regex.match?(@format, normalized) do
      {:ok, %__MODULE__{value: normalized}}
    else
      {:error, :invalid_slug}
    end
  end

  def new(_), do: {:error, :invalid_slug}

  @doc """
  Gera um slug aleatório — usado quando o autor não escolhe um.

  Base32 e não base64url: o alfabeto do base64url inclui `-` e `_`, que o
  `@format` proíbe na primeira posição. Um gerador capaz de produzir valor que
  o próprio `new/1` rejeita é uma bomba-relógio — falha em ~3% das criações,
  o suficiente para passar no code review e aparecer como "erro aleatório" em
  produção. Base32 minúsculo (`a-z`, `2-7`) é sempre válido por construção.
  """
  @spec generate() :: t()
  def generate do
    value =
      @generated_bytes
      |> :crypto.strong_rand_bytes()
      |> Base.encode32(case: :lower, padding: false)

    %__MODULE__{value: value}
  end

  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{value: value}), do: value

  defimpl String.Chars do
    def to_string(%{value: value}), do: value
  end
end
