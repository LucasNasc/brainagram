defmodule Brainagram.Domain.Diagramming.ValueObjects.Title do
  @moduledoc """
  Título de um diagrama.

  Normalmente não é digitado: sai da diretiva `diagram <tipo> "<título>"` da
  própria DSL. Manter isso como value object garante que o título nunca entre
  em branco ou gigante no banco, independentemente de por onde ele chegou.
  """

  alias Brainagram.Shared.Text

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}

  @max_length 160
  @fallback "Sem título"

  @spec new(String.t() | t() | nil) :: {:ok, t()} | {:error, :title_too_long}
  def new(%__MODULE__{} = title), do: {:ok, title}

  def new(value) do
    cond do
      Text.blank?(value) -> {:ok, %__MODULE__{value: @fallback}}
      String.length(value) > @max_length -> {:error, :title_too_long}
      true -> {:ok, %__MODULE__{value: String.trim(value)}}
    end
  end

  @spec fallback() :: t()
  def fallback, do: %__MODULE__{value: @fallback}

  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{value: value}), do: value

  defimpl String.Chars do
    def to_string(%{value: value}), do: value
  end
end
