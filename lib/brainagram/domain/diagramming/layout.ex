defmodule Brainagram.Domain.Diagramming.Layout do
  @moduledoc """
  Serviço de domínio: despacha a AST para o motor de layout do seu tipo.

  Fica no domínio, e não na infraestrutura, porque decidir *como um diagrama de
  sequência se parece* é a regra de negócio central deste produto — não um
  detalhe técnico substituível.
  """

  alias Brainagram.Domain.Diagramming.Dsl.Ast
  alias Brainagram.Domain.Diagramming.Layout.{Architecture, Hints, Sequence}
  alias Brainagram.Domain.Diagramming.Scene

  @doc """
  Compila a AST em cena. As posições fixadas no bloco `layout` entram como
  `Hints`; sem o bloco, tudo é automático. `direction` só vale para
  arquitetura: o eixo do tempo da sequência é sempre vertical.
  """
  @spec build(Ast.t()) :: Scene.t()
  def build(%Ast{} = ast) do
    hints = Hints.from_ast(ast)

    scene =
      case ast.kind do
        :architecture -> Architecture.build(ast, hints)
        _ -> Sequence.build(ast, hints)
      end

    %{scene | has_layout: not is_nil(ast.layout_span)}
  end
end
