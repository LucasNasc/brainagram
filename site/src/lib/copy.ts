export type Lang = "pt" | "en";

export interface Pain {
  message: string;
  title: string;
  body: string;
}

export interface Feature {
  term: string;
  body: string;
}

export interface UseStep {
  title: string;
  body: string;
}

export interface Copy {
  htmlLang: string;
  title: string;
  skip: string;
  navLabel: string;
  transportLabel: string;
  stepNames: [string, string, string, string, string];
  lanes: [string, string, string, string, string];
  langSwitch: { label: string; other: string; otherName: string };
  cta: { demo: string; demoRepo: string; install: string; github: string };
  hero: { message: string; messageRepo: string; title: string; lede: string; hint: string };
  pains: { title: string; items: Pain[] };
  how: {
    message: string;
    title: string;
    lede: string;
    source: string;
    diagramLabel: string;
    participants: [string, string, string, string, string];
    steps: [string, string, string];
    lastReply: string;
    features: Feature[];
  };
  use: {
    message: string;
    title: string;
    steps: [UseStep, UseStep, UseStep];
    gifAlt: string;
  };
  closing: { message: string; reply: string; title: string; body: string };
  footer: { license: string; docs: string; contribute: string };
  player: {
    play: string;
    pause: string;
    prev: string;
    next: string;
    playPage: string;
    pausePage: string;
    goTo: string;
    stepOf: string;
    seek: string;
    copy: string;
    copied: string;
    seconds: string;
  };
}

const pt: Copy = {
  htmlLang: "pt-BR",
  title: "Brainagram · Diagramas de software que contam uma história",
  skip: "Pular para o conteúdo",
  navLabel: "Seções da página",
  transportLabel: "Reprodução da página",
  stepNames: ["Início", "As dores", "Como funciona", "Como usar", "Demo"],
  lanes: ["Você", "As dores", "Como funciona", "Como usar", "Demo"],
  langSwitch: { label: "Idioma", other: "EN", otherName: "Read in English" },
  cta: {
    demo: "Abrir a demo",
    demoRepo: "Ver a demo no GitHub",
    install: "Instalar com Docker",
    github: "Código no GitHub",
  },
  hero: {
    message: "abrir a demo",
    messageRepo: "ver a demo no GitHub",
    title: "Diagramas de software que contam uma história.",
    lede: "O Brainagram coloca o tempo dentro do diagrama. As mensagens tocam em ordem, passo a passo, e quem assiste entende o fluxo sem você na sala.",
    hint: "Esta página é um diagrama de sequência. Role para avançar no tempo, ou dê play lá embaixo.",
  },
  pains: {
    title: "Um diagrama parado deixa a história de fora.",
    items: [
      {
        message: "explicar de novo",
        title: "A explicação some quando a reunião acaba.",
        body: "Todo diagrama de sequência é narrado em voz alta: primeiro o cliente chama a API, depois ela publica um evento. Essa narração não fica guardada em lugar nenhum.",
      },
      {
        message: "adivinhar a ordem",
        title: "Uma imagem não diz o que acontece primeiro.",
        body: "draw.io, Excalidraw, Mermaid e D2 entregam uma imagem parada. Quem chega depois precisa reconstruir o passo a passo sozinho.",
      },
      {
        message: "desenho desatualizado",
        title: "O diagrama envelhece longe do código.",
        body: "Desenho feito à mão não passa por revisão. Aqui o diagrama é um arquivo de texto .brain: vive no repositório, aparece no diff do pull request e é renderizado na CI.",
      },
      {
        message: "sintaxe que afasta",
        title: "Quem não escreve código fica sem entender.",
        body: "Gente nova no time, revisores e pessoas de produto não precisam ver a sintaxe. Elas dão play, voltam, avançam e leem os passos.",
      },
    ],
  },
  how: {
    message: "e se o diagrama tocasse?",
    title: "No Brainagram, o tempo faz parte do diagrama.",
    lede: "As mensagens são agrupadas em passos e tocadas em ordem, com um impulso percorrendo cada seta. O texto é a única fonte: o que toca ao lado é exatamente o que está escrito.",
    source: "checkout.brain",
    diagramLabel: "Diagrama de sequência do checkout, tocando passo a passo",
    participants: ["Cliente", "API Gateway", "Order Service", "PostgreSQL", "RabbitMQ"],
    steps: ["Cliente confirma o pedido", "Pedido gravado", "Resposta rápida"],
    lastReply: "Pedido recebido!",
    features: [
      {
        term: "O texto é o diagrama",
        body: "Arrastar, conectar e renomear no canvas reescrevem o texto. Nada existe só na tela.",
      },
      {
        term: "Sequência e arquitetura",
        body: "Raias, notas e payloads de um lado; grupos e setas ortogonais que evitam cruzamentos do outro.",
      },
      {
        term: "Entra e sai sem prender",
        body: "Importa Mermaid e PlantUML. Exporta SVG, PNG, GIF animado e o próprio arquivo .brain.",
      },
      {
        term: "Sete idiomas, dois temas",
        body: "Interface em português, inglês, chinês, russo, italiano, japonês e hindi, clara ou escura.",
      },
    ],
  },
  use: {
    message: "docker compose up -d",
    title: "Do zero ao primeiro play em três passos.",
    steps: [
      {
        title: "Suba a sua instância",
        body: "Um container roda tudo, com o banco incluído. Preencha SECRET_KEY_BASE no .env; para usar um PostgreSQL seu, defina também DATABASE_URL.",
      },
      {
        title: "Escreva o fluxo",
        body: "Declare os participantes e agrupe as mensagens em passos. Se preferir, desenhe no canvas: o texto acompanha cada gesto.",
      },
      {
        title: "Dê play e compartilhe",
        body: "O link do diagrama abre direto na apresentação: o diagrama, o player e os passos. Para slides e conversas, exporte um GIF como este.",
      },
    ],
    gifAlt: "Gravação do Brainagram tocando o diagrama de checkout, com o impulso percorrendo cada seta",
  },
  closing: {
    message: "dar play",
    reply: "sua vez",
    title: "Aperte o play no seu próprio sistema.",
    body: "Código aberto, licença MIT, feito para rodar na sua infraestrutura.",
  },
  footer: {
    license: "Brainagram é software livre sob a licença MIT.",
    docs: "Documentação",
    contribute: "Como contribuir",
  },
  player: {
    play: "Tocar",
    pause: "Pausar",
    prev: "Passo anterior",
    next: "Próximo passo",
    playPage: "Tocar a página",
    pausePage: "Pausar a página",
    goTo: "Ir para",
    stepOf: "de",
    seek: "Posição no diagrama",
    copy: "Copiar",
    copied: "Copiado",
    seconds: "s",
  },
};

const en: Copy = {
  htmlLang: "en",
  title: "Brainagram · Software diagrams that tell a story",
  skip: "Skip to content",
  navLabel: "Page sections",
  transportLabel: "Page playback",
  stepNames: ["Start", "The pains", "How it works", "How to use", "Demo"],
  lanes: ["You", "The pains", "How it works", "How to use", "Demo"],
  langSwitch: { label: "Language", other: "PT", otherName: "Ler em português" },
  cta: {
    demo: "Open the demo",
    demoRepo: "See the demo on GitHub",
    install: "Install with Docker",
    github: "Code on GitHub",
  },
  hero: {
    message: "open the demo",
    messageRepo: "see the demo on GitHub",
    title: "Software diagrams that tell a story.",
    lede: "Brainagram puts time inside the diagram. Messages play in order, step by step, and whoever watches understands the flow without you in the room.",
    hint: "This page is a sequence diagram. Scroll to move through time, or press play down below.",
  },
  pains: {
    title: "A still diagram leaves the story out.",
    items: [
      {
        message: "explain it again",
        title: "The explanation is gone when the meeting ends.",
        body: "Every sequence diagram gets narrated out loud: first the client calls the API, then it publishes an event. That narration is stored nowhere.",
      },
      {
        message: "guess the order",
        title: "A picture doesn't say what happens first.",
        body: "draw.io, Excalidraw, Mermaid and D2 produce a still image. Whoever arrives later has to rebuild the step-by-step alone.",
      },
      {
        message: "outdated drawing",
        title: "The diagram ages away from the code.",
        body: "A hand-made drawing skips review. Here the diagram is a .brain text file: it lives in the repository, shows up in the pull request diff and renders in CI.",
      },
      {
        message: "syntax in the way",
        title: "People who don't write code are left out.",
        body: "New teammates, reviewers and product people never need to see the syntax. They press play, go back, go forward and read the steps.",
      },
    ],
  },
  how: {
    message: "what if the diagram played?",
    title: "In Brainagram, time is part of the diagram.",
    lede: "Messages are grouped into steps and played in order, with an impulse traveling along each arrow. The text is the only source: what plays next to it is exactly what is written.",
    source: "checkout.brain",
    diagramLabel: "Checkout sequence diagram, playing step by step",
    participants: ["Customer", "API Gateway", "Order Service", "PostgreSQL", "RabbitMQ"],
    steps: ["Customer places the order", "Order is stored", "Fast response"],
    lastReply: "Order received!",
    features: [
      {
        term: "The text is the diagram",
        body: "Dragging, connecting and renaming on the canvas rewrite the text. Nothing exists only on screen.",
      },
      {
        term: "Sequence and architecture",
        body: "Lanes, notes and payloads on one side; groups and orthogonal arrows that avoid crossings on the other.",
      },
      {
        term: "In and out, no lock-in",
        body: "Imports Mermaid and PlantUML. Exports SVG, PNG, animated GIF and the .brain file itself.",
      },
      {
        term: "Seven languages, two themes",
        body: "UI in Portuguese, English, Chinese, Russian, Italian, Japanese and Hindi, light or dark.",
      },
    ],
  },
  use: {
    message: "docker compose up -d",
    title: "From zero to the first play in three steps.",
    steps: [
      {
        title: "Start your instance",
        body: "One container runs everything, database included. Fill in SECRET_KEY_BASE in .env; to use your own PostgreSQL, set DATABASE_URL too.",
      },
      {
        title: "Write the flow",
        body: "Declare the participants and group the messages into steps. Or draw on the canvas: the text follows every gesture.",
      },
      {
        title: "Press play and share",
        body: "The diagram link opens straight into presentation: the diagram, the player and the steps. For slides and chats, export a GIF like this one.",
      },
    ],
    gifAlt: "Recording of Brainagram playing the checkout diagram, with the impulse traveling along each arrow",
  },
  closing: {
    message: "press play",
    reply: "your turn",
    title: "Press play on your own system.",
    body: "Open source, MIT licensed, made to run on your infrastructure.",
  },
  footer: {
    license: "Brainagram is free software under the MIT license.",
    docs: "Documentation",
    contribute: "How to contribute",
  },
  player: {
    play: "Play",
    pause: "Pause",
    prev: "Previous step",
    next: "Next step",
    playPage: "Play the page",
    pausePage: "Pause the page",
    goTo: "Go to",
    stepOf: "of",
    seek: "Position in the diagram",
    copy: "Copy",
    copied: "Copied",
    seconds: "s",
  },
};

export const COPY: Record<Lang, Copy> = { pt, en };

/** O exemplo de checkout: o texto mostrado é o mesmo que o diagrama toca. */
export function checkoutSource(c: Copy): string[] {
  const [user, api, orders, db, mq] = c.how.participants;
  const [s1, s2, s3] = c.how.steps;
  return [
    `diagram sequence "Checkout"`,
    ``,
    `actor       user   "${user}"`,
    `participant api    "${api}"`,
    `service     orders "${orders}"`,
    `database    db     "${db}"`,
    `queue       mq     "${mq}"`,
    ``,
    `step "${s1}" {`,
    `  user -> api : POST /orders`,
    `  api -> orders : CreateOrder`,
    `}`,
    ``,
    `step "${s2}" {`,
    `  orders -> db : INSERT order`,
    `  db --> orders : order_id`,
    `}`,
    ``,
    `step "${s3}" {`,
    `  orders ->> mq : OrderCreated`,
    `  orders --> api : 201 Created`,
    `  api --> user : "${c.how.lastReply}"`,
    `}`,
  ];
}
