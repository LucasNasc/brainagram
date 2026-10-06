defmodule Brainagram.Domain.Diagramming.ValueObjects.ProjectName do
  @moduledoc """
  Nome de um projeto — a pasta onde a pessoa separa os diagramas.

  Diferente do título de um diagrama, este é digitado: o projeto não tem fonte
  de onde derivar nada. Por isso as invariantes moram aqui: nunca em branco,
  nunca gigante, sem espaços sobrando.
  """

  alias Brainagram.Shared.Text

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}

  @max_length 60

  @spec new(String.t() | t() | nil) ::
          {:ok, t()} | {:error, :blank_project_name | :project_name_too_long}
  def new(%__MODULE__{} = name), do: {:ok, name}

  def new(value) when is_binary(value) do
    normalized = value |> String.replace(~r/\s+/, " ") |> String.trim()

    cond do
      Text.blank?(normalized) -> {:error, :blank_project_name}
      String.length(normalized) > @max_length -> {:error, :project_name_too_long}
      true -> {:ok, %__MODULE__{value: normalized}}
    end
  end

  def new(_), do: {:error, :blank_project_name}

  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{value: value}), do: value
end
