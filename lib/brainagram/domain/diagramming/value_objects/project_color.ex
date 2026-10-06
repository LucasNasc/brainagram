defmodule Brainagram.Domain.Diagramming.ValueObjects.ProjectColor do
  @moduledoc """
  A cor que identifica um projeto na lateral e nos cards.

  Um nome de uma paleta fechada, não um hexadecimal: a cor de verdade vem dos
  tokens do design system (`--project-violet`…), então ela acompanha o tema
  claro e o escuro, e ninguém consegue escolher uma cor ilegível.
  """

  @values [:violet, :blue, :teal, :green, :amber, :orange, :rose, :slate]

  @type t :: :violet | :blue | :teal | :green | :amber | :orange | :rose | :slate

  @spec values() :: [t()]
  def values, do: @values

  @spec default() :: t()
  def default, do: :violet

  @spec new(t() | String.t() | nil) :: {:ok, t()} | {:error, :invalid_project_color}
  def new(nil), do: {:ok, default()}
  def new(""), do: {:ok, default()}
  def new(value) when value in @values, do: {:ok, value}

  def new(value) when is_binary(value) do
    case Enum.find(@values, &(Atom.to_string(&1) == value)) do
      nil -> {:error, :invalid_project_color}
      color -> {:ok, color}
    end
  end

  def new(_), do: {:error, :invalid_project_color}

  @spec to_string(t()) :: String.t()
  def to_string(color) when color in @values, do: Atom.to_string(color)
end
