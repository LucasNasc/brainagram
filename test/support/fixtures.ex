defmodule Brainagram.Test.Fixtures do
  @moduledoc "Fontes e agregados prontos para os testes."

  alias Brainagram.Domain.Diagramming.Diagram
  alias Brainagram.Domain.Diagramming.Scene
  alias Brainagram.Domain.Diagramming.ValueObjects.Source
  alias Brainagram.Application.Ports

  @spec source(String.t()) :: String.t()
  def source(slug) do
    {:ok, example} = Ports.example_catalog().fetch(slug)
    example.source
  end

  @spec sequence_source() :: String.t()
  def sequence_source, do: source("checkout")

  @spec architecture_source() :: String.t()
  def architecture_source, do: source("arquitetura")

  @doc """
  Arquitetura com as setas emaranhadas, como costuma chegar de um Mermaid ou
  PlantUML: a ordem das declarações foi pensada para ler, não para desenhar.
  """
  @spec tangled_architecture_source() :: String.t()
  def tangled_architecture_source do
    """
    diagram architecture "Bagunça"
    group "Dados" {
      database pg "Postgres"   # principal
      queue mq "Fila"
      database redis "Redis"
    }
    group "Borda" {
      node lb "LB"
      node cdn "CDN"
    }
    group "App" {
      service worker "Worker"
      service api "API"
      service auth "Auth"
    }
    external s3 "S3"
    external mail "E-mail"
    cdn -> lb : https
    lb -> api
    api -> auth : valida
    auth -> redis : sessão
    api -> pg : SELECT
    api ->> mq : evento
    mq -> worker : consome
    worker -> pg : UPDATE
    worker -> s3 : upload
    worker -> mail : envia
    auth -> pg : usuários
    """
  end

  @doc """
  Diagrama de componentes do PlantUML como os do mundo real: `package` e
  `cloud` com `{ }`, `[Nome\\n(detalhe)] as ID`, setas coloridas, um ciclo
  (o cliente manda comando e recebe evento) e notas de várias linhas.
  """
  @spec plantuml_component_source() :: String.t()
  def plantuml_component_source do
    ~S"""
    @startuml Introducao_Objetivos_Integracoes
    title Visão Introdutória — Objetivos e Integrações

    skinparam componentStyle rectangle

    rectangle "Clientes/Consumidores" as CLIENTS
    package "WPP-API (NestJS)" {
      [AppSyncSubscriberService\n(Realtime WS)] as ASS
      [BaileysWhatsAppService\n(Fluxos WhatsApp)] as BWS
      [AppSyncEventsService\n(Events HTTP)] as AES
      [Cache/Redis] as REDIS
    }

    cloud "AWS AppSync" {
      [Realtime WS] as RT
      [Event API /event] as APP
    }

    cloud "WhatsApp" as WA

    CLIENTS -[#blue]-> ASS : comandos (WS)
    ASS -[#blue]-> RT : subscribe / data
    ASS -[#green]-> BWS : executeAction(action, content)

    BWS -[#darkgreen]-> WA : WASocket
    BWS -[#darkgreen]-> REDIS : credenciais / grupos

    BWS -[#orange]-> AES : eventos (mensagens, status, grupos, pairing)
    AES -[#orange]-> APP : POST /event
    APP -[#brown]-> CLIENTS : eventos por canal

    note right of ASS
    - Reconexão proativa <24h
    - Watchdog keep-alive
    end note

    note right of BWS
    - Backoff até 30s
    - 408/429 => restart
    - Link preview HD / canais
    end note

    @enduml
    """
  end

  @doc "Compila um fonte em cena, estourando se não for válido."
  @spec scene!(String.t()) :: Scene.t()
  def scene!(raw) do
    {:ok, source} = Source.new(raw)
    Source.scene(source)
  end

  @doc "Um agregado válido, ainda não persistido."
  @spec diagram!(map()) :: Diagram.t()
  def diagram!(attrs \\ %{}) do
    attrs = Map.merge(%{source: ~s(diagram sequence "Teste"\na -> b : oi)}, attrs)
    {:ok, diagram, _events} = Diagram.create(attrs)
    diagram
  end
end
