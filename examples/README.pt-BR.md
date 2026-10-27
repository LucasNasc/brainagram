# Exemplos

[English](README.md) · **Português (Brasil)**

Diagramas prontos para usar: abra o editor do Brainagram, escolha **Abrir →
Importar** (ou cole o texto) e dê play. Cada arquivo `.brain` tem um `.svg` ao
lado com o estado final, gerado pelo `mix brainagram.render`.

## Diagramas de sequência

| Arquivo | O que mostra |
|---|---|
| [`sequence/oauth-sign-in.brain`](sequence/oauth-sign-in.brain) | **Sem payload.** Login com um provedor de identidade, em três passos: chamadas, retornos e uma nota. |
| [`sequence/card-payment-with-payloads.brain`](sequence/card-payment-with-payloads.brain) | **Com payload.** Um pagamento com cartão em que o gateway estoura o tempo (`-x`), uma nova tentativa, e depois o registro e um evento. Payloads de JSON, cabeçalho e SQL, em uma linha e em várias. |

<p>
  <img src="sequence/oauth-sign-in.svg" alt="Diagrama de sequência: login com OAuth" width="49%">
  <img src="sequence/card-payment-with-payloads.svg" alt="Diagrama de sequência: pagamento com cartão e gateway falhando" width="49%">
</p>

## Diagramas de arquitetura

| Arquivo | O que mostra |
|---|---|
| [`architecture/url-shortener.brain`](architecture/url-shortener.brain) | **Sem payload.** Grupos (borda, serviços, dados) e dois fluxos: criar e seguir um link curto. |
| [`architecture/order-approval.brain`](architecture/order-approval.brain) | **Fluxo de decisão.** Losangos `decision` com a pergunta dentro, setas `yes` / `no` saindo por pontas diferentes, da esquerda para a direita (`direction horizontal`). |
| [`architecture/event-driven-orders.brain`](architecture/event-driven-orders.brain) | **Com payload.** Eventos assíncronos (`->>`) passando pelo Kafka, com o corpo do evento, um UPDATE em SQL e um pedido de e-mail. |

<p>
  <img src="architecture/url-shortener.svg" alt="Diagrama de arquitetura: encurtador de links" width="49%">
  <img src="architecture/event-driven-orders.svg" alt="Diagrama de arquitetura: pedidos orientados a eventos" width="49%">
</p>

## Vindo do Mermaid ou do PlantUML

O Brainagram **importa** Mermaid e PlantUML, então os diagramas que você já tem
não precisam ser reescritos. Cole o arquivo num diálogo de importação e você
recebe o texto `.brain`, pronto para tocar. O que não converte vira comentário
no topo do código; a importação nunca falha por causa de uma linha
desconhecida.

| Origem | Vira | Resultado convertido |
|---|---|---|
| [`import/mermaid/password-reset.mmd`](import/mermaid/password-reset.mmd) (Mermaid `sequenceDiagram`) | sequência | [`password-reset.brain`](import/mermaid/password-reset.brain) |
| [`import/mermaid/order-pipeline.mmd`](import/mermaid/order-pipeline.mmd) (Mermaid `flowchart`) | arquitetura | [`order-pipeline.brain`](import/mermaid/order-pipeline.brain) |
| [`import/plantuml/file-upload.puml`](import/plantuml/file-upload.puml) (sequência do PlantUML) | sequência | [`file-upload.brain`](import/plantuml/file-upload.brain) |
| [`import/plantuml/analytics-components.puml`](import/plantuml/analytics-components.puml) (componentes do PlantUML) | arquitetura | [`analytics-components.brain`](import/plantuml/analytics-components.brain) |

O que converte:

- **Mermaid `sequenceDiagram`:** participantes e atores (com `as`), `box` como
  grupo, setas síncronas, de retorno, assíncronas e de falha, notas, `title` e
  `alt`/`else`/`opt`/`loop`/`critical`/`break` como passos. `par`, `rect` e
  setas bidirecionais ficam registrados no comentário; as mensagens são
  mantidas.
- **Mermaid `flowchart` / `graph`:** vira arquitetura. Todas as formas de nó
  convertem; o cilindro (`[( )]`) é banco, e os outros tipos vêm do nome da
  classe (`classDef queue …`, `class X ext`, `X:::store`) ou do rótulo ("fila",
  "Redis", "clientes"…). `subgraph` vira grupo, `-.->` seta assíncrona, `--x`
  falha, e cadeias (`A --> B --> C`) e leques (`A & B --> C`) viram uma seta
  cada. Ligações sem ponta, de mão dupla e para um subgraph ficam registradas
  no comentário.
- **Sequência do PlantUML:** `participant`, `actor`, `database`, `queue` e os
  outros tipos de participante, `box` como grupo, `->`, `-->`, `->>`, `->x`,
  setas invertidas, notas, `title`, `== seção ==` e
  `alt`/`else`/`opt`/`loop`/`group` como passos.
- **Componentes (ou implantação) do PlantUML:** `[Componente]`, `component`,
  `database`, `queue`, `actor`, `cloud`, `node`… e contêineres como `package`,
  `node` ou `cloud` viram grupos; `..>` vira seta assíncrona.

## Renderizar ou conferir pela linha de comando

```bash
mix brainagram.render examples/sequence/oauth-sign-in.brain         # → .svg ao lado
mix brainagram.fmt --check-formatted examples/**/*.brain             # formatação canônica, para a CI
```

Os diagramas dos GIFs do README ficam em [`../docs/examples/`](../docs/examples).
