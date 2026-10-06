// Pan/zoom manipulando o viewBox do SVG.
//
// Fica tudo no cliente de propósito: arrastar o canvas não pode custar um
// round-trip de WebSocket. O LiveView só sabe da cena, nunca do zoom.

export class Viewport {
  constructor(svg, scene, opts = {}) {
    this.svg = svg;
    this.scene = scene;
    this.min = opts.min ?? 0.2;
    this.max = opts.max ?? 4;
    this.onChange = opts.onChange || (() => {});
    // Quem decide se um arrasto move a tela: no modo de edição, arrastar em área
    // vazia cria nó, e o pan fica para Espaço+arrastar ou o botão do meio.
    this.canPan = opts.canPan || (() => true);
    // Faixa de cima ocupada por controles flutuantes: o enquadramento não põe nada ali.
    this.insetTop = opts.insetTop ?? 0;
    this.view = { x: 0, y: 0, w: scene.width, h: scene.height };
    this._drag = null;
    this._bind();
    this.fit();
  }

  apply() {
    const { x, y, w, h } = this.view;
    this.svg.setAttribute("viewBox", `${x} ${y} ${w} ${h}`);
    this.onChange(this.scale);
  }

  get scale() {
    const rect = this.svg.getBoundingClientRect();
    return rect.width > 0 ? rect.width / this.view.w : 1;
  }

  // "Caber inteiro" é péssimo para diagramas de sequência, que são muito altos:
  // o resultado fica em 40% e ninguém lê os rótulos. Abaixo de um limite de
  // legibilidade, cai para "caber na largura" e ancora no topo — o eixo vertical
  // vira rolagem, que é como as pessoas leem uma sequência mesmo.
  fit() {
    const rect = this.svg.getBoundingClientRect();
    const pad = 28;
    const w = this.scene.width + pad * 2;
    const h = this.scene.height + pad * 2;

    if (!(rect.width > 0 && rect.height > 0)) {
      this.view = { x: -pad, y: -pad, w, h };
      return this.apply();
    }

    const usableH = Math.max(rect.height - this.insetTop, rect.height * 0.5);
    const fitAll = Math.min(rect.width / w, usableH / h);
    const readable = 0.62;
    const scale = fitAll >= readable ? Math.min(fitAll, 1.15) : Math.min(rect.width / w, 1.15);

    const viewW = rect.width / scale;
    const viewH = rect.height / scale;
    const inset = (rect.height - usableH) / scale;
    const usableViewH = viewH - inset;

    this.view = {
      x: -pad - (viewW - w) / 2,
      y: (usableViewH >= h ? -pad - (usableViewH - h) / 2 : -pad) - inset,
      w: viewW,
      h: viewH,
    };

    this.apply();
  }

  zoomBy(factor, clientX, clientY) {
    const rect = this.svg.getBoundingClientRect();
    const cx = clientX ?? rect.left + rect.width / 2;
    const cy = clientY ?? rect.top + rect.height / 2;
    const fx = (cx - rect.left) / rect.width;
    const fy = (cy - rect.top) / rect.height;

    const nextW = clampRange(this.view.w / factor, this.scene.width / this.max, this.scene.width / this.min);
    const k = nextW / this.view.w;
    const nextH = this.view.h * k;

    this.view = {
      x: this.view.x + (this.view.w - nextW) * fx,
      y: this.view.y + (this.view.h - nextH) * fy,
      w: nextW,
      h: nextH,
    };

    this.apply();
  }

  // Ponto da tela → coordenada da cena (a mesma unidade do layout do servidor).
  toScene(clientX, clientY) {
    const ctm = this.svg.getScreenCTM();
    if (!ctm) return { x: 0, y: 0 };
    const pt = new DOMPoint(clientX, clientY).matrixTransform(ctm.inverse());
    return { x: pt.x, y: pt.y };
  }

  // Coordenada da cena → ponto da tela (para posicionar controles HTML por cima).
  toClient(x, y) {
    const ctm = this.svg.getScreenCTM();
    if (!ctm) return { x: 0, y: 0 };
    const pt = new DOMPoint(x, y).matrixTransform(ctm);
    return { x: pt.x, y: pt.y };
  }

  // Centraliza verticalmente em uma coordenada da cena (usado ao trocar de passo).
  focusY(y, smooth = true) {
    const target = y - this.view.h / 2;
    if (!smooth) {
      this.view.y = target;
      this.apply();
      return;
    }
    const from = this.view.y;
    const start = performance.now();
    const step = (ts) => {
      const p = Math.min((ts - start) / 420, 1);
      const eased = 1 - Math.pow(1 - p, 3);
      this.view.y = from + (target - from) * eased;
      this.apply();
      if (p < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  destroy() {
    for (const [target, type, fn, opts] of this._listeners) target.removeEventListener(type, fn, opts);
  }

  _bind() {
    const onWheel = (e) => {
      e.preventDefault();
      if (e.ctrlKey || e.metaKey || Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
        this.zoomBy(Math.pow(1.0015, -e.deltaY), e.clientX, e.clientY);
      } else {
        this.view.x += (e.deltaX * this.view.w) / this.svg.getBoundingClientRect().width;
        this.apply();
      }
    };

    // O arrasto só começa depois de o ponteiro andar um pouco. Capturar o
    // ponteiro já no pointerdown faria todo clique cair no <svg> — e o chip do
    // payload, a faixa do passo etc. nunca receberiam o clique.
    const onDown = (e) => {
      if (!(e.button === 1 || (e.button === 0 && this.canPan(e)))) return;
      if (e.button === 1) e.preventDefault();
      this._drag = { x: e.clientX, y: e.clientY, vx: this.view.x, vy: this.view.y, id: e.pointerId, active: false };
    };

    const onMove = (e) => {
      if (!this._drag) return;
      if (!this._drag.active) {
        if (Math.hypot(e.clientX - this._drag.x, e.clientY - this._drag.y) < PAN_THRESHOLD) return;
        this._drag.active = true;
        this.svg.classList.add("is-panning");
        this.svg.setPointerCapture?.(this._drag.id);
      }
      const rect = this.svg.getBoundingClientRect();
      const kx = this.view.w / rect.width;
      const ky = this.view.h / rect.height;
      this.view.x = this._drag.vx - (e.clientX - this._drag.x) * kx;
      this.view.y = this._drag.vy - (e.clientY - this._drag.y) * ky;
      this.apply();
    };

    const onUp = (e) => {
      const wasPanning = this._drag && this._drag.active;
      this._drag = null;
      if (!wasPanning) return;
      this.svg.classList.remove("is-panning");
      this.svg.releasePointerCapture?.(e.pointerId);
    };

    this._listeners = [
      [this.svg, "wheel", onWheel, { passive: false }],
      [this.svg, "pointerdown", onDown, undefined],
      [this.svg, "pointermove", onMove, undefined],
      [this.svg, "pointerup", onUp, undefined],
      [this.svg, "pointercancel", onUp, undefined],
    ];

    for (const [target, type, fn, opts] of this._listeners) target.addEventListener(type, fn, opts);
  }
}

const PAN_THRESHOLD = 4;

function clampRange(v, lo, hi) {
  return Math.max(lo, Math.min(v, hi));
}
