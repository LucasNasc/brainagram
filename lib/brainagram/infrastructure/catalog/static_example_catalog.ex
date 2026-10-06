defmodule Brainagram.Infrastructure.Catalog.StaticExampleCatalog do
  @moduledoc """
  Catálogo de exemplos embutido no binário.

  É infraestrutura, não domínio: conteúdo editorial que por acaso está em
  código. Está atrás de uma porta porque o destino provável é o banco —
  exemplos curados, ou os diagramas públicos mais bifurcados.
  """

  @behaviour Brainagram.Application.Ports.ExampleCatalog

  alias Brainagram.Application.ReadModels.Example

  @checkout """
  diagram sequence "Checkout com pagamento assíncrono"

  actor        user "Cliente"
  participant  web  "Web App"
  participant  api  "API Gateway"
  service      orders "Order Service"
  database     db   "PostgreSQL"
  queue        mq   "RabbitMQ"
  external     psp  "Gateway de Pagamento"

  step "Cliente confirma o pedido" {
    user -> web : clica em Pagar
    web  -> api : POST /orders
  }

  step "API valida e persiste" {
    api -> orders : CreateOrder
    orders -> orders : valida estoque
    orders -> db : INSERT order (pending)
    db --> orders : order_id
  }

  step "Resposta rápida ao cliente" {
    orders ->> mq : OrderCreated
    orders --> api : 201 Created
    api --> web : 201 Created
    web --> user : "Pedido recebido!"
    note over user, web : a UI já responde aqui — o resto é assíncrono
  }

  step "Cobrança em background" {
    mq -> orders : consome OrderCreated
    orders -> psp : POST /charges
    psp --> orders : approved
    orders -> db : UPDATE order = paid
  }

  step "Caminho triste" {
    psp -x orders : timeout
    orders ->> mq : OrderPaymentFailed
  }
  """

  @architecture """
  diagram architecture "Plataforma — visão de alto nível"

  group "Edge" {
    node cdn "Cloudflare CDN"
    node lb  "Load Balancer"
  }

  group "Aplicação" {
    service api    "API (Phoenix)"
    service worker "Worker (Oban)"
  }

  group "Dados" {
    database pg    "PostgreSQL"
    database redis "Redis"
    queue    mq    "RabbitMQ"
  }

  external s3 "Object Storage"

  step "Tráfego de entrada" {
    cdn -> lb  : HTTPS
    lb  -> api : round-robin
  }

  step "Leitura e cache" {
    api -> redis : GET sessão
    api -> pg    : SELECT
  }

  step "Trabalho assíncrono" {
    api    ->> mq     : publica evento
    mq     -> worker  : consome
    worker -> pg      : UPDATE
    worker -> s3      : upload de relatório
  }
  """

  @cqrs """
  diagram sequence "Um comando atravessando as camadas"

  actor       user   "Usuário"
  participant live   "LiveView"
  participant bus    "Application.Bus"
  participant handler "Handler"
  participant agg    "Diagram (agregado)"
  participant repo   "EctoDiagramRepository"
  queue       pubsub "PubSub"

  step "A intenção chega" {
    user -> live : salvar
    live -> bus  : dispatch(ChangeDiagramSource)
    bus -> bus   : valida o comando
  }

  step "A regra decide" {
    bus -> handler : handle(comando)
    handler -> repo : fetch_by_slug
    repo --> handler : agregado
    handler -> agg : change_source
    agg --> handler : {agregado, eventos}
  }

  step "Persiste e só então publica" {
    handler -> repo : update
    repo --> handler : ok
    handler --> bus : {:ok, resultado, eventos}
    bus ->> pubsub : publica eventos
    note over bus, pubsub : eventos só saem depois da escrita confirmada
  }
  """

  @minimal """
  diagram sequence "Login"

  user -> app : credenciais
  app -> auth : valida
  auth --> app : token
  app --> user : sessão iniciada
  """

  # Blocos `payload """` dentro: por isso ~S''' e não """.
  @payloads ~S'''
  diagram sequence "Checkout — o que cada mensagem carrega"

  actor    user   "Cliente"
  participant api "API Gateway"
  service  orders "Order Service"
  database db     "PostgreSQL"
  queue    mq     "RabbitMQ"
  external psp    "Gateway de Pagamento"

  step "Cliente envia o pedido" {
    user -> api : POST /orders
      payload """
      {
        "customer_id": "c-123",
        "items": [
          {"sku": "A-1", "qty": 2, "price": 89.95},
          {"sku": "B-7", "qty": 1, "price": 20.00}
        ],
        "coupon": "BLACK10"
      }
      """
    api -> orders : CreateOrder
      payload: Authorization: Bearer eyJhbGciOiJIUzI1NiJ9…
  }

  step "Pedido gravado" {
    orders -> db : INSERT order
      payload """
      INSERT INTO orders (id, customer_id, total, status)
      VALUES ($1, $2, 179.91, 'pending')
      RETURNING id
      """
    db --> orders : order_id
      payload: {"id": "ord_42"}
    orders ->> mq : OrderCreated
      payload """
      {
        "event": "order.created",
        "order_id": "ord_42",
        "total": 179.91
      }
      """
    orders --> api : 201 Created
      payload: {"id": "ord_42", "status": "pending"}
    api --> user : pedido recebido
  }

  step "Pagamento confirmado" {
    psp -> api : POST /webhooks/payment
      payload """
      {
        "type": "payment.approved",
        "order_id": "ord_42",
        "amount": 179.91,
        "signature": "t=1727...,v1=5f2b…"
      }
      """
    api -> orders : MarkAsPaid
    orders -> db : UPDATE orders SET status
      payload: UPDATE orders SET status = 'paid' WHERE id = 'ord_42'
    api --> psp : 200 OK
  }
  '''

  @examples [
    %Example{slug: "checkout", name: "Sequência — Checkout", source: @checkout},
    %Example{slug: "payloads", name: "Sequência — Checkout com payloads", source: @payloads},
    %Example{slug: "arquitetura", name: "Arquitetura — Plataforma", source: @architecture},
    %Example{slug: "cqrs", name: "Sequência — Um comando nas camadas", source: @cqrs},
    %Example{slug: "minimo", name: "Mínimo — Login", source: @minimal}
  ]

  @impl true
  def all, do: @examples

  @impl true
  def fetch(slug) do
    case Enum.find(@examples, &(&1.slug == slug)) do
      nil -> {:error, :not_found}
      example -> {:ok, example}
    end
  end

  @impl true
  def default_source, do: @checkout
end
