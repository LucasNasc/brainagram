# Prompt para o Claude Design — Redesign do Brainagram

> Cole tudo abaixo da linha no Claude Design. Anexe junto: `Claude outputs/arch-orto.png`, `Claude outputs/simple-orto.png` e um print do editor atual (tela inteira, tema claro e escuro).

---

## Contexto

Você vai redesenhar o **Brainagram**, uma ferramenta web (PT-BR) para criar **diagramas de engenharia de software animados**. O usuário escreve o fluxo numa linguagem de texto simples, aperta play e vê **mensagens viajando pelas setas, passo a passo**. Hoje existem dois tipos de diagrama: **sequência** e **arquitetura**.

**Posicionamento:** draw.io, Excalidraw, Mermaid e D2 geram imagens paradas. O Brainagram acrescenta o **tempo**: aquele "primeiro acontece isso, depois aquilo…" que alguém explica em voz alta numa reunião passa a ser um artefato que dá para guardar e compartilhar. Usos principais: onboarding de devs, propostas de arquitetura (RFCs), postmortems e apresentações técnicas.

**Público:** devs, tech leads e arquitetos. Também PMs e pessoas não técnicas que só vão *assistir* e *apresentar* os diagramas. O produto precisa ser fácil para quem nunca viu a sintaxe.

### Como funciona hoje (o que já existe)

- **Rotas:** `/` (novo diagrama, abre com um exemplo carregado) e `/d/:slug` (diagrama salvo). Não há home, galeria, lista de "meus diagramas" nem login. Qualquer pessoa com o link pode editar.
- **Layout do editor:** barra superior + 3 colunas (painel **Fonte** com o texto | **canvas** | painel **Timeline** com os passos) + **barra de reprodução** embaixo do canvas.
- **A linguagem (DSL):**
  ```
  diagram sequence "Checkout"
  actor cliente
  service api
  database db
  step "Pedido" {
    cliente -> api : POST /checkout
    api -> db : INSERT pedido
    db --> api : ok
  }
  api ->> fila : publica evento
  api -x pagamento : timeout
  note over api : valida estoque
  group "Dados" { db fila }
  ```
  - Tipos de nó: `actor, participant, service, component, database, queue, external, system, node, boundary`.
  - Setas: `->` chamada síncrona, `-->` retorno, `->>` assíncrona, `-x` falha/timeout.
  - Blocos: `step "…" {}` define um passo da timeline e `group "…" {}` define um agrupamento. Também há notas (`note over/left of/right of`).
- **Layout automático:** o servidor calcula as posições. Não existe posicionamento manual; arrastar nós é roadmap.
- **Animação:** cada seta se desenha em 0,5–0,8 s e um **ponto luminoso** percorre a seta ativa. O nó de destino **pulsa** quando o ponto chega. Estados das setas: pendente (fantasma quase invisível), ativa e concluída (esmaecida). Os nós do passo atual ganham contorno de destaque.
- **Reprodução:** voltar passo, play/pause, avançar passo, reiniciar, loop, barra de progresso (scrubber), tempo "0.0s / 5.2s" e velocidade 0,5×–2×. Atalhos: Espaço, ←/→, F (enquadrar), R (reiniciar).
- **Canvas:** zoom pela rolagem (20%–400%), arrastar para mover, botão "enquadrar", fundo com grade de pontos.
- **Fonte:** textarea monoespaçada que recompila enquanto você digita. Mostra "✓ válido" ou "N erro(s)" com uma lista "L2 mensagem". Tem uma colinha de sintaxe recolhível.
- **Salvar/compartilhar:** "Salvar" gera um link `/d/:slug`. Depois disso, o botão vira "Atualizar". Um badge alterna entre público e privado, e existe "Bifurcar" (duplicar). Quando alguém edita o mesmo diagrama em outro lugar, aparece o aviso "Este diagrama mudou em outro lugar — Recarregar".
- **Exportar:** SVG e PNG (2×) do estado final.

### Roadmap (desenhe como "em breve" ou como estados preparados)

Página pública com embed, exportação em **GIF/MP4**, contas e workspaces, **editor visual** (arrastar nós e ligar setas no canvas, sincronizado com o texto), importar Mermaid/PlantUML, **paleta de comandos ⌘K**, colaboração em tempo real e comentários ancorados em passos.

---

## Problemas atuais que o redesign precisa resolver

1. **Sem identidade.** Logo, favicon, título da aba ("Brainagram · Phoenix Framework") e barra de carregamento ainda são os padrões do Phoenix. A marca é só um "B" num quadrado.
2. **Cor principal inconsistente.** No tema claro os botões são **laranja**, mas o destaque da animação é **violeta**. No escuro, tudo é violeta.
3. **Ícones Unicode** (⏮ ▶ ⏭ ↺ ∞ ⤢) mudam de aparência conforme o sistema operacional e ficam ao lado de botões de texto ("SVG", "PNG").
4. **Compartilhar está espalhado e escondido.** Público/privado é um badge minúsculo que só aparece depois de salvar, "Bifurcar" é jargão e não há botão de copiar link nem de embed.
5. **É fácil perder trabalho.** Escolher um exemplo sobrescreve o texto sem perguntar e não há indicador de alterações não salvas.
6. **Editor de texto fraco.** Não tem números de linha (mesmo com erros apontando "L2"), realce de sintaxe nem autocomplete. A colinha omite os tipos de nó.
7. **Sem estados vazios nem onboarding.** Quem chega não entende que precisa escrever texto e apertar play.
8. **Atalhos invisíveis.** Só aparecem em tooltips.
9. **Legibilidade do canvas** (veja os prints anexados):
   - rótulos de setas se sobrepõem;
   - setas cruzam os títulos dos grupos;
   - setas pendentes (14% de opacidade) e rótulos em cinza claro quase somem;
   - todos os tipos de nó são o mesmo retângulo, diferenciados só por um ícone de 12 px.
10. **Idiomas misturados.** A UI é em PT, mas aparecem "sequence", "Zoom in" e mensagens de erro de conexão em inglês.
11. **Não é responsivo.** Os painéis são fixos e não recolhem, e não há visualização no celular.
12. **O tema claro/escuro não tem botão visível.**
13. **Acessibilidade.** Botões só com ícone não têm rótulo e o passo atual não é anunciado.

---

## O que eu quero de você

### 1. Identidade visual

**Conceito sugerido:** *"o impulso é a marca"*. Brain + diagram: o ponto que viaja pela seta é um **impulso nervoso/sinapse**. A interface é **calma e técnica** (sem neon, sem cara de "dark hacker"), e a **única cor saturada é reservada para o movimento**: o impulso, o passo ativo e as ações principais. Assim o movimento vira a identidade, não decoração.

A pesquisa de mercado mostra três caminhos já ocupados:
- **neon dev escuro:** Arkiio, Glideflow, Eraser;
- **rabisco à mão:** Excalidraw, Excalimate;
- **SaaS pastel lúdico:** FigJam, Whimsical, tldraw.

Quero um quarto caminho: **"calma técnica"**. Quero neutros de grafite e papel com um sinal vivo. Pense em Linear, Vercel/Geist e Raycast, mas com assinatura própria.

Entregue:
- **Logo:** símbolo + logotipo. Uma ideia de partida: dois nós ligados por uma curva que forma um "b", com o ponto de impulso. Quero também uma **versão animada** de 1–2 s para loading e splash, **favicon** (16/32 px legível) e ícone de app.
- **Nome de conceito, tom de voz e microcopy em PT-BR:** direto, técnico sem ser frio. Troque jargões: "Bifurcar" vira "Duplicar", "Fonte" vira "Código".
- **Tipografia:** sugestão Geist (UI) + Geist Mono ou JetBrains Mono (código). Fontes precisam ser open source e empacotáveis.
- **Iconografia:** a base é **Heroicons** (outline 20/24). Desenhe só ícones custom para os tipos de nó, no mesmo traço.

### 2. Paleta de cores

Use esta proposta como ponto de partida. Refine, ajuste contraste e entregue tudo em **OKLCH + hex**, com **tema claro e escuro**:

| Token | Claro | Escuro | Uso |
|---|---|---|---|
| `bg-app` | `#F6F6F3` (papel) | `#111115` (grafite) | fundo da aplicação |
| `bg-canvas` | `#FBFBF9` | `#15151A` | palco do diagrama (grade de pontos sutil) |
| `surface` | `#FFFFFF` | `#1C1C22` | painéis, nós, modais |
| `surface-2` | `#F0F0EC` | `#24242B` | hover, trilhos, inputs |
| `border` | `#E3E3DE` | `#2E2E37` | divisores e bordas |
| `text` | `#16161B` | `#EDEDF2` | texto principal |
| `text-muted` | `#66666F` | `#9C9CAA` | secundário (mínimo 4,5:1) |
| **`brand / impulso`** | `#5B3FE6` | `#8E7CFF` | impulso animado, passo ativo, CTA primário, foco |
| `brand-soft` | `#ECE8FF` | `#2A2450` | fundos de seleção e realce do passo |
| `edge-sync` | `#3A3A48` | `#C9C9D6` | seta síncrona: linha sólida, ponta cheia |
| `edge-return` | `#8A8A96` | `#7C7C8A` | retorno: tracejada, ponta aberta |
| `edge-async` | `#0F8F80` | `#3CCBB6` | assíncrona: pontilhada, ponta aberta |
| `edge-fail` | `#D23F36` | `#FF6A5F` | falha: tracejada + ícone × |
| `note` | `#FFF3BF` / borda `#E9C94A` | `#3A3218` / borda `#8A7430` | notas (post-it) |
| `success / warning / danger / info` | defina | defina | status, validação, toasts |

**Regras da paleta:**
- As setas em repouso são **neutras**. Só a seta **ativa** acende na cor `brand`, com o impulso brilhando. Cada tipo de seta se distingue **também** pelo padrão de traço e pela ponta, nunca só pela cor.
- **Cor por tipo de nó**, baseada no conjunto seguro para daltonismo **Okabe-Ito**, ajustado por tema. A cor aparece como tinta do ícone e numa faixa fina ou no chip do tipo, **não** como preenchimento chapado:
  - actor `#0072B2`
  - service `#56B4E9`
  - database `#009E73`
  - queue `#E69F00`
  - external `#CC79A7`
  - component/system/node neutros
  - boundary/group como contorno tracejado
- **Contraste:** 4,5:1 para texto e 3:1 para bordas, setas, ícones e anel de foco, **nos dois temas**. Setas pendentes precisam continuar legíveis (use no mínimo ~30–35% de opacidade, ou outro tratamento como traço mais fino e cinza).
- Entregue os tokens como **CSS custom properties** prontos para Tailwind v4 (`@theme`), com a mesma nomenclatura nos dois temas.

### 3. Canvas e diagrama

- **Formas distintas por tipo de nó,** além do ícone: ator (figura/pílula), database (cilindro), queue (cápsula com divisões), external (contorno tracejado), service (retângulo arredondado). Precisam funcionar em 68 px de altura (arquitetura) e 44 px (cabeçalho de sequência).
- **Rótulos de seta** com fundo/halo da cor do canvas, sem sobreposição, e com hierarquia clara entre o rótulo ativo e os inativos.
- **Grupos:** título num chip que as setas não atravessam e fundo levíssimo.
- **Estados de animação:** especifique visualmente **pendente, ativa, concluída e foco do passo** (nós fora do passo esmaecidos).
- **Motion spec:** curvas de easing nomeadas (ex.: `impulso` para o ponto viajando, `pulso` para a chegada no nó, `revelar` para notas), durações, brilho do impulso e comportamento com `prefers-reduced-motion` (sem ponto e sem pulso; transições viram cortes/fades curtos).
- **Diagrama de sequência:** lifelines, barras de ativação, bandas numeradas de passo.

### 4. Estrutura e UX do editor

Proposta de layout (melhore se tiver ideia melhor):

- **Barra superior:**
  - logo;
  - título do diagrama, com dica de que vem da 1ª linha do código;
  - indicador **"Salvo / Alterações não salvas / Salvando…"**;
  - **botão "Compartilhar"** único;
  - menu **"Exportar"**;
  - alternância de tema;
  - acesso a atalhos (`?`).
- **Painel Código (esquerda, recolhível):**
  - números de linha, realce de sintaxe e autocomplete de tipos de nó e setas;
  - erro **inline na linha**, com clique para ir até ele;
  - status de validação discreto;
  - "Referência rápida" completa.
- **Canvas (centro):**
  - controles flutuantes de zoom/enquadrar com ícones consistentes;
  - badge do tipo de diagrama ("Sequência" / "Arquitetura").
- **Painel Passos (direita, recolhível):** cards numerados como slides, com passo atual destacado e clique para pular.
- **Player (embaixo):**
  - Heroicons e botão play grande;
  - **scrubber segmentado por passos**, com marcadores clicáveis e rótulo do passo no hover;
  - tempo, velocidade e loop com estado visível.
- **Modal Compartilhar** (unifica o que hoje está espalhado):
  - copiar link;
  - Público/Privado com explicação do que significa;
  - "Duplicar";
  - embed (em breve).
  - Antes de salvar, o próprio botão explica: "Salve para gerar um link".
- **Menu Exportar:**
  - SVG e PNG com prévia;
  - GIF/MP4 "em breve";
  - presets de proporção 16:9 / 1:1 / 9:16.
- **Proteção contra perda:** confirmação ao trocar de exemplo com alterações e toasts de desfazer.
- **Overlay de atalhos** (`?`) e paleta de comandos **⌘K**.
- **Modo apresentação:** tela cheia, ←/→ avançam passos, legenda do passo embaixo, UI escondida.

### 5. Onboarding, vazio e descoberta

- **Estado vazio como ponto de partida:**
  - galeria de modelos (Checkout assíncrono, Arquitetura de plataforma, Login mínimo, Um comando nas camadas) com **miniaturas que animam no hover**;
  - "Começar do zero";
  - "Colar Mermaid" (em breve).
- **Primeira visita:** tour de 3 passos, pulável:
  1. "Escreva o fluxo";
  2. "Aperte play";
  3. "Compartilhe o link".
- **Home / Meus diagramas:** proponha a tela, com recentes locais agora e contas no futuro.

### 6. Estados e responsividade

- Loading com o logo animado, erro de sintaxe, reconexão ("Tentando reconectar…"), "mudou em outro lugar", 404 amigável e toasts.
- **Responsivo:**
  - no desktop, os painéis recolhem;
  - no tablet, o painel Código vira gaveta;
  - no **celular, modo visualizador**: canvas + player + lista de passos, sem edição.

### 7. Acessibilidade

- Anel de foco visível e navegação por teclado entre controles e passos. Siga o modelo do tldraw: Tab percorre os nós em ordem de leitura.
- `aria-label` em todo botão de ícone, `aria-current` no passo ativo e anúncio do passo atual.
- Controle de pausa sempre visível (WCAG 2.2.2) e alternativa textual do diagrama (lista de passos e mensagens).

---

## Referências para se inspirar (não copiar)

- **Eraser.io:** código e canvas lado a lado, sincronizados; `/` para inserir.
- **Mermaid Live / Flowchart Fun:** split texto | render, com erros inline.
- **Jitter / Figma Motion:** animação por **blocos nomeados e presets** em vez de keyframes crus; timeline simples.
- **Excalidraw+ / Motion Canvas:** modo apresentação por passos.
- **Glideflow:** nós tipados com cor e ícone, pacotes viajando pelas setas, embeds que respeitam reduced-motion.
- **Make.com:** bolhas de status nos nós após a execução (inspiração para estados de passo).
- **FigJam / tldraw:** barra de ferramentas mínima e leveza.
- **Linear:** temas gerados em espaço perceptual a partir de base + accent + contraste.
- **Arcade / Storylane:** passos como capítulos, hotspot pulsante.

---

## Restrições técnicas (para o design ser implementável)

- **Stack:** Phoenix LiveView + **Tailwind CSS v4**. Os componentes serão escritos à mão, **sem daisyUI** no novo design. Heroicons estão disponíveis.
- O canvas é **SVG desenhado à mão** (sem React Flow). Tudo do diagrama precisa ser expressável em SVG + CSS variables. A exportação SVG/PNG embute as cores do tema.
- Fontes e assets precisam ser **empacotados no bundle** (sem CDN externo).
- O layout do diagrama é automático. Não conte com posicionamento manual nas telas atuais.

---

## Entregáveis

1. **Moodboard + conceito** da identidade, em 1 página.
2. **Logo:** símbolo, logotipo, versão animada, favicon.
3. **Design system:**
   - tokens de cor (claro/escuro, OKLCH + hex);
   - tipografia, espaçamento, raios, sombras e motion tokens;
   - componentes: botões, inputs, menu, modal, toast, badge, tabs, slider/scrubber, card de passo, tooltip e kbd.
4. **Kit do diagrama:** nós por tipo, 4 tipos de seta, grupo, nota, lifeline, ativação, bandas de passo, cada um nos estados pendente/ativo/concluído, nos dois temas.
5. **Telas (desktop, claro e escuro):**
   1. editor com diagrama de **arquitetura** tocando;
   2. editor com **sequência** e erro de sintaxe;
   3. estado vazio / galeria de modelos;
   4. modal Compartilhar;
   5. menu Exportar;
   6. overlay de atalhos + ⌘K;
   7. modo apresentação;
   8. Home / Meus diagramas;
   9. **visualizador mobile**.
6. **Protótipo navegável** do fluxo: abrir, escolher modelo, editar, dar play, compartilhar.
7. Uma **nota curta de decisões**: por que essa paleta, e como ela resolve cada problema listado acima.
