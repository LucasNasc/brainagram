import { clamp01, easeOutExpo, prefersReducedMotion } from "./motion";
import type { EdgeKind } from "./tokens";

/**
 * A linha do tempo da página: rolar é avançar no tempo.
 *
 * Cada <Message> registra uma seta (de qual raia para qual, e onde fica no
 * documento) e cada <StepSection> registra um passo. O WebGL e a barra de
 * transporte leem daqui; nada disso passa pelo estado do React, porque muda a
 * cada quadro.
 */
export type MsgState = "pending" | "active" | "done";

export interface Msg {
  el: HTMLElement;
  from: number;
  to: number;
  kind: EdgeKind;
  /** y da linha da seta no documento (px). */
  y: number;
  /** Metade da faixa de rolagem em que esta seta toca. */
  win: number;
  /** Uma seta do futuro: fica pendente, nunca toca. */
  hold: boolean;
  state: MsgState;
}

export interface Step {
  el: HTMLElement;
  id: string;
  top: number;
  bottom: number;
}

/** A seta toca enquanto cruza esta faixa (no máximo) em torno da linha de leitura. */
const WINDOW = 150;
/** Fração da altura da janela onde fica a linha de leitura. */
const READING_LINE = 0.56;
const INTRO_MS = 1700;
const INTRO_OFFSET = 620;

type Listener = () => void;

class Timeline {
  msgs: Msg[] = [];
  steps: Step[] = [];
  private listeners = new Set<Listener>();
  private introStart = 0;
  private introDone = false;
  private frame = 0;

  addMessage(el: HTMLElement, from: number, to: number, kind: EdgeKind, hold = false) {
    this.msgs.push({ el, from, to, kind, y: 0, win: WINDOW, hold, state: "pending" });
    this.schedule();
    return () => {
      this.msgs = this.msgs.filter((m) => m.el !== el);
    };
  }

  addStep(el: HTMLElement, id: string) {
    this.steps.push({ el, id, top: 0, bottom: 0 });
    this.schedule();
    return () => {
      this.steps = this.steps.filter((s) => s.el !== el);
    };
  }

  /** Relê as posições do DOM. Chamado em resize, fontes e mudança de layout. */
  measure = () => {
    const sy = window.scrollY;
    for (const m of this.msgs) {
      const r = m.el.getBoundingClientRect();
      m.y = r.top + sy + r.height / 2;
    }
    this.msgs.sort((a, b) => a.y - b.y);
    // Vizinhas próximas dividem o espaço: nunca há duas setas tocando.
    this.msgs.forEach((m, i) => {
      const prev = this.msgs[i - 1];
      const next = this.msgs[i + 1];
      const room = Math.min(prev ? m.y - prev.y : Infinity, next ? next.y - m.y : Infinity);
      m.win = Math.max(24, Math.min(WINDOW, room / 2));
    });
    for (const s of this.steps) {
      const r = s.el.getBoundingClientRect();
      s.top = r.top + sy;
      s.bottom = r.bottom + sy;
    }
    this.steps.sort((a, b) => a.top - b.top);
    this.sync();
    this.emit();
  };

  private schedule() {
    cancelAnimationFrame(this.frame);
    this.frame = requestAnimationFrame(this.measure);
  }

  subscribe(fn: Listener) {
    this.listeners.add(fn);
    return () => {
      this.listeners.delete(fn);
    };
  }

  emit = () => {
    for (const fn of this.listeners) fn();
  };

  /** A entrada: a linha de leitura desce até o lugar, e a primeira seta toca. */
  startIntro() {
    this.introStart = performance.now();
    this.introDone = prefersReducedMotion();
  }

  get introRunning() {
    return !this.introDone;
  }

  /** y da linha de leitura no documento. */
  playhead(now = performance.now()): number {
    let lag = 0;
    if (!this.introDone) {
      const t = clamp01((now - this.introStart) / INTRO_MS);
      lag = (1 - easeOutExpo(t)) * INTRO_OFFSET;
      if (t >= 1) this.introDone = true;
    }
    const max = document.documentElement.scrollHeight - window.innerHeight;
    // No fim da página a linha de leitura desce até o rodapé, para a última
    // seta também terminar.
    const end = max > 0 ? clamp01((window.scrollY - (max - 240)) / 240) : 0;
    const line = READING_LINE + (1 - READING_LINE) * end;
    return window.scrollY + window.innerHeight * line - lag;
  }

  /** Progresso (0..1) de uma seta para uma dada linha de leitura. */
  progressOf(m: Msg, playhead: number): number {
    if (m.hold) return 0;
    return clamp01((playhead - (m.y - m.win)) / (2 * m.win));
  }

  /** Índice do passo atual e o quanto dele já passou. */
  stepAt(playhead: number): { index: number; fractions: number[] } {
    let index = 0;
    const fractions = this.steps.map((s, i) => {
      const f = clamp01((playhead - s.top) / Math.max(1, s.bottom - s.top));
      if (playhead >= s.top) index = i;
      return f;
    });
    return { index, fractions };
  }

  current = 0;
  private stepListeners = new Set<Listener>();

  subscribeStep = (fn: Listener) => {
    this.stepListeners.add(fn);
    return () => {
      this.stepListeners.delete(fn);
    };
  };

  getCurrent = () => this.current;

  /** Atualiza o passo atual; chamado a cada rolagem. */
  sync = () => {
    const { index } = this.stepAt(this.playhead());
    this.steps.forEach((s, i) => s.el.toggleAttribute("data-current", i === index));
    if (index !== this.current) {
      this.current = index;
      for (const fn of this.stepListeners) fn();
    }
  };

  scrollToStep(index: number) {
    const s = this.steps[Math.max(0, Math.min(this.steps.length - 1, index))];
    if (!s) return;
    const top = index <= 0 ? 0 : s.top - 96;
    window.scrollTo({ top, behavior: prefersReducedMotion() ? "auto" : "smooth" });
  }
}

export const timeline = new Timeline();
