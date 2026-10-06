// Exportar GIF animado: grava a animação inteira, do primeiro ao último passo.
//
// A timeline é uma função pura do tempo (`seek(t)` desenha o instante exato),
// então gravar é só percorrer `t` em passos fixos, fotografar o SVG em cada
// um e entregar os quadros ao encoder. Nada de gravar a tela: o resultado é
// igual em qualquer máquina e não depende de quanto tempo cada quadro levou.

import { toSvgString, svgStyleText, triggerDownload } from "./export";
import { Palette, GifWriter } from "./gif";

// Duas qualidades. HD grava em 2× (texto nítido em tela retina e em slide),
// limitado por um orçamento de pixels por quadro — acima disso o tempo de
// gravação e o arquivo crescem sem ganho visível. Leve é para chat com limite
// de tamanho: 1×, no máximo 960 px de largura.
const QUALITY = {
  hd: { maxScale: 2, maxWidth: 2400, maxHeight: 3000, maxPixels: 4_200_000, fps: 12, maxFrames: 360 },
  light: { maxScale: 1, maxWidth: 960, maxHeight: 1400, maxPixels: 1_400_000, fps: 12, maxFrames: 300 },
};
const PALETTE_SAMPLES = 16;
const FINAL_HOLD_MS = 1800;

export class GifCancelled extends Error {}

// Escala do quadro: a maior até `maxScale` que caiba em largura, altura e
// orçamento de pixels.
export function gifScale(scene, quality = "hd") {
  const q = QUALITY[quality] || QUALITY.hd;
  return Math.min(
    q.maxScale,
    q.maxWidth / scene.width,
    q.maxHeight / scene.height,
    Math.sqrt(q.maxPixels / (scene.width * scene.height)),
  );
}

// opts: { svg, scene, timeline, quality ("hd" | "light"), onProgress(0..1), isCancelled() }
export async function recordGif({ svg, scene, timeline, quality = "hd", onProgress = () => {}, isCancelled = () => false }) {
  const q = QUALITY[quality] || QUALITY.hd;
  const scale = gifScale(scene, quality);
  const width = Math.max(1, Math.round(scene.width * scale));
  const height = Math.max(1, Math.round(scene.height * scale));

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  // o SVG é vetor: desenhado já no tamanho final, sai nítido (sem reamostrar)
  ctx.imageSmoothingQuality = "high";
  const background = getComputedStyle(document.documentElement).getPropertyValue("--bg-canvas").trim() || "#fbfbf9";
  const style = svgStyleText();

  // Diagramas longos baixam a taxa de quadros em vez de virar um arquivo enorme.
  const total = timeline.total;
  let frameMs = 1000 / q.fps;
  if (total / frameMs + 1 > q.maxFrames) frameMs = total / (q.maxFrames - 1);
  const count = Math.floor(total / frameMs) + 1;
  const times = Array.from({ length: count }, (_, i) => Math.min(i * frameMs, total));

  // A reprodução da pessoa não pode ser afetada: pausa, grava e devolve tudo como estava.
  const saved = { t: timeline.t, playing: timeline.playing, reduced: timeline.reduced };
  timeline.pause();
  // o arquivo é para compartilhar: leva o impulso mesmo com movimento reduzido na tela
  timeline.reduced = false;

  const capture = async (t) => {
    if (isCancelled()) throw new GifCancelled();
    timeline.seek(t);
    const source = toSvgString(svg, scene, { final: false, style });
    const url = URL.createObjectURL(new Blob([source], { type: "image/svg+xml;charset=utf-8" }));
    try {
      const img = new Image();
      img.src = url;
      await img.decode();
      ctx.fillStyle = background;
      ctx.fillRect(0, 0, width, height);
      ctx.drawImage(img, 0, 0, width, height);
      return ctx.getImageData(0, 0, width, height).data;
    } finally {
      URL.revokeObjectURL(url);
    }
  };

  try {
    // 1ª passada: amostras espalhadas pela animação montam a paleta global
    const palette = new Palette();
    for (let i = 0; i < PALETTE_SAMPLES; i++) {
      palette.sample(await capture((total * i) / (PALETTE_SAMPLES - 1)));
      onProgress((0.15 * (i + 1)) / PALETTE_SAMPLES);
    }
    palette.build();

    // 2ª passada: os quadros
    const writer = new GifWriter(width, height, palette);
    for (let i = 0; i < times.length; i++) {
      writer.addFrame(palette.index(await capture(times[i])), frameMs);
      // o `await` do decode de cada quadro já devolve a vez ao navegador, então o
      // progresso aparece sem pausa extra (setTimeout é estrangulado em aba oculta)
      onProgress(0.15 + (0.85 * (i + 1)) / times.length);
    }

    return { blob: writer.finish(FINAL_HOLD_MS), width, height, frames: writer.frames };
  } finally {
    timeline.reduced = saved.reduced;
    timeline.seek(saved.t);
    if (saved.playing) timeline.play();
  }
}

export async function downloadGif(opts, filename) {
  const result = await recordGif(opts);
  triggerDownload(URL.createObjectURL(result.blob), filename, true);
  return result;
}
