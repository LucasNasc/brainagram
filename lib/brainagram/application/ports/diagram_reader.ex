defmodule Brainagram.Application.Ports.DiagramReader do
  @moduledoc """
  Porta de leitura.

  Mora na camada de aplicação, e não no domínio, por um motivo específico: ela
  devolve *read models*, que são artefatos de aplicação. Se o domínio
  declarasse este contrato, ele passaria a depender de uma camada acima — a
  seta de dependência se inverteria e o desenho deixaria de valer.

  É também a metade do CQRS que não passa pelo agregado: consultar não carrega,
  não valida e não reconstitui nada. Vai direto da tabela para a tela.
  """

  alias Brainagram.Application.ReadModels.{DiagramDetail, DiagramSummary}

  @callback fetch_by_slug(String.t()) :: {:ok, DiagramDetail.t()} | {:error, :not_found}
  @callback list_public(limit :: pos_integer()) :: [DiagramSummary.t()]
  @callback count_public() :: non_neg_integer()

  @typedoc """
  Filtros da área de gestão. `project`: slug de um projeto, `:none` (sem
  projeto) ou `nil` (todos). `search`: trecho do título, sem diferenciar
  maiúsculas. `kind`: `"sequence"`, `"architecture"` ou `nil`.
  """
  @type filters :: %{
          optional(:project) => String.t() | :none | nil,
          optional(:search) => String.t() | nil,
          optional(:kind) => String.t() | nil,
          optional(:sort) => :updated | :created | :title,
          optional(:limit) => pos_integer()
        }

  @callback list(filters()) :: [DiagramSummary.t()]

  @doc """
  Os diagramas de um escopo **com o fonte** — só para exportar. A listagem da
  tela continua sem o fonte (`list/1`); aqui ele é o próprio conteúdo pedido.
  """
  @callback list_sources(filters()) :: [
              %{
                slug: String.t(),
                title: String.t(),
                source: String.t(),
                visibility: String.t(),
                project: String.t() | nil,
                project_name: String.t() | nil,
                project_color: String.t() | nil
              }
            ]

  @doc "Quantos diagramas existem no total e quantos estão sem projeto."
  @callback counts() :: %{all: non_neg_integer(), none: non_neg_integer()}
end
