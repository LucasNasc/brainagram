/** A partir desta largura a marca cabe ao lado do primeiro participante. */
export const FULL_FROM = 1240;
/** Abaixo desta largura a página usa duas linhas de vida, nas bordas. */
export const COMPACT_BELOW = 820;
export const LANE_COUNT = 5;

/** Posição x (px) de cada raia. É a única fonte: CSS e WebGL leem daqui. */
export function laneXs(width: number): number[] {
  if (width < COMPACT_BELOW) {
    const left = 22;
    const right = width - 22;
    return [left, right, right, right, right];
  }
  const pad = width < FULL_FROM ? 132 : Math.min(280, Math.max(228, width * 0.15));
  const gap = (width - 2 * pad) / (LANE_COUNT - 1);
  return Array.from({ length: LANE_COUNT }, (_, i) => pad + i * gap);
}

export function isCompact(width: number): boolean {
  return width < COMPACT_BELOW;
}

/** Faixa intermediária: os cinco participantes cabem, a marca vira só o símbolo. */
export function isMid(width: number): boolean {
  return width >= COMPACT_BELOW && width < FULL_FROM;
}

/**
 * As pontas de uma seta. No modo compacto só há duas linhas de vida, então
 * toda mensagem cruza a tela: para a direita se avança de raia, para a
 * esquerda se volta.
 */
export function arrowEnds(width: number, from: number, to: number): [number, number] {
  const xs = laneXs(width);
  if (!isCompact(width)) return [xs[from], xs[to]];
  return to > from ? [xs[0], xs[1]] : [xs[1], xs[0]];
}
