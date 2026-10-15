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
    // piso de escala do enquadramento: editor 0,66; apresentação 1 ("projetor")
    this.minReadable = opts.minReadable ?? MIN_READABLE;
    this.view = { x: 0, y: 0, w: scene.width, h: scene.height };
    // a pessoa mexeu no zoom ou arrastou: redimensionar a janela não desfaz isso
    this.userView = false;
    this._drag = null;
    this._anim = null;
    this._bind();
    this.fit();
  }

  apply() {
    const { x, y, w, h } = this.view;
    this.svg.setAttribute("viewBox", `${x} ${y} ${w} ${h}`);
    // tamanho na tela neste enquadramento: `resize` precisa dele para manter o
    // zoom e para ignorar avisos de redimensionamento sem mudança de tamanho
    const rect = this.svg.getBoundingClientRect();
    if (rect.width > 0) {
      this._lastWidth = rect.width;
      this._lastHeight = rect.height;
    }
    this.onChange(this.scale, this.view);
  }

  get scale() {
    const rect = this.svg.getBoundingClientRect();
    return rect.width > 0 ? rect.width / this.view.w : 1;
  }

  // "Caber inteiro" é péssimo para diagramas de sequência, que são muito altos:
  // o resultado fica em 40% e ninguém lê os rótulos. Abaixo de um limite de
  // legibilidade, cai para "caber na largura" e ancora no topo — o eixo vertical
  // vira rolagem, que é como as pessoas leem uma sequência mesmo. E se nem a
  // largura cabe legível (muitos participantes, tela estreita), fica no zoom
  // mínimo legível, ancorado no começo: o resto é rolagem, e a câmera
  // acompanha a seta que está tocando.
  fit() {
    this.userView = false;
    this._stopAnim();
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
    const fitWidth = rect.width / w;
    let scale = fitAll >= readable ? Math.min(fitAll, 1.15) : Math.min(fitWidth, 1.15);
    const tooSmall = scale < this.minReadable;
    if (tooSmall) scale = this.minReadable;

    const viewW = rect.width / scale;
    const viewH = rect.height / scale;
    const inset = (rect.height - usableH) / scale;
    const usableViewH = viewH - inset;

    this.view = {
      x: tooSmall ? -pad : -pad - (viewW - w) / 2,
      y: (usableViewH >= h ? -pad - (usableViewH - h) / 2 : -pad) - inset,
      w: viewW,
      h: viewH,
    };

    this.apply();
  }

  // Janela redimensionada (ou painel aberto/fechado): sem intervenção da
  // pessoa, reenquadra; se ela escolheu um zoom, mantém o zoom e o centro.
  resize() {
    const rect = this.svg.getBoundingClientRect();
    if (!(rect.width > 0 && rect.height > 0)) return;
    // o mesmo tamanho de antes: nada a refazer — reenquadrar aqui desfaria a
    // câmera que está acompanhando o passo
    if (Math.abs(rect.width - this._lastWidth) < 1 && Math.abs(rect.height - this._lastHeight) < 1) return;
    if (!this.userView) return this.fit();
    const scale = this.view.w > 0 ? this._lastWidth / this.view.w : 1;
    const cx = this.view.x + this.view.w / 2;
    const cy = this.view.y + this.view.h / 2;
    const w = rect.width / (scale || 1);
    const h = rect.height / (scale || 1);
    this.view = { x: cx - w / 2, y: cy - h / 2, w, h };
    this.apply();
  }

  // Garante que uma área da cena ({x, y, w, h}) esteja à vista, com folga,
  // sem mudar o zoom; só move se ela estiver (parcialmente) fora da tela.
  ensureVisible(box, { margin = 48, smooth = true } = {}) {
    const rect = this.svg.getBoundingClientRect();
    if (!(rect.width > 0) || !box) return;
    const k = this.view.w / rect.width;
    const m = margin * k;
    const top = this.view.y + this.insetTop * k;
    const v = this.view;
    let x = v.x;
    let y = v.y;
    if (box.w + 2 * m <= v.w) {
      if (box.x - m < v.x) x = box.x - m;
      else if (box.x + box.w + m > v.x + v.w) x = box.x + box.w + m - v.w;
    } else {
      x = box.x - m;
    }
    if (box.y - m < top) y = box.y - m - this.insetTop * k;
    else if (box.y + box.h + m > v.y + v.h) y = Math.min(box.y + box.h + m - v.h, box.y - m - this.insetTop * k);
    if (Math.abs(x - v.x) < 1 && Math.abs(y - v.y) < 1) return;
    this.animateTo(x, y, smooth);
  }

  animateTo(x, y, smooth = true) {
    this._stopAnim();
    if (!smooth || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.view.x = x;
      this.view.y = y;
      return this.apply();
    }
    const fromX = this.view.x;
    const fromY = this.view.y;
    const start = performance.now();
    const step = (ts) => {
      const p = Math.min((ts - start) / 420, 1);
      const eased = 1 - Math.pow(1 - p, 3);
      this.view.x = fromX + (x - fromX) * eased;
      this.view.y = fromY + (y - fromY) * eased;
      this.apply();
      this._anim = p < 1 ? requestAnimationFrame(step) : null;
    };
    this._anim = requestAnimationFrame(step);
  }

  _stopAnim() {
    if (this._anim) cancelAnimationFrame(this._anim);
    this._anim = null;
  }

  zoomBy(factor, clientX, clientY) {
    this.userView = true;
    this._stopAnim();
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
    this.animateTo(this.view.x, y - this.view.h / 2, smooth);
  }

  destroy() {
    this._stopAnim();
    for (const [target, type, fn, opts] of this._listeners) target.removeEventListener(type, fn, opts);
  }

  _bind() {
    const onWheel = (e) => {
      e.preventDefault();
      if (e.ctrlKey || e.metaKey || Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
        this.zoomBy(Math.pow(1.0015, -e.deltaY), e.clientX, e.clientY);
      } else {
        this.userView = true;
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
        this.userView = true;
        this._stopAnim();
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
// Abaixo disto os rótulos (13–14px) ficam com menos de ~9px na tela.
const MIN_READABLE = 0.66;

function clampRange(v, lo, hi) {
  return Math.max(lo, Math.min(v, hi));
}
