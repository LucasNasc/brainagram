defmodule Brainagram.Domain.Diagramming.Scene do
  @moduledoc """
  Representação intermediária (IR) de um diagrama: geometria resolvida +
  timeline, pronta para ser serializada em JSON e desenhada pelo cliente.

  Esta é a fronteira do sistema. O servidor decide *onde* cada coisa fica e
  *quando* cada coisa acontece; o cliente só desenha e toca. Isso mantém o
  layout testável em Elixir e a interação a 60fps sem round-trip.

  Para o modo de edição, cada nó leva também `group` (rótulo do grupo, ou
  `nil`) e `pinned` (se está no bloco `layout`), e a cena diz se o bloco
  existe (`has_layout`) — o que habilita o botão "Reorganizar".

  `direction` é o sentido do layout de arquitetura (`:vertical` ou
  `:horizontal`); a sequência é sempre `:vertical`.
  """

  @derive Jason.Encoder
  defstruct kind: :sequence,
            title: nil,
            direction: :vertical,
            width: 0,
            height: 0,
            nodes: [],
            groups: [],
            edges: [],
            notes: [],
            activations: [],
            steps: [],
            has_layout: false

  @type t :: %__MODULE__{}

  @doc """
  Raio horizontal das tampas do cilindro deitado que desenha uma fila. A caixa
  da fila é `2 * queue_cap()` mais larga para o rótulo não encostar na tampa;
  `renderer.js` usa o mesmo valor.
  """
  @spec queue_cap() :: pos_integer()
  def queue_cap, do: 12

  @doc """
  Altura do losango de um nó `decision` (as caixas têm 68): o texto fica na
  faixa do meio, e um losango achatado demais não parece pergunta.
  """
  @spec decision_h() :: pos_integer()
  def decision_h, do: 88

  @doc """
  Largura do losango para o rótulo caber dentro dele. Uma linha de texto de
  altura ~20 no meio de um losango de altura `h` cabe se
  `texto / largura + 20 / h <= 1`; a folga extra afasta o texto das pontas.
  """
  @spec decision_width(String.t(), number(), number()) :: pos_integer()
  def decision_width(label, size, min) do
    text = text_width(label, size)
    round(max(min, text / (1 - 20 / decision_h()) + 36))
  end

  @doc "Estimativa de largura de texto (evita medir no DOM para manter o layout puro)."
  @spec text_width(String.t() | nil, number()) :: float()
  def text_width(text, size), do: char_units(text) * size * 0.56

  @doc """
  Quantos caracteres latinos o texto ocupa. Ideogramas, kana e hangul são
  quadrados (~1 em, quase o dobro de uma letra latina), então contam 1,8;
  o resto conta 1 por grafema.
  """
  @spec char_units(String.t() | nil) :: float()
  def char_units(nil), do: 0.0

  def char_units(text) do
    text
    |> String.graphemes()
    |> Enum.reduce(0.0, fn grapheme, acc ->
      <<codepoint::utf8, _::binary>> = grapheme
      acc + if(wide?(codepoint), do: 1.8, else: 1.0)
    end)
  end

  defp wide?(cp)
       when cp in 0x1100..0x115F or cp in 0x2E80..0xA4CF or cp in 0xAC00..0xD7A3 or
              cp in 0xF900..0xFAFF or cp in 0xFE30..0xFE4F or cp in 0xFF00..0xFF60 or
              cp in 0xFFE0..0xFFE6 or cp in 0x20000..0x3FFFD,
       do: true

  defp wide?(_cp), do: false

  @doc "Duração sugerida, em ms, para animar uma aresta."
  @spec edge_duration(map()) :: pos_integer()
  def edge_duration(%{arrow: :return}), do: 520
  def edge_duration(%{arrow: :async}), do: 820
  def edge_duration(_), do: 700
end
