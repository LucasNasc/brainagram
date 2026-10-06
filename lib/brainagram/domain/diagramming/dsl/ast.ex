defmodule Brainagram.Domain.Diagramming.Dsl.Ast do
  @moduledoc """
  Árvore sintática abstrata produzida por `Brainagram.Domain.Diagramming.Dsl.Parser`.

  A AST é intencionalmente "burra": ela descreve *o que* o autor escreveu,
  sem nenhuma noção de geometria. Toda decisão visual acontece depois, em
  `Brainagram.Domain.Diagramming.Layout.*`.

  Cada nó carrega `span` (a declaração inteira) e `spans` (um `%Span{}` por
  campo editável). É o contrato que permite ao canvas reescrever só os bytes
  do que foi mexido — ver `Dsl.Editor`. O que não foi escrito no texto (um nó
  declarado só por aparecer numa seta, um passo implícito) tem `span: nil`.

  O bloco `layout { id at (x, y) }` vira `pins`: posições fixadas à mão, que o
  layout automático respeita.
  """

  alias Brainagram.Domain.Diagramming.Dsl.Span

  defstruct kind: :sequence,
            title: nil,
            nodes: [],
            groups: [],
            steps: [],
            pins: [],
            span: nil,
            spans: %{},
            layout_span: nil,
            layout_end_span: nil

  @type t :: %__MODULE__{
          kind: :sequence | :architecture,
          title: String.t() | nil,
          nodes: [Brainagram.Domain.Diagramming.Dsl.Node.t()],
          groups: [Brainagram.Domain.Diagramming.Dsl.Group.t()],
          steps: [Brainagram.Domain.Diagramming.Dsl.Step.t()],
          pins: [Brainagram.Domain.Diagramming.Dsl.Pin.t()],
          span: Span.t() | nil,
          spans: %{optional(atom()) => Span.t() | nil},
          layout_span: Span.t() | nil,
          layout_end_span: Span.t() | nil
        }
end

defmodule Brainagram.Domain.Diagramming.Dsl.Node do
  @moduledoc "Um participante (sequência) ou caixa (arquitetura)."
  defstruct [:id, :label, :kind, :group, :line, span: nil, spans: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          kind: atom(),
          group: String.t() | nil,
          line: pos_integer(),
          span: Brainagram.Domain.Diagramming.Dsl.Span.t() | nil,
          spans: %{
            optional(:id | :label | :kind) => Brainagram.Domain.Diagramming.Dsl.Span.t() | nil
          }
        }
end

defmodule Brainagram.Domain.Diagramming.Dsl.Group do
  @moduledoc "Agrupamento visual de nós (boundary, VPC, bounded context...)."
  defstruct [:id, :label, :node_ids, :line, span: nil, end_span: nil, spans: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          node_ids: [String.t()],
          line: pos_integer(),
          span: Brainagram.Domain.Diagramming.Dsl.Span.t() | nil,
          end_span: Brainagram.Domain.Diagramming.Dsl.Span.t() | nil,
          spans: %{optional(:label) => Brainagram.Domain.Diagramming.Dsl.Span.t() | nil}
        }
end

defmodule Brainagram.Domain.Diagramming.Dsl.Step do
  @moduledoc """
  Um passo da timeline: o que é animado junto, em ordem.

  `implicit: true` marca os passos que o parser inventou (uma mensagem solta
  por passo, ou o "Contexto inicial" que junta o que ficou fora dos blocos):
  eles não existem no texto, então não têm `span`.
  """
  defstruct [:index, :label, :items, :line, implicit: false, span: nil, end_span: nil, spans: %{}]

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          label: String.t(),
          items: [
            Brainagram.Domain.Diagramming.Dsl.Edge.t()
            | Brainagram.Domain.Diagramming.Dsl.Note.t()
          ],
          line: pos_integer(),
          implicit: boolean(),
          span: Brainagram.Domain.Diagramming.Dsl.Span.t() | nil,
          end_span: Brainagram.Domain.Diagramming.Dsl.Span.t() | nil,
          spans: %{optional(:label) => Brainagram.Domain.Diagramming.Dsl.Span.t() | nil}
        }
end

defmodule Brainagram.Domain.Diagramming.Dsl.Edge do
  @moduledoc """
  Uma mensagem/conexão entre dois nós.

  `payload` é o que a mensagem carrega (o corpo de um POST, a linha de um
  INSERT, os cabeçalhos…), escrito logo abaixo dela com `payload:` ou num
  bloco `payload \""" … \"""`. Os spans `:payload` e `:payload_end` marcam a
  primeira e a última linha desse trecho, para a edição pelo canvas trocar ou
  apagar o payload sem tocar no resto.
  """
  defstruct [:id, :from, :to, :label, :arrow, :line, :payload, span: nil, spans: %{}]

  @type arrow :: :sync | :return | :async | :fail

  @type t :: %__MODULE__{
          id: String.t(),
          from: String.t(),
          to: String.t(),
          label: String.t() | nil,
          arrow: arrow(),
          payload: String.t() | nil,
          line: pos_integer(),
          span: Brainagram.Domain.Diagramming.Dsl.Span.t() | nil,
          spans: %{
            optional(:from | :to | :arrow | :label | :payload | :payload_end) =>
              Brainagram.Domain.Diagramming.Dsl.Span.t() | nil
          }
        }
end

defmodule Brainagram.Domain.Diagramming.Dsl.Note do
  @moduledoc "Uma anotação ancorada em um ou mais nós."
  defstruct [:id, :placement, :target_ids, :text, :line, span: nil, spans: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          placement: :over | :left | :right,
          target_ids: [String.t()],
          text: String.t(),
          line: pos_integer(),
          span: Brainagram.Domain.Diagramming.Dsl.Span.t() | nil,
          spans: %{
            optional(:placement | :targets | :text) =>
              Brainagram.Domain.Diagramming.Dsl.Span.t() | nil
          }
        }
end

defmodule Brainagram.Domain.Diagramming.Dsl.Pin do
  @moduledoc "Uma posição fixada à mão, dentro do bloco `layout { }`: `api at (420, 680)`."
  defstruct [:id, :x, :y, :line, span: nil, spans: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          x: integer(),
          y: integer(),
          line: pos_integer(),
          span: Brainagram.Domain.Diagramming.Dsl.Span.t() | nil,
          spans: %{optional(:id | :coords) => Brainagram.Domain.Diagramming.Dsl.Span.t() | nil}
        }
end
