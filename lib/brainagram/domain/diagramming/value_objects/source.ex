defmodule Brainagram.Domain.Diagramming.ValueObjects.Source do
  @moduledoc """
  O código-fonte da DSL — o value object mais importante do domínio.

  A decisão de modelagem aqui é: **um `%Source{}` só existe se compilar**.
  `new/1` roda o parser e devolve `{:error, erros}` quando o texto é inválido,
  então nenhuma outra parte do sistema precisa perguntar "esse fonte é válido?".
  Estado ilegal virou estado irrepresentável.

  Como consequência, o `Source` carrega a AST já parseada. Isso não é cache
  oportunista: é o resultado da validação que seria jogado fora e reconstruído
  depois. Título e tipo do diagrama saem daqui, não de campos digitados à parte
  — é o que impede o metadado de divergir do conteúdo.
  """

  alias Brainagram.Domain.Diagramming.Dsl.{Ast, ParseError, Parser}
  alias Brainagram.Domain.Diagramming.Layout
  alias Brainagram.Domain.Diagramming.Scene
  alias Brainagram.Domain.Diagramming.ValueObjects.{Kind, Title}

  @enforce_keys [:raw, :ast]
  defstruct [:raw, :ast]

  @type t :: %__MODULE__{raw: String.t(), ast: Ast.t()}

  @max_bytes 200_000

  @spec new(String.t() | t()) ::
          {:ok, t()} | {:error, {:syntax, [Parser.error()]}} | {:error, :source_too_large}
  def new(%__MODULE__{} = source), do: {:ok, source}

  def new(raw) when is_binary(raw) do
    if byte_size(raw) > @max_bytes do
      {:error, :source_too_large}
    else
      case Parser.parse(raw) do
        {:ok, ast} -> {:ok, %__MODULE__{raw: raw, ast: ast}}
        {:error, errors} -> {:error, {:syntax, errors}}
      end
    end
  end

  def new(_),
    do:
      {:error,
       {:syntax, [%ParseError{line: 1, message: "fonte inválido", code: :invalid_source}]}}

  @doc "Compila para a cena renderizável. Total — a AST já foi validada em `new/1`."
  @spec scene(t()) :: Scene.t()
  def scene(%__MODULE__{ast: ast}), do: Layout.build(ast)

  @spec kind(t()) :: Kind.t()
  def kind(%__MODULE__{ast: ast}), do: ast.kind

  @doc "Título declarado na DSL; cai no padrão quando o autor não declarou um."
  @spec title(t()) :: Title.t()
  def title(%__MODULE__{ast: ast}) do
    case Title.new(ast.title) do
      {:ok, title} -> title
      {:error, _} -> Title.fallback()
    end
  end

  @spec raw(t()) :: String.t()
  def raw(%__MODULE__{raw: raw}), do: raw

  @doc "Igualdade por valor — dois fontes são o mesmo se o texto é o mesmo."
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{raw: a}, %__MODULE__{raw: b}), do: a == b

  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes
end
