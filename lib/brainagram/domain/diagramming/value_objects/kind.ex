defmodule Brainagram.Domain.Diagramming.ValueObjects.Kind do
  @moduledoc """
  Tipo do diagrama.

  Enum sobre átomos em vez de struct: não há invariante além de "é um dos
  valores conhecidos", e átomo é o que o pattern matching do Elixir despacha
  melhor (`Layout.build(%Ast{kind: :architecture})`). Envolver isso num struct
  seria cerimônia sem ganho.
  """

  @values [:sequence, :architecture]

  @type t :: :sequence | :architecture

  @spec values() :: [t()]
  def values, do: @values

  @spec new(t() | String.t()) :: {:ok, t()} | {:error, :invalid_kind}
  def new(value) when value in @values, do: {:ok, value}

  def new(value) when is_binary(value) do
    case Enum.find(@values, &(Atom.to_string(&1) == value)) do
      nil -> {:error, :invalid_kind}
      kind -> {:ok, kind}
    end
  end

  def new(_), do: {:error, :invalid_kind}

  @spec to_string(t()) :: String.t()
  def to_string(kind) when kind in @values, do: Atom.to_string(kind)
end
