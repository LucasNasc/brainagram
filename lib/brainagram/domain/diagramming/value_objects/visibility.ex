defmodule Brainagram.Domain.Diagramming.ValueObjects.Visibility do
  @moduledoc """
  Quem enxerga o diagrama.

  Hoje são dois estados. É enum por vocação: quando entrar `:unlisted` (link
  secreto, fora da listagem pública), o compilador aponta cada `case` que
  precisa de um ramo novo — coisa que um boolean `public` não faria.
  """

  @values [:public, :private]

  @type t :: :public | :private

  @spec values() :: [t()]
  def values, do: @values

  @spec default() :: t()
  def default, do: :public

  @spec new(t() | String.t() | boolean() | nil) :: {:ok, t()} | {:error, :invalid_visibility}
  def new(nil), do: {:ok, default()}
  def new(value) when value in @values, do: {:ok, value}
  def new(true), do: {:ok, :public}
  def new(false), do: {:ok, :private}

  def new(value) when is_binary(value) do
    case Enum.find(@values, &(Atom.to_string(&1) == value)) do
      nil -> {:error, :invalid_visibility}
      visibility -> {:ok, visibility}
    end
  end

  def new(_), do: {:error, :invalid_visibility}

  @spec public?(t()) :: boolean()
  def public?(visibility), do: visibility == :public

  @spec to_string(t()) :: String.t()
  def to_string(visibility) when visibility in @values, do: Atom.to_string(visibility)
end
