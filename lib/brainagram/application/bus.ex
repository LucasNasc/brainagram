defmodule Brainagram.Application.Bus do
  @moduledoc """
  Porta de entrada única da aplicação.

  A camada web não conhece handler, repositório, Ecto nem agregado — conhece
  este módulo e os structs de comando/query. Duas operações:

      Bus.dispatch(CreateDiagram, %{source: texto})   # escreve
      Bus.ask(GetDiagramBySlug, %{slug: "abc123"})    # lê

  O barramento faz três coisas e só três: valida a mensagem, chama o handler
  declarado por ela e — no caso de comando — publica os eventos que o handler
  devolveu. Publicar **depois** do handler é o que garante que nenhum evento
  escape de uma escrita que falhou.

  Não há registro central de rotas: cada mensagem declara seu handler. Isso
  evita o arquivo gigante de despacho que sempre vira ponto de conflito de
  merge, e faz "quem trata isso?" ser uma ida à definição no editor.
  """

  require Logger

  alias Brainagram.Application.{Message, Ports}

  @type failure :: {:error, Ecto.Changeset.t()} | {:error, term()}

  @doc "Executa um comando. Aceita `(módulo, atributos)` ou um comando já montado."
  @spec dispatch(module() | struct(), map()) :: {:ok, term()} | failure()
  def dispatch(command, attrs \\ %{})

  def dispatch(module, attrs) when is_atom(module) do
    with {:ok, command} <- module.new(attrs), do: run(module, command)
  end

  def dispatch(%module{} = command, _attrs), do: run(module, command)

  @doc "Executa uma query. Mesma assinatura, sem eventos no caminho."
  @spec ask(module() | struct(), map()) :: {:ok, term()} | failure()
  def ask(query, attrs \\ %{})

  def ask(module, attrs) when is_atom(module) do
    with {:ok, query} <- module.new(attrs), do: module.handler().handle(query)
  end

  def ask(%module{} = query, _attrs), do: module.handler().handle(query)

  @doc """
  Assina os eventos de um diagrama.

  Está aqui, e não num módulo de infraestrutura importado pela web, para que a
  camada de cima continue conhecendo um endereço só. Quem escuta recebe
  `{:domain_event, %Evento{}}` no `handle_info`.
  """
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(slug) when is_binary(slug), do: Ports.event_bus().subscribe(slug)

  @doc "Assina os eventos de todos os diagramas e projetos — é o que a área de gestão escuta."
  @spec subscribe_all() :: :ok | {:error, term()}
  def subscribe_all, do: Ports.event_bus().subscribe_all()

  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(slug) when is_binary(slug), do: Ports.event_bus().unsubscribe(slug)

  @doc "Formata a falha de validação de uma mensagem como `%{campo => [erros]}`."
  @spec validation_errors(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  defdelegate validation_errors(changeset), to: Message, as: :errors

  defp run(module, command) do
    case module.handler().handle(command) do
      {:ok, result, events} ->
        publish(events)
        {:ok, result}

      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp publish([]), do: :ok

  defp publish(events) do
    Ports.event_bus().publish(events)
  rescue
    error ->
      # Falha de broadcast não pode derrubar uma escrita que já foi confirmada.
      Logger.error("falha ao publicar eventos de domínio: #{Exception.message(error)}")
      :ok
  end
end
