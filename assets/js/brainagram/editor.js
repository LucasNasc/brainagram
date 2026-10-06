// Modo de edição do canvas (spec 001, §6).
//
// Regra do módulo: nada aqui muda o diagrama. Cada gesto vira um pedido de
// edição do *texto* (`push(op, params)`); o servidor aplica a edição cirúrgica,
// recompila e manda a cena nova. O canvas só antecipa o efeito para o gesto
// não parecer lento — arrastar acompanha o mouse a 60fps aqui, e o comando sai
// no `pointerup` (§6: "arrastar é local").

import { icon, arrowGlyph } from "./icons";
import { t } from "./i18n";

const NS = "http://www.w3.org/2000/svg";
const GRID = 8;
const SNAP_PX = 6;
const DRAG_THRESHOLD = 4;
const GHOST = { w: 160, h: 68 };

const ARROWS = [
  ["sync", "Chamada síncrona (->)"],
  ["return", "Retorno (-->)"],
  ["async", "Assíncrona (->>)"],
  ["fail", "Falha (-x)"],
];

function el(name, attrs = {}, parent = null) {
  const node = document.createElementNS(NS, name);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, String(v));
  if (parent) parent.appendChild(node);
  return node;
}

const snapGrid = (v) => Math.round(v / GRID) * GRID;

export class CanvasEditor {
  // opts: { svg, stage, scene, viewport, push(op, params), step(), isSpaceDown(), onSelect() }
  constructor(opts) {
    Object.assign(this, opts);
    this.enabled = false;
    this.selection = null;
    this.gesture = null;
    this.connectFrom = null; // modo "Conectar" pela paleta: clique na origem, depois no destino
    this.nodes = new Map(this.scene.nodes.map((n) => [n.id, n]));
    this.edges = new Map(this.scene.edges.map((e) => [e.id, e]));

    this.layer = el("g", { class: "bg-edit-layer" }, this.svg);
    this.guides = el("g", { class: "bg-guides" }, this.layer);
    this.temp = el("path", { class: "bg-temp-edge", d: "" }, this.layer);
    this.ghost = el("rect", { class: "bg-ghost", rx: 10, width: GHOST.w, height: GHOST.h, visibility: "hidden" }, this.layer);
    this.handle = el("circle", { class: "bg-handle", r: 7, visibility: "hidden" }, this.layer);
    this.handle.appendChild(el("title")).textContent = t("Arraste até outro nó para conectar");

    this.bar = document.createElement("div");
    this.bar.className = "ba-float ba-selbar";
    this.bar.hidden = true;
    this.stage.appendChild(this.bar);

    this._bind();
  }

  setEnabled(on) {
    this.enabled = on;
    this.svg.classList.toggle("is-editing", on);
    if (!on) {
      this.clearSelection();
      this.cancelConnect();
      this.handle.setAttribute("visibility", "hidden");
    }
  }

  destroy() {
    for (const [t, type, fn, o] of this._listeners) t.removeEventListener(type, fn, o);
    this.closeInline(false);
    this.bar.remove();
    this.layer.remove();
  }

  // ── seleção ──────────────────────────────────────────────────────────────

  select(kind, id) {
    this.clearSelection();
    const group = this.groupOf(kind, id);
    if (!group) return;
    group.classList.add("is-selected");
    this.selection = { kind, id };
    this.renderBar();
    this.onSelect && this.onSelect(this.selection);
  }

  clearSelection() {
    this.svg.querySelectorAll(".is-selected").forEach((g) => g.classList.remove("is-selected"));
    this.selection = null;
    this.bar.hidden = true;
  }

  groupOf(kind, id) {
    const attr = kind === "node" ? "data-node" : "data-edge";
    return this.svg.querySelector(`.bg-${kind}[${attr}="${CSS.escape(id)}"]`);
  }

  removeSelection() {
    if (!this.selection) return;
    const { kind, id } = this.selection;
    this.clearSelection();
    this.push(kind === "node" ? "remove_node" : "remove_edge", { id });
  }

  // Barra flutuante da seleção: tipo da seta, renomear, soltar posição, remover.
  renderBar() {
    const sel = this.selection;
    if (!sel) return;
    const buttons = [];

    if (sel.kind === "edge") {
      const edge = this.edges.get(sel.id);
      for (const [kind, label] of ARROWS) {
        const pressed = edge && edge.arrow === kind;
        buttons.push(
          `<button type="button" class="ba-btn ba-btn--icon ba-btn--sm" data-act="arrow" data-arrow="${kind}" aria-pressed="${pressed}" aria-label="${t(label)}" title="${t(label)}">${arrowGlyph(kind)}</button>`,
        );
      }
      buttons.push('<span class="ba-float__sep"></span>');
      buttons.push(this.barButton("relabel", "pencil-square", t("Editar rótulo (Enter)")));
      // o balão de payload só é desenhado na sequência
      if (this.scene.kind === "sequence") {
        buttons.push(this.barButton("payload", "code-bracket-square", t("Payload da mensagem (P)")));
      }
    } else {
      const node = this.nodes.get(sel.id);
      buttons.push(this.barButton("rename", "pencil-square", t("Renomear (Enter)")));
      buttons.push(this.barButton("connect", "link", t("Conectar a outro nó")));
      if (node && node.pinned) buttons.push(this.barButton("unpin", "lock-open", t("Voltar ao layout automático")));
    }

    buttons.push(this.barButton("remove", "trash", t("Remover (Delete)"), "ba-btn--danger"));
    this.bar.innerHTML = buttons.join("");
    this.bar.hidden = false;
    this.placeBar();
  }

  barButton(act, name, label, extra = "") {
    return `<button type="button" class="ba-btn ba-btn--icon ba-btn--sm ${extra}" data-act="${act}" aria-label="${label}" title="${label}">${icon(name)}</button>`;
  }

  placeBar() {
    const group = this.selection && this.groupOf(this.selection.kind, this.selection.id);
    if (!group) return (this.bar.hidden = true);
    const box = group.getBoundingClientRect();
    const stage = this.stage.getBoundingClientRect();
    const barW = this.bar.offsetWidth || 160;
    const left = Math.max(8, Math.min(box.left + box.width / 2 - stage.left - barW / 2, stage.width - barW - 8));
    // acima do elemento; sem espaço (a faixa de cima é da barra do canvas), abaixo
    const above = box.top - stage.top - 44;
    const top = above >= 56 ? above : box.bottom - stage.top + 8;
    this.bar.style.left = `${left}px`;
    this.bar.style.top = `${top}px`;
  }

  onBarClick(e) {
    const btn = e.target.closest("[data-act]");
    if (!btn || !this.selection) return;
    const { kind, id } = this.selection;
    switch (btn.dataset.act) {
      case "arrow":
        this.push("change_arrow", { id, arrow: btn.dataset.arrow });
        break;
      case "relabel":
        this.startRelabel(id);
        break;
      case "payload":
        this.startPayload(id);
        break;
      case "rename":
        this.startRename(id);
        break;
      case "connect":
        this.startConnect(id);
        break;
      case "unpin":
        this.push("unpin", { id });
        break;
      case "remove":
        this.removeSelection();
        break;
    }
    if (kind) this.placeBar();
  }

  // ── edição no lugar ──────────────────────────────────────────────────────

  startRename(id) {
    const node = this.nodes.get(id);
    if (!node) return;
    const topLeft = this.viewport.toClient(node.x + 30, node.y + node.h / 2 - 14);
    const bottomRight = this.viewport.toClient(node.x + node.w - 8, node.y + node.h / 2 + 14);
    this.openInline({
      value: node.label,
      box: { left: topLeft.x, top: topLeft.y, width: bottomRight.x - topLeft.x },
      label: t("Nome de {label}", { label: node.label }),
      commit: (value) => value.trim() && value !== node.label && this.push("rename_node", { id, label: value }),
    });
  }

  startRelabel(id) {
    const edge = this.edges.get(id);
    if (!edge) return;
    const x = edge.label ? edge.label_x : (edge.x1 + edge.x2) / 2;
    const y = edge.label ? edge.label_y : ((edge.y1 ?? edge.y) + (edge.y2 ?? edge.y)) / 2;
    const at = this.viewport.toClient(x, y);
    const width = Math.max(160, (edge.label || "").length * 8 + 40);
    const anchor = edge.label_anchor || "middle";
    const left = anchor === "middle" ? at.x - width / 2 : anchor === "end" ? at.x - width : at.x - 6;
    this.openInline({
      value: edge.label || "",
      placeholder: t("rótulo da mensagem"),
      box: { left, top: at.y - 16, width },
      label: t("Rótulo da seta"),
      commit: (value) => value !== (edge.label || "") && this.push("relabel_edge", { id, label: value }),
    });
  }

  // O payload: o que a mensagem carrega, num balão sob a seta. Edita-se numa
  // caixa de várias linhas no lugar do balão (ou logo abaixo da seta, se ainda
  // não houver um): Enter quebra linha, Ctrl+Enter salva, Esc cancela.
  startPayload(id) {
    const edge = this.edges.get(id);
    if (!edge) return;
    const p = edge.payload;
    const mid = ((edge.x1 ?? 0) + (edge.x2 ?? 0)) / 2;
    const y = p ? p.y : (edge.y ?? edge.y1) + 12;
    // tudo em coordenadas de tela (o zoom conta), e a caixa sempre dentro do palco
    const topLeft = this.viewport.toClient(p ? p.x : mid, y);
    const right = p ? this.viewport.toClient(p.x + p.w, y).x : topLeft.x;
    const width = Math.max(280, right - topLeft.x + 24);
    const stage = this.stage.getBoundingClientRect();
    const wanted = p ? topLeft.x : topLeft.x - width / 2;
    const left = Math.max(stage.left + 8, Math.min(wanted, stage.right - width - 8));
    this.openInline({
      value: p ? p.text : "",
      multiline: true,
      placeholder: t('{"id": 42, "status": "pago"}'),
      box: { left, top: topLeft.y, width },
      label: t("Payload da mensagem"),
      commit: (value) => value.trim() !== (p ? p.text : "").trim() && this.push("set_payload", { id, payload: value }),
    });
  }

  openInline({ value, box, commit, placeholder = "", label, multiline = false }) {
    this.closeInline(false);
    const stage = this.stage.getBoundingClientRect();
    const input = document.createElement(multiline ? "textarea" : "input");
    input.className = multiline ? "ba-inline-input ba-inline-input--area" : "ba-inline-input";
    input.value = value;
    input.placeholder = placeholder;
    input.spellcheck = false;
    input.setAttribute("aria-label", label);
    if (multiline) {
      input.rows = Math.min(12, Math.max(3, value.split("\n").length + 1));
      input.title = t("Ctrl+Enter salva · Esc cancela");
    }
    input.style.left = `${box.left - stage.left}px`;
    input.style.top = `${box.top - stage.top}px`;
    input.style.width = `${Math.max(120, box.width)}px`;
    this.stage.appendChild(input);
    this.inline = { input, commit };

    input.addEventListener("keydown", (e) => {
      e.stopPropagation();
      const save = multiline ? e.key === "Enter" && (e.ctrlKey || e.metaKey) : e.key === "Enter";
      if (save) {
        e.preventDefault();
        this.closeInline(true);
      }
      if (e.key === "Escape") this.closeInline(false);
    });
    input.addEventListener("blur", () => this.closeInline(true));
    requestAnimationFrame(() => {
      input.focus();
      input.select();
    });
  }

  closeInline(save) {
    const inline = this.inline;
    if (!inline) return;
    this.inline = null;
    if (save) inline.commit(inline.input.value);
    inline.input.remove();
  }

  // ── conectar ─────────────────────────────────────────────────────────────

  startConnect(fromId = null) {
    this.connectFrom = fromId || "pick";
    this.svg.classList.add("is-connecting");
    this.hint && this.hint(fromId ? t("Clique no nó de destino") : t("Clique no nó de origem"));
  }

  cancelConnect() {
    this.connectFrom = null;
    this.svg.classList.remove("is-connecting");
    this.temp.setAttribute("d", "");
    this.hint && this.hint(null);
  }

  connect(from, to) {
    this.cancelConnect();
    if (!from || !to) return;
    const step = this.step();
    const params = { from, to };
    if (step !== null && step !== undefined) params.step = step;
    this.push("connect", params);
  }

  // ── gestos ───────────────────────────────────────────────────────────────

  _bind() {
    const down = (e) => this.onDown(e);
    const move = (e) => this.onMove(e);
    const up = (e) => this.onUp(e);
    const dbl = (e) => this.onDouble(e);
    const bar = (e) => this.onBarClick(e);
    const hide = () => this.selection && this.placeBar();

    this._listeners = [
      [this.svg, "pointerdown", down, undefined],
      [this.svg, "pointermove", move, undefined],
      [this.svg, "pointerup", up, undefined],
      [this.svg, "pointercancel", up, undefined],
      [this.svg, "dblclick", dbl, undefined],
      [this.bar, "click", bar, undefined],
      [this.svg, "wheel", hide, { passive: true }],
    ];
    for (const [t, type, fn, o] of this._listeners) t.addEventListener(type, fn, o);
  }

  scenePoint(e) {
    return this.viewport.toScene(e.clientX, e.clientY);
  }

  nodeAt(e) {
    const hit = document.elementFromPoint(e.clientX, e.clientY);
    const g = hit && hit.closest && hit.closest(".bg-node");
    return g && this.svg.contains(g) ? g.dataset.node : null;
  }

  onDown(e) {
    // chip/balão de payload: o clique é de abrir e fechar, não de selecionar
    if (e.target.closest && e.target.closest("[data-payload]")) return;
    if (!this.enabled || e.button !== 0 || this.isSpaceDown()) return;
    this.closeInline(true);

    const target = e.target;
    const nodeG = target.closest(".bg-node");
    const edgeG = target.closest(".bg-edge");
    const p = this.scenePoint(e);

    if (this.connectFrom) {
      const id = nodeG && nodeG.dataset.node;
      if (!id) return this.cancelConnect();
      if (this.connectFrom === "pick") return this.startConnect(id);
      return this.connect(this.connectFrom, id);
    }

    if (target.closest(".bg-handle")) {
      this.gesture = { type: "connect", from: this.handle.dataset.node, start: p };
    } else if (nodeG) {
      const node = this.nodes.get(nodeG.dataset.node);
      this.gesture = { type: "node", node, group: nodeG, start: p, client: { x: e.clientX, y: e.clientY }, moved: false };
    } else if (edgeG) {
      this.gesture = { type: "edge", id: edgeG.dataset.edge };
    } else if (!target.closest(".bg-band")) {
      this.gesture = { type: "create", start: p, client: { x: e.clientX, y: e.clientY }, moved: false };
    } else {
      return;
    }

    this.svg.setPointerCapture?.(e.pointerId);
    e.stopPropagation();
  }

  onMove(e) {
    if (!this.enabled) return;
    const g = this.gesture;

    if (!g) return this.hover(e);

    const p = this.scenePoint(e);
    const dist = g.client ? Math.hypot(e.clientX - g.client.x, e.clientY - g.client.y) : 99;

    if (g.type === "node") {
      if (!g.moved && dist < DRAG_THRESHOLD) return;
      g.moved = true;
      this.clearSelection();
      this.handle.setAttribute("visibility", "hidden");
      const seq = this.scene.kind === "sequence";
      const raw = { x: g.node.x + (p.x - g.start.x), y: seq ? g.node.y : g.node.y + (p.y - g.start.y) };
      const snapped = this.snap(raw, g.node, seq);
      g.to = snapped;
      g.group.setAttribute("transform", `translate(${snapped.x - g.node.x} ${snapped.y - g.node.y})`);
      g.group.classList.add("is-dragging");
      this.highlightDropGroup(snapped, g.node);
    }

    if (g.type === "connect") {
      const from = this.nodes.get(g.from);
      if (!from) return;
      this.temp.setAttribute("d", `M ${from.cx} ${from.cy ?? from.y + from.h / 2} L ${p.x} ${p.y}`);
      const over = this.nodeAt(e);
      this.svg.querySelectorAll(".bg-node.is-target").forEach((n) => n.classList.remove("is-target"));
      if (over && over !== g.from) this.groupOf("node", over)?.classList.add("is-target");
    }

    if (g.type === "create") {
      if (!g.moved && dist < DRAG_THRESHOLD * 3) return;
      g.moved = true;
      g.at = { x: snapGrid(p.x - GHOST.w / 2), y: snapGrid(p.y - GHOST.h / 2) };
      this.ghost.setAttribute("x", g.at.x);
      this.ghost.setAttribute("y", g.at.y);
      this.ghost.setAttribute("visibility", "visible");
    }
  }

  onUp(e) {
    const g = this.gesture;
    this.gesture = null;
    if (!g || !this.enabled) return;
    this.svg.releasePointerCapture?.(e.pointerId);
    this.clearGuides();

    if (g.type === "node") {
      if (!g.moved) return this.select("node", g.node.id);
      g.group.classList.remove("is-dragging");
      const to = g.to || { x: g.node.x, y: g.node.y };
      const params = { id: g.node.id, x: Math.round(to.x), y: Math.round(to.y) };

      if (this.scene.kind === "architecture") {
        const target = this.groupAt(to, g.node);
        if ((target || null) !== (g.node.group || null)) params.group = target || "";
      }

      this.onDrop && this.onDrop(params);
      this.push("drop", params);
    }

    if (g.type === "edge") this.select("edge", g.id);

    if (g.type === "connect") {
      this.temp.setAttribute("d", "");
      this.svg.querySelectorAll(".bg-node.is-target").forEach((n) => n.classList.remove("is-target"));
      const to = this.nodeAt(e);
      if (to && to !== g.from) this.connect(g.from, to);
    }

    if (g.type === "create") {
      this.ghost.setAttribute("visibility", "hidden");
      if (g.moved && g.at) this.push("add_node", { label: t("Novo nó"), x: g.at.x, y: g.at.y });
      else this.clearSelection();
    }
  }

  onDouble(e) {
    if (!this.enabled) return;
    const nodeG = e.target.closest(".bg-node");
    const edgeG = e.target.closest(".bg-edge");
    if (nodeG) return this.startRename(nodeG.dataset.node);
    const payloadG = e.target.closest("[data-payload]");
    if (payloadG) return this.startPayload(payloadG.dataset.payload);
    if (edgeG) return this.startRelabel(edgeG.dataset.edge);
    if (!e.target.closest(".bg-band")) {
      const p = this.scenePoint(e);
      this.push("add_node", { label: t("Novo nó"), x: snapGrid(p.x - GHOST.w / 2), y: snapGrid(p.y - GHOST.h / 2) });
    }
  }

  hover(e) {
    const g = e.target.closest && e.target.closest(".bg-node");
    if (!g || e.target.closest(".bg-handle")) {
      if (!e.target.closest || !e.target.closest(".bg-handle")) this.handle.setAttribute("visibility", "hidden");
      return;
    }
    const node = this.nodes.get(g.dataset.node);
    if (!node) return;
    const seq = this.scene.kind === "sequence";
    this.handle.setAttribute("cx", seq ? node.cx : node.x + node.w);
    this.handle.setAttribute("cy", seq ? node.y + node.h : node.y + node.h / 2);
    this.handle.dataset.node = node.id;
    this.handle.setAttribute("visibility", "visible");
  }

  // ── snapping ─────────────────────────────────────────────────────────────

  // Grade de 8px e bordas/centros dos vizinhos (spec 001, §6). O ímã dos
  // vizinhos vence a grade quando está a poucos pixels de tela.
  snap(raw, node, seq) {
    const tol = SNAP_PX / (this.viewport.scale || 1);
    let x = snapGrid(raw.x);
    let y = seq ? raw.y : snapGrid(raw.y);
    let gx = null;
    let gy = null;

    for (const other of this.scene.nodes) {
      if (other.id === node.id) continue;
      const xs = [other.x, other.x + other.w - node.w, other.cx - node.w / 2];
      for (const cand of xs) {
        if (Math.abs(raw.x - cand) < tol) {
          x = cand;
          gx = cand === other.cx - node.w / 2 ? other.cx : cand === other.x ? other.x : other.x + other.w;
        }
      }
      if (!seq) {
        const cy = other.cy ?? other.y + other.h / 2;
        const ys = [other.y, other.y + other.h - node.h, cy - node.h / 2];
        for (const cand of ys) {
          if (Math.abs(raw.y - cand) < tol) {
            y = cand;
            gy = cand === cy - node.h / 2 ? cy : cand === other.y ? other.y : other.y + other.h;
          }
        }
      }
    }

    this.drawGuides(gx, gy);
    return { x: Math.max(0, Math.round(x)), y: Math.max(0, Math.round(y)) };
  }

  drawGuides(gx, gy) {
    this.clearGuides();
    const { width, height } = this.scene;
    if (gx !== null) el("line", { class: "bg-guide", x1: gx, y1: -2000, x2: gx, y2: height + 2000 }, this.guides);
    if (gy !== null) el("line", { class: "bg-guide", x1: -2000, y1: gy, x2: width + 2000, y2: gy }, this.guides);
  }

  clearGuides() {
    this.guides.replaceChildren();
    this.svg.querySelectorAll(".bg-group.is-drop-target").forEach((g) => g.classList.remove("is-drop-target"));
  }

  // ── grupos ───────────────────────────────────────────────────────────────

  groupAt(to, node) {
    const cx = to.x + node.w / 2;
    const cy = to.y + node.h / 2;
    const hit = this.scene.groups.find((g) => cx >= g.x && cx <= g.x + g.w && cy >= g.y && cy <= g.y + g.h);
    return hit ? hit.label : null;
  }

  highlightDropGroup(to, node) {
    if (this.scene.kind !== "architecture") return;
    const label = this.groupAt(to, node);
    this.svg.querySelectorAll(".bg-group[data-group]").forEach((g) => {
      g.classList.toggle("is-drop-target", g.dataset.group === label && label !== node.group);
    });
  }

  // ── teclado ──────────────────────────────────────────────────────────────

  // Devolve true quando o atalho foi consumido pelo canvas.
  onKey(e) {
    if (!this.enabled) return false;
    if (e.key === "Escape") {
      const busy = !!(this.connectFrom || this.selection);
      if (this.connectFrom) this.cancelConnect();
      this.clearSelection();
      return busy;
    }
    if (!this.selection) return false;
    if (e.key === "Delete" || e.key === "Backspace") {
      this.removeSelection();
      return true;
    }
    if (e.key === "Enter") {
      const { kind, id } = this.selection;
      kind === "node" ? this.startRename(id) : this.startRelabel(id);
      return true;
    }
    if ((e.key === "p" || e.key === "P") && this.selection.kind === "edge" && this.scene.kind === "sequence") {
      this.startPayload(this.selection.id);
      return true;
    }
    return false;
  }
}
