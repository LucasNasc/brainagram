// Motor de animação.
//
// Propriedade central: `seek(t)` é uma função pura do tempo — desenha o estado
// exato do diagrama no instante `t` sem depender do que foi desenhado antes.
// Play vira só "incrementa t e chama seek"; o scrub vira "chama seek". Isso
// elimina toda a classe de bugs de animação baseada em callbacks encadeados.

const STEP_HOLD = 340;
const EDGE_OVERLAP = 0.86;

export function buildSchedule(scene) {
  const entries = new Map();
  const steps = [];
  let cursor = 0;

  for (const step of scene.steps) {
    const start = cursor;

    for (const id of step.note_ids || []) {
      entries.set(id, { start, dur: 260, step: step.index, note: true });
    }

    for (const id of step.edge_ids) {
      const edge = scene.edges.find((e) => e.id === id);
      const dur = (edge && edge.duration) || 700;
      entries.set(id, { start: cursor, dur, step: step.index, note: false });
      // mensagem com payload: pausa de leitura com o balão aberto
      cursor += dur * EDGE_OVERLAP + ((edge && edge.payload && edge.payload.hold) || 0);
    }

    if (step.edge_ids.length === 0) cursor += 420;
    cursor += STEP_HOLD;
    steps.push({ index: step.index, label: step.label, start, end: cursor });
  }

  const total = Math.max(cursor, 1);

  // Até quando o balão de cada mensagem fica aberto: até a próxima começar
  // (ou até o fim, para a última) — "passou dela, minimiza".
  const edgeEntries = [...entries.values()].filter((e) => !e.note).sort((a, b) => a.start - b.start);
  edgeEntries.forEach((entry, i) => {
    entry.until = i + 1 < edgeEntries.length ? edgeEntries[i + 1].start : total;
  });

  return { entries, steps, total };
}

export class Timeline {
  constructor(index, schedule, opts = {}) {
    this.index = index;
    this.schedule = schedule;
    this.t = 0;
    this.speed = 1;
    this.playing = false;
    this.loop = opts.loop ?? false;
    this.onTick = opts.onTick || (() => {});
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this._frame = null;
    this._last = 0;
  }

  get total() {
    return this.schedule.total;
  }

  get currentStep() {
    const steps = this.schedule.steps;
    let current = 0;
    for (const s of steps) {
      if (this.t >= s.start) current = s.index;
    }
    return current;
  }

  play() {
    if (this.playing) return;
    if (this.t >= this.total - 1) this.t = 0;
    this.playing = true;
    this._last = performance.now();
    this._frame = requestAnimationFrame((ts) => this._loop(ts));
    this.onTick(this);
  }

  pause() {
    this.playing = false;
    if (this._frame) cancelAnimationFrame(this._frame);
    this._frame = null;
    this.onTick(this);
  }

  toggle() {
    this.playing ? this.pause() : this.play();
  }

  restart() {
    this.seek(0);
    this.play();
  }

  seek(t) {
    this.t = Math.max(0, Math.min(t, this.total));
    this.paint();
    this.onTick(this);
  }

  gotoStep(index) {
    const step = this.schedule.steps.find((s) => s.index === index);
    if (step) this.seek(step.start + 1);
  }

  nextStep() {
    const next = this.schedule.steps.find((s) => s.start > this.t + 2);
    next ? this.seek(next.start + 1) : this.seek(this.total);
  }

  prevStep() {
    const before = this.schedule.steps.filter((s) => s.start < this.t - 60);
    before.length ? this.seek(before[before.length - 1].start + 1) : this.seek(0);
  }

  destroy() {
    this.pause();
  }

  _loop(ts) {
    if (!this.playing) return;
    const dt = Math.min(ts - this._last, 64);
    this._last = ts;
    this.t += dt * this.speed;

    if (this.t >= this.total) {
      if (this.loop) {
        this.t = 0;
      } else {
        this.t = this.total;
        this.paint();
        this.pause();
        return;
      }
    }

    this.paint();
    this.onTick(this);
    this._frame = requestAnimationFrame((next) => this._loop(next));
  }

  // ── pintura ─────────────────────────────────────────────────────────────

  paint() {
    const { entries } = this.schedule;
    const current = this.currentStep;
    const hot = new Set();
    const live = new Set();

    for (const [id, entry] of entries) {
      const item = this.index.edges.get(id);
      if (!item) continue;

      const p = entry.dur > 0 ? clamp((this.t - entry.start) / entry.dur, 0, 1) : 1;
      const started = this.t >= entry.start;

      let state = "pending";
      if (started && p >= 1) state = "done";
      else if (started) state = "active";

      setState(item.group, state, entry.step === current);

      if (item.payload) {
        item.payload.classList.toggle("is-open", started && this.t < entry.until);
        item.payload.classList.toggle("is-live", state === "active");
      }

      if (item.line) {
        const offset = this.reduced ? (started ? 0 : item.length) : item.length * (1 - p);
        item.line.style.strokeDashoffset = `${offset}`;
      }

      if (item.packet && item.line) {
        if (!this.reduced && state === "active" && item.length > 0) {
          const pt = item.line.getPointAtLength(item.length * p);
          item.packet.setAttribute("transform", `translate(${pt.x} ${pt.y})`);
          item.packet.style.opacity = "1";
        } else {
          item.packet.style.opacity = "0";
        }
      }

      if (entry.step === current && !entry.note) {
        live.add(item.meta.from);
        live.add(item.meta.to);
        if (p > 0.82) hot.add(item.meta.to);
      }
    }

    for (const [id, group] of this.index.nodes) {
      group.classList.toggle("is-active", live.has(id));
      group.classList.toggle("is-hot", hot.has(id));
    }

    for (const [idx, refs] of this.index.steps) {
      if (refs && refs.band) refs.band.classList.toggle("is-current", idx === current);
    }
  }
}

function setState(group, state, isCurrent) {
  // A ponta acompanha o traço: na cor do impulso enquanto a seta toca.
  if (group.dataset.state !== state) {
    group.dataset.state = state;
    const line = group.querySelector(".bg-edge-line");
    if (line && group.dataset.arrow) {
      const marker = state === "active" ? "active" : group.dataset.arrow;
      line.setAttribute("marker-end", `url(#bg-arrow-${marker})`);
    }
  }

  group.classList.toggle("is-pending", state === "pending");
  group.classList.toggle("is-active", state === "active");
  group.classList.toggle("is-done", state === "done");
  group.classList.toggle("is-current-step", isCurrent);
}

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(v, hi));
}
