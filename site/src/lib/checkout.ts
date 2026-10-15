import type { EdgeKind } from "./tokens";

/** O fluxo de checkout tocado na seção "Como funciona". */
export interface FlowMsg {
  from: number;
  to: number;
  kind: EdgeKind;
  label: string;
  step: number;
  /** Linha (base 0) em checkoutSource() que declara esta mensagem. */
  line: number;
}

export function checkoutFlow(lastReply: string): FlowMsg[] {
  return [
    { from: 0, to: 1, kind: "sync", label: "POST /orders", step: 0, line: 9 },
    { from: 1, to: 2, kind: "sync", label: "CreateOrder", step: 0, line: 10 },
    { from: 2, to: 3, kind: "sync", label: "INSERT order", step: 1, line: 14 },
    { from: 3, to: 2, kind: "return", label: "order_id", step: 1, line: 15 },
    { from: 2, to: 4, kind: "async", label: "OrderCreated", step: 2, line: 19 },
    { from: 2, to: 1, kind: "return", label: "201 Created", step: 2, line: 20 },
    { from: 1, to: 0, kind: "return", label: lastReply, step: 2, line: 21 },
  ];
}

/** O tipo de cada participante, na ordem em que o texto os declara. */
export const FLOW_KINDS = ["actor", "participant", "service", "database", "queue"] as const;

/** Segundos que cada mensagem leva, e o intervalo até a próxima. */
export const TRAVEL = 1.15;
export const SLOT = 1.5;
export const FLOW_LENGTH = 7;
export const TOTAL = FLOW_LENGTH * SLOT;
export const STEP_SIZES = [2, 2, 3];

/** Geometria do mini-diagrama, compartilhada entre o WebGL e os rótulos. */
export function flowLayout(width: number, height: number) {
  const pad = width < 520 ? 34 : Math.max(40, width * 0.095);
  const xs = Array.from({ length: 5 }, (_, i) => pad + (i * (width - 2 * pad)) / 4);
  const first = 104;
  const row = (height - first - 30) / (FLOW_LENGTH - 1);
  const ys = Array.from({ length: FLOW_LENGTH }, (_, i) => first + i * row);
  return { xs, ys, row, headerBottom: width < 520 ? 62 : 58 };
}

type Listener = () => void;

/** O relógio do mini-player. Vive fora do React: muda a cada quadro. */
export class FlowClock {
  t = 0;
  playing = false;
  private listeners = new Set<Listener>();

  subscribe = (fn: Listener) => {
    this.listeners.add(fn);
    return () => {
      this.listeners.delete(fn);
    };
  };

  private emit() {
    for (const fn of this.listeners) fn();
  }

  advance(delta: number) {
    if (!this.playing) return;
    this.t = Math.min(TOTAL, this.t + delta);
    if (this.t >= TOTAL) this.playing = false;
    this.emit();
  }

  play() {
    if (this.t >= TOTAL) this.t = 0;
    this.playing = true;
    this.emit();
  }

  pause() {
    this.playing = false;
    this.emit();
  }

  toggle() {
    if (this.playing) this.pause();
    else this.play();
  }

  seek(t: number) {
    this.t = Math.max(0, Math.min(TOTAL, t));
    this.emit();
  }

  /** Vai para o início da mensagem vizinha (para ←/→ e para movimento reduzido). */
  stepBy(direction: 1 | -1) {
    const index = Math.floor(this.t / SLOT - 1e-6);
    const next = direction === 1 ? index + 1 : this.t > index * SLOT + 0.05 ? index : index - 1;
    this.playing = false;
    this.seek(Math.max(0, Math.min(FLOW_LENGTH, next)) * SLOT);
  }

  progressOf(index: number): number {
    const p = (this.t - index * SLOT) / TRAVEL;
    return p < 0 ? 0 : p > 1 ? 1 : p;
  }

  /** Índice da mensagem atual; -1 antes de começar. */
  get index(): number {
    if (this.t <= 0) return -1;
    return Math.min(FLOW_LENGTH - 1, Math.floor(this.t / SLOT - 1e-6));
  }
}
