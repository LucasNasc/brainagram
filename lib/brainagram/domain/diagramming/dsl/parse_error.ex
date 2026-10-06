defmodule Brainagram.Domain.Diagramming.Dsl.ParseError do
  @moduledoc """
  Um problema de sintaxe, ancorado na linha.

  Struct e não mapa solto porque este valor atravessa três camadas até virar
  marcação no editor: domínio → aplicação → LiveView. O struct garante que
  nenhuma delas invente um campo pelo caminho.

  `message` é a frase pronta em português (tarefas Mix, logs). `code` e
  `bindings` deixam a interface traduzir: o texto é o mesmo, com os valores
  de `bindings` no lugar de `%{nome}`.
  """

  @enforce_keys [:line, :message]
  defstruct [:line, :message, code: nil, bindings: %{}]

  @type t :: %__MODULE__{
          line: pos_integer(),
          message: String.t(),
          code: atom() | nil,
          bindings: %{optional(atom()) => String.t()}
        }
end
