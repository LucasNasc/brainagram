defmodule Brainagram.Domain.Diagramming.Dsl.Span do
  @moduledoc """
  Posição de um trecho no texto original.

  É o que permite editar o fonte cirurgicamente: o canvas não regenera o
  arquivo, ele troca os bytes de *um* trecho. Por isso o contrato é em bytes
  (`offset`, `length`), não em caracteres — `binary_part/3` é a operação que
  garante que o resto do arquivo fica idêntico.

    * `line` — linha (1-based)
    * `column` — coluna em bytes dentro da linha (1-based)
    * `offset` — posição em bytes desde o início do fonte (0-based)
    * `length` — tamanho em bytes do trecho
  """

  @enforce_keys [:line, :column, :offset, :length]
  defstruct [:line, :column, :offset, :length]

  @type t :: %__MODULE__{
          line: pos_integer(),
          column: pos_integer(),
          offset: non_neg_integer(),
          length: non_neg_integer()
        }

  @spec new(pos_integer(), pos_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def new(line, column, offset, length) do
    %__MODULE__{line: line, column: column, offset: offset, length: length}
  end

  @doc "Posição logo depois do trecho."
  @spec stop(t()) :: non_neg_integer()
  def stop(%__MODULE__{offset: offset, length: length}), do: offset + length

  @doc "O texto que o trecho cobre."
  @spec slice(String.t(), t()) :: String.t()
  def slice(source, %__MODULE__{offset: offset, length: length}),
    do: binary_part(source, offset, length)
end
