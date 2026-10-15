// Espelho dos tokens escuros de styles/tokens.css, para o WebGL.
export const COLOR = {
  bg: "#111115",
  brand: "#8e7cff",
  brandSoft: "#2a2450",
  lifeline: "#3d3d49",
  dot: "#2c2c35",
  dotLit: "#8e7cff",
  sync: "#c9c9d6",
  return: "#8a8a98",
  async: "#3ccbb6",
  fail: "#ff6a5f",
  pending: "#666674",
} as const;

export type EdgeKind = "sync" | "return" | "async" | "fail";

/** Traço de cada tipo de seta: [traço, espaço] em px; 0 = contínuo. */
export const DASH: Record<EdgeKind, [number, number]> = {
  sync: [0, 0],
  return: [6, 4],
  async: [2, 5],
  fail: [6, 4],
};
