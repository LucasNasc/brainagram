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
  """

  @derive Jason.Encoder
  defstruct kind: :sequence,
            title: nil,
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
