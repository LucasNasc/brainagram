# Brainagram: landing page

A página de apresentação do Brainagram. É um site estático, separado do app
Phoenix: quem instala o Brainagram não recebe marketing na própria instância.

A página inteira é um diagrama de sequência. O menu são os participantes, cada
seção é um passo e rolar (ou dar play na barra de baixo) avança no tempo.

## Rodar

Precisa de Node 22 ou mais novo.

```bash
cd site
npm install
npm run dev        # http://localhost:5199
npm run build      # gera site/dist
```

## A URL da demo

O botão principal aponta para a demo pública. Enquanto ela não existir, ele
leva ao README no GitHub e os rótulos dizem isso. Para ligar a demo, defina a
variável no build (veja `.env.example`):

```bash
VITE_DEMO_URL=https://demo.exemplo.com npm run build
```

## Publicar

O workflow `.github/workflows/pages.yml` publica no GitHub Pages a cada push
em `main` que mude algo em `site/`. Para ligar, uma vez só:

1. Settings → Pages → Source: **GitHub Actions**.
2. (Opcional) Settings → Secrets and variables → Actions → Variables:
   `DEMO_URL` com a URL da demo.

`npm run build` gera arquivos estáticos em `site/dist`, com caminhos relativos:
também servem em qualquer outra hospedagem estática (um site estático do
Coolify, Netlify) e em qualquer subcaminho.

## Organização (atomic design)

| Pasta | O que tem |
|---|---|
| `src/components/atoms` | ícone, logo, botões |
| `src/components/molecules` | mensagem (seta com rótulo), participante, bloco de código, barra de tempo, dor |
| `src/components/organisms` | navegação, início, dores, como funciona (mini-player), como usar, fechamento, transporte |
| `src/components/templates` | `SequencePage`: o molde "a página é um diagrama" |
| `src/components/pages` | `Landing` |
| `src/three` | o diagrama em WebGL (react-three-fiber): linhas de vida, setas, impulso, malha de pontos |
| `src/lib` | textos (pt-BR e en), linha do tempo da página, geometria das raias, o fluxo de checkout |
| `src/styles` | tokens (os mesmos do app, tema escuro) e CSS escrito à mão |

Como funciona por dentro:

- `lib/lanes.ts` é a única fonte da posição das raias. O CSS lê `--lane-0` a
  `--lane-4` e o WebGL lê a mesma função.
- `lib/timeline.ts` guarda a posição de cada seta e de cada passo. Muda a cada
  quadro, então fica fora do estado do React.
- Os rótulos das setas são DOM (texto e links de verdade); o canvas só desenha
  linhas e o impulso. Sem WebGL, a página continua legível e navegável.
- O three.js é carregado depois do texto, em um arquivo separado.
- Com "reduzir movimento" ligado no sistema, o play some e ficam os botões de
  passo anterior e próximo.

## Textos

Todos os textos ficam em `src/lib/copy.ts`, em português e inglês. Não invente
números, clientes ou depoimentos: a página só afirma o que o produto faz.

## Imagens

`public/media/checkout.*.gif` são cópias de `docs/images/checkout.*.gif`,
gravadas pelo exportador do próprio Brainagram (`docs/tools/record_gifs.mjs`).
