// Cola entre o LiveView e o renderizador.
//
// Contrato: o servidor manda `Scene` por push_event; daqui pra frente nada
// mais toca o servidor para *tocar* a animação. Play, scrub, zoom, pan e
// export são 100% locais — é isso que deixa o editor fluido mesmo com
// latência alta.
//
// O modo de edição (spec 001) é a exceção deliberada: cada gesto vira um pedido
// de edição do texto (`canvas`), e a cena volta recompilada. Enquanto ela não
// volta, o canvas mostra o efeito otimista; quando volta, reconcilia com uma
// transição de 150ms para a diferença não parecer um glitch (§6).

import { render, measure } from "../brainagram/renderer";
import { Timeline, buildSchedule } from "../brainagram/timeline";
import { Viewport } from "../brainagram/viewport";
import { CanvasEditor } from "../brainagram/editor";
import { downloadPng, downloadSvg, triggerDownload } from "../brainagram/export";
import { downloadGif, GifCancelled } from "../brainagram/gif_export";
import { t, decimal } from "../brainagram/i18n";

const RECONCILE_MS = 150;
// Faixa de cima ocupada pela barra flutuante do canvas (no editor) — na
// apresentação a barra não existe e o diagrama sobe até perto da borda.
const INSET_EDIT = 52;
const INSET_PRESENT = 12;
// Escala mínima do enquadramento: o rótulo de seta (12px) nunca fica menor que
// isso na tela. Na apresentação é a escala de projetor (1:1); no editor, mais compacta.
const MIN_EDIT = 0.66;
const MIN_PRESENT = 1;

export const DiagramCanvas = {
  mounted() {
    this.canvas = this.el.querySelector("[data-bg-canvas]");
    this.scene = null;
    this.timeline = null;
    this.viewport = null;
    this.editor = null;
    this.mode = readMode();
    this.presenting = this.el.dataset.presenting === "true";
    this.selectedStep = null;
    this.followedEdge = null;
    this.spaceDown = false;
    this.spacePanned = false;
    this.pendingDrop = null;
    this.pendingCreated = null;

    this.handleEvent("bg:scene", ({ scene }) => this.setScene(scene));
    this.handleEvent("bg:created", (meta) => this.focusCreated(meta));

    this._delegate = (e) => this.onControl(e);
    document.addEventListener("click", this._delegate);
    document.addEventListener("input", this._delegate);
    document.addEventListener("change", this._delegate);
    this._keys = (e) => this.onKey(e);
    this._keysUp = (e) => this.onKeyUp(e);
    document.addEventListener("keydown", this._keys);
    document.addEventListener("keyup", this._keysUp);
    this._command = (e) => this.onCommand(e.detail || {});
    window.addEventListener("bg:command", this._command);

    // qualquer mudança no tamanho do canvas — janela, painel de código que some
    // na apresentação, gaveta — passa pelo `resize`, que só reenquadra se a
    // pessoa não tiver escolhido um zoom
    this._ro = new ResizeObserver(() => this.viewport && this.viewport.resize());
    this._ro.observe(this.canvas);

    // sair da página com alterações não salvas pede confirmação
    this._unload = (e) => {
      if (document.getElementById("editor")?.dataset.dirty !== "true") return;
      e.preventDefault();
      e.returnValue = "";
    };
    window.addEventListener("beforeunload", this._unload);

    this.syncMode();

    const seed = this.el.dataset.scene;
    if (seed) this.setScene(JSON.parse(seed));
  },

  destroyed() {
    document.removeEventListener("click", this._delegate);
    document.removeEventListener("input", this._delegate);
    document.removeEventListener("change", this._delegate);
    document.removeEventListener("keydown", this._keys);
    document.removeEventListener("keyup", this._keysUp);
    window.removeEventListener("bg:command", this._command);
    window.removeEventListener("beforeunload", this._unload);
    this._ro && this._ro.disconnect();
    this.timeline && this.timeline.destroy();
    this.viewport && this.viewport.destroy();
    this.editor && this.editor.destroy();
  },

  // O servidor trocou o modo (Apresentar / Editar / tecla P).
  updated() {
    const presenting = this.el.dataset.presenting === "true";
    if (presenting === this.presenting) return;
    this.presenting = presenting;
    this.applyPresenting();
  },

  // Apresentação: quem assiste não edita pelo canvas — arrastar move a tela,
  // e os participantes da sequência ficam fixos no topo ao rolar.
  applyPresenting() {
    this.el.classList.toggle("is-presenting", this.presenting);
    if (this.viewport) {
      this.viewport.insetTop = this.presenting ? INSET_PRESENT : INSET_EDIT;
      this.viewport.minReadable = this.presenting ? MIN_PRESENT : MIN_EDIT;
    }
    this.syncCaption();
    if (this.editor) {
      this.editor.clearSelection();
      this.editor.setEnabled(this.editing());
    }
    this.setDrawer(false);
    this.syncMode();
    // os painéis entraram/saíram: reenquadra para o novo modo
    requestAnimationFrame(() => this.viewport && this.viewport.fit());
  },

  editing() {
    return this.mode === "edit" && !this.presenting;
  },

  setScene(scene) {
    const prev = this.timeline;
    const prevScene = this.scene;
    // Editar o mesmo diagrama mantém o enquadramento; trocar de diagrama reenquadra.
    const keepView =
      this.viewport && prevScene && prevScene.title === scene.title && prevScene.kind === scene.kind;
    const savedView = keepView ? { ...this.viewport.view } : null;
    const progress = prev && prev.total > 0 ? prev.t / prev.total : null;
    const wasPlaying = prev ? prev.playing : false;
    // Só reconcilia versões do mesmo diagrama — trocar de exemplo não anima nada.
    const before = keepView ? positions(prevScene, this.pendingDrop) : null;
    this.pendingDrop = null;

    if (prev) prev.destroy();
    if (this.viewport) {
      this._userView = this.viewport.userView;
      this.viewport.destroy();
    }
    if (this.editor) this.editor.destroy();

    this.scene = scene;
    this.index = measure(render(this.canvas, scene));
    this.schedule = buildSchedule(scene);

    this.timeline = new Timeline(this.index, this.schedule, {
      loop: this.loop ?? false,
      onTick: (tl) => this.syncControls(tl),
    });

    this.headerTop = scene.kind === "sequence" && scene.nodes.length ? Math.min(...scene.nodes.map((n) => n.y)) : null;
    this.buildScrubber();

    this.viewport = new Viewport(this.index.svg, scene, {
      insetTop: this.presenting ? INSET_PRESENT : INSET_EDIT,
      minReadable: this.presenting ? MIN_PRESENT : MIN_EDIT,
      onChange: (s, view) => {
        this.setText("zoom", `${Math.round(s * 100)}%`);
        this.syncSticky(view);
        this.syncEdgeCue(view);
        this.editor && this.editor.selection && this.editor.placeBar();
      },
      canPan: () => {
        if (!this.editing()) return true;
        if (this.spaceDown) this.spacePanned = true;
        return this.spaceDown;
      },
    });

    if (savedView) {
      this.viewport.view = savedView;
      this.viewport.userView = this._userView ?? false;
      this.viewport.apply();
    }

    this.editor = new CanvasEditor({
      svg: this.index.svg,
      stage: this.el.querySelector("#canvas-overlay") || this.el,
      scene,
      viewport: this.viewport,
      push: (op, params) => this.pushEdit(op, params),
      step: () => this.selectedStep,
      isSpaceDown: () => this.spaceDown,
      onDrop: (drop) => (this.pendingDrop = drop),
      hint: (text) => this.setHint(text),
    });
    this.editor.setEnabled(this.editing());
    this.el.classList.toggle("is-presenting", this.presenting);

    this.index.svg.addEventListener("click", (e) => {
      const payload = e.target.closest("[data-payload]");
      if (payload) return this.togglePayload(payload.dataset.payload);
      const band = e.target.closest(".bg-band");
      if (band) this.gotoStep(Number(band.dataset.step));
    });

    // quem estava fixado continua fixado depois de editar o texto
    this.pinnedPayloads = this.pinnedPayloads || new Set();
    for (const id of this.pinnedPayloads) this.applyPin(id, true);

    this.syncLayoutButton();
    if (before) reconcile(this.index.svg, before, scene);

    // Digitar não deve te jogar de volta pro começo da animação.
    this.timeline.seek(progress !== null ? progress * this.schedule.total : 0);
    if (wasPlaying) this.timeline.play();

    if (this.pendingCreated) {
      const meta = this.pendingCreated;
      this.pendingCreated = null;
      requestAnimationFrame(() => this.focusCreated(meta));
    }
  },

  // Clique no chip (ou no balão aberto): fixa aberto / solta. Fixado, o balão
  // não fecha quando a animação passa — e entra na exportação SVG/PNG.
  togglePayload(id) {
    const pinned = !this.pinnedPayloads.has(id);
    pinned ? this.pinnedPayloads.add(id) : this.pinnedPayloads.delete(id);
    this.applyPin(id, pinned);
  },

  applyPin(id, pinned) {
    const item = this.index.edges.get(id);
    if (!item || !item.payload) return this.pinnedPayloads.delete(id);
    item.payload.classList.toggle("is-pinned", pinned);
    item.group.querySelector(".bg-payload-chip")?.classList.toggle("is-pinned", pinned);
  },

  // Antes de um gesto, o texto digitado ainda no debounce vai primeiro — a
  // edição do canvas tem que se aplicar sobre o que a pessoa está vendo.
  pushEdit(op, params = {}) {
    window.dispatchEvent(new CustomEvent("bg:flush-source"));
    this.pushEvent("canvas", { op, params });
  },

  // O servidor avisa o que o gesto criou; o nó ou a seta nova já chega pedindo nome.
  focusCreated(meta) {
    if (!this.editor || !meta) return;
    if (meta.node_id && !this.editor.nodes.has(meta.node_id)) return (this.pendingCreated = meta);
    if (meta.edge_id && !this.editor.edges.has(meta.edge_id)) return (this.pendingCreated = meta);
    if (meta.node_id) {
      this.editor.select("node", meta.node_id);
      this.editor.startRename(meta.node_id);
    } else if (meta.edge_id) {
      this.editor.select("edge", meta.edge_id);
      this.editor.startRelabel(meta.edge_id);
    }
  },

  gotoStep(index) {
    this.selectedStep = index;
    this.timeline.pause();
    this.timeline.gotoStep(index);
    this.focusCurrent();
  },

  // Cabeçalhos da sequência fixos no topo: ao rolar para baixo, a camada dos
  // participantes acompanha a borda de cima. Fora do modo de edição — lá os
  // nós são arrastados e precisam ficar onde a cena diz.
  syncSticky(view) {
    const layer = this.index && this.index.svg.querySelector(".bg-layer-nodes");
    if (!layer || this.headerTop === null || !view) return;
    let dy = 0;
    if (!this.editing()) {
      const rect = this.index.svg.getBoundingClientRect();
      const k = rect.width > 0 ? view.w / rect.width : 1;
      const top = view.y + ((this.presenting ? INSET_PRESENT : INSET_EDIT) + 4) * k;
      dy = Math.max(0, top - this.headerTop);
    }
    if (dy > 0) layer.setAttribute("transform", `translate(0 ${dy.toFixed(1)})`);
    else layer.removeAttribute("transform");
    if (layer.classList.contains("is-stuck") !== dy > 0) {
      layer.classList.toggle("is-stuck", dy > 0);
      // fixos, os cabeçalhos ficam por cima das setas que passam por baixo
      // deles; soltos, voltam para trás das setas, como o renderizador desenha
      const svg = this.index.svg;
      if (dy > 0) svg.appendChild(layer);
      else svg.insertBefore(layer, svg.querySelector(".bg-layer-edges"));
    }
  },

  // Quantos participantes ficam fora da tela, à direita: "+2 →". Só na
  // apresentação — no editor a barra de zoom e o arrastar já mostram o resto.
  syncEdgeCue(view) {
    const cue = this.overlayEl("ba-edgecue");
    if (!cue) return;
    let hidden = 0;
    if (this.presenting && view && this.scene.kind === "sequence") {
      hidden = this.scene.nodes.filter((n) => n.x > view.x + view.w - 8).length;
    }
    cue.hidden = hidden === 0;
    cue.textContent = hidden ? `+${hidden} →` : "";
  },

  // Legenda do passo atual sobre o canvas (apresentação): "3/5 · título".
  syncCaption() {
    const cap = this.overlayEl("ba-stepcaption");
    if (!cap) return;
    const tl = this.timeline;
    const step = tl && tl.started ? this.scene.steps.find((s) => s.index === tl.currentStep) : null;
    cap.hidden = !(this.presenting && step);
    cap.textContent = step ? `${step.index + 1}/${this.scene.steps.length} · ${t(step.label)}` : "";
  },

  overlayEl(cls) {
    const layer = this.el.querySelector("#canvas-overlay");
    if (!layer) return null;
    let el = layer.querySelector(`.${cls}`);
    if (!el) {
      el = document.createElement("p");
      el.className = cls;
      el.hidden = true;
      el.setAttribute("aria-hidden", "true");
      layer.appendChild(el);
    }
    return el;
  },

  // Faixa da barra de tempo, um segmento por passo, do tamanho da duração dele.
  buildScrubber() {
    const box = document.querySelector("[data-bg-scrub-segs]");
    if (!box || !this.schedule) return;
    box.replaceChildren(
      ...this.schedule.steps.map((step) => {
        const seg = document.createElement("span");
        seg.className = "ba-scrubber__seg";
        seg.style.flexGrow = String(Math.max(step.end - step.start, 1));
        seg.dataset.step = String(step.index);
        seg.appendChild(document.createElement("i"));
        return seg;
      }),
    );
  },

  // Área das setas do passo (coordenadas da cena), para a câmera.
  stepBox(index) {
    const step = this.scene.steps.find((s) => s.index === index);
    if (!step) return null;
    const boxes = [];
    for (const id of step.edge_ids) {
      const item = this.index.edges.get(id);
      if (item) boxes.push(item.group.getBBox());
    }
    const box = unionBox(boxes);
    // a faixa do passo (sequência) atravessa o diagrama inteiro: conta só na
    // vertical, para o título do passo aparecer junto — senão a área iria até
    // a borda esquerda e a câmera nunca andaria para a direita
    const band = this.index.steps.get(index)?.band;
    if (band && box) {
      const b = band.getBBox();
      const top = Math.min(box.y, b.y);
      box.h = Math.max(box.y + box.h, b.y + b.height) - top;
      box.y = top;
    }
    return box;
  },

  // Durante o play, a câmera acompanha a seta que está tocando — sem mudar o
  // zoom, e só quando ela sai da tela.
  followActive(tl) {
    if (!tl.playing || !tl.started) {
      this.followedEdge = null;
      return;
    }
    let active = null;
    for (const [id, entry] of this.schedule.entries) {
      if (!entry.note && tl.t >= entry.start && tl.t < entry.start + entry.dur) active = id;
    }
    if (!active || active === this.followedEdge) return;
    this.followedEdge = active;
    const item = this.index.edges.get(active);
    if (item) this.viewport.ensureVisible(toBox(item.group.getBBox()));
  },

  setDrawer(open) {
    const pane = document.getElementById("steps-pane");
    if (!pane) return;
    if (open) pane.setAttribute("data-open", "");
    else pane.removeAttribute("data-open");
    document.querySelectorAll('[data-bg-control="steps-drawer"]').forEach((b) => b.setAttribute("aria-expanded", String(open)));
    if (open) (pane.querySelector('[aria-current="step"]') || pane.querySelector(".ba-step"))?.focus();
  },

  onControl(e) {
    const target = e.target.closest("[data-bg-control], [data-bg-step]");
    if (!target || !this.timeline) return;

    if (target.dataset.bgStep !== undefined && e.type === "click") {
      this.gotoStep(Number(target.dataset.bgStep));
      return;
    }

    const action = target.dataset.bgControl;
    if (!action) return;

    if (e.type === "click" && target.closest("details.ba-dropdown")) {
      target.closest("details.ba-dropdown").removeAttribute("open");
    }

    this.runAction(action, target, e);
  },

  runAction(action, target, e) {
    switch (action) {
      case "toggle":
        e && e.preventDefault();
        this.timeline.toggle();
        break;
      case "restart":
        this.timeline.restart();
        break;
      case "next":
        this.timeline.pause();
        this.timeline.nextStep();
        this.selectedStep = this.timeline.currentStep;
        this.focusCurrent();
        break;
      case "prev":
        this.timeline.pause();
        this.timeline.prevStep();
        this.selectedStep = this.timeline.currentStep;
        this.focusCurrent();
        break;
      case "scrub":
        if (e && e.type === "input") {
          this.timeline.pause();
          this.timeline.seek((Number(target.value) / 1000) * this.timeline.total);
        }
        break;
      case "speed":
        if (e && e.type === "change") this.timeline.speed = Number(target.value);
        break;
      case "loop":
        if (e && e.type !== "click") break;
        this.loop = !this.loop;
        this.timeline.loop = this.loop;
        target && target.setAttribute("aria-pressed", String(this.loop));
        break;
      case "zoom-in":
        this.viewport.zoomBy(1.25);
        break;
      case "zoom-out":
        this.viewport.zoomBy(0.8);
        break;
      case "fit":
        this.viewport.fit();
        break;
      case "steps-drawer":
        if (e && e.type !== "click") break;
        this.setDrawer(!document.getElementById("steps-pane")?.hasAttribute("data-open"));
        break;
      case "mode-edit":
      case "mode-view":
        if (e && e.type !== "click") break;
        this.setMode(action === "mode-edit" ? "edit" : "view");
        break;
      case "add-node":
        if (e && e.type !== "click") break;
        this.addNodeAtCenter();
        break;
      case "connect":
        if (e && e.type !== "click") break;
        this.setMode("edit");
        this.editor.startConnect();
        break;
      case "export-svg":
        if (e && e.type !== "click") break;
        downloadSvg(this.index.svg, this.scene, `${slugify(this.scene.title)}.svg`);
        break;
      case "export-png":
        if (e && e.type !== "click") break;
        downloadPng(this.index.svg, this.scene, `${slugify(this.scene.title)}.png`);
        break;
      case "export-gif":
        if (e && e.type !== "click") break;
        this.exportGif("hd");
        break;
      case "export-brain": {
        if (e && e.type !== "click") break;
        const source = document.getElementById("source")?.value || "";
        const blob = new Blob([source], { type: "text/plain;charset=utf-8" });
        triggerDownload(URL.createObjectURL(blob), `${slugify(this.scene.title)}.brain`, true);
        break;
      }
      case "export-gif-light":
        if (e && e.type !== "click") break;
        this.exportGif("light");
        break;
    }
  },

  // Comandos vindos da paleta (⌘K).
  onCommand(detail) {
    if (!this.timeline) return;
    if (detail.step !== undefined) return this.gotoStep(detail.step);
    if (detail.action) this.runAction(detail.action, document.querySelector(`[data-bg-control="${detail.action}"]`), null);
  },

  // GIF: grava a animação inteira no próprio navegador. Enquanto grava, a faixa
  // de aviso mostra o progresso; Esc cancela.
  async exportGif(quality = "hd") {
    if (this.exporting) return;
    this.exporting = { cancelled: false };
    const job = this.exporting;
    const scene = this.scene;
    this.editor && this.editor.clearSelection();
    const buttons = document.querySelectorAll('[data-bg-control="export-gif"], [data-bg-control="export-gif-light"]');
    buttons.forEach((b) => b.setAttribute("aria-busy", "true"));
    this.setHint(t("Gerando GIF… {p}% · Esc cancela", { p: 0 }));

    try {
      const result = await downloadGif(
        {
          svg: this.index.svg,
          scene,
          timeline: this.timeline,
          quality,
          onProgress: (p) => this.setHint(t("Gerando GIF… {p}% · Esc cancela", { p: Math.round(p * 100) })),
          isCancelled: () => job.cancelled || this.scene !== scene,
        },
        `${slugify(scene.title)}${quality === "light" ? "-leve" : ""}.gif`,
      );
      this.flashHint(t("GIF pronto · {w}×{h} · {size}", { w: result.width, h: result.height, size: formatBytes(result.blob.size) }));
    } catch (error) {
      if (error instanceof GifCancelled) this.flashHint(t("Exportação do GIF cancelada"));
      else {
        console.error(error);
        this.flashHint(t("Não foi possível gerar o GIF"));
      }
    } finally {
      this.exporting = null;
      buttons.forEach((b) => b.removeAttribute("aria-busy"));
    }
  },

  flashHint(text) {
    this.setHint(text);
    clearTimeout(this._hintTimer);
    this._hintTimer = setTimeout(() => !this.exporting && this.setHint(null), 2800);
  },

  addNodeAtCenter() {
    this.setMode("edit");
    const rect = this.index.svg.getBoundingClientRect();
    const p = this.viewport.toScene(rect.left + rect.width / 2, rect.top + rect.height / 2);
    this.pushEdit("add_node", { label: t("Novo nó"), x: Math.round((p.x - 80) / 8) * 8, y: Math.round((p.y - 34) / 8) * 8 });
  },

  setMode(mode) {
    this.mode = mode;
    try {
      localStorage.setItem("bg:canvas-mode", mode);
    } catch (_e) {}
    this.syncMode();
    this.editor && this.editor.setEnabled(this.editing());
    if (this.viewport) this.syncSticky(this.viewport.view);
  },

  // Rádio de verdade: só a opção marcada entra na ordem do Tab; as setas trocam.
  syncMode() {
    document.querySelectorAll('[data-bg-control="mode-edit"], [data-bg-control="mode-view"]').forEach((b) => {
      const on = (b.dataset.bgControl === "mode-edit") === (this.mode === "edit");
      b.setAttribute("aria-checked", String(on));
      b.setAttribute("tabindex", on ? "0" : "-1");
    });
    this.el.classList.toggle("is-edit-mode", this.editing());
  },

  syncLayoutButton() {
    document.querySelectorAll("[data-bg-needs-layout]").forEach((b) => {
      b.disabled = !this.scene.has_layout;
      b.title = this.scene.has_layout ? t("Apaga as posições fixadas e volta ao layout automático") : t("Nenhum nó foi arrastado ainda");
    });
  },

  setHint(text) {
    const hint = this.el.querySelector("[data-bg-hint]");
    if (!hint) return;
    hint.textContent = text || "";
    hint.hidden = !text;
  },

  onKey(e) {
    if (!this.timeline) return;
    if (this.exporting && e.key === "Escape") {
      this.exporting.cancelled = true;
      e.preventDefault();
      return;
    }
    // Ctrl/⌘+S salva de qualquer lugar do editor — inclusive digitando no código
    if ((e.ctrlKey || e.metaKey) && !e.altKey && e.key.toLowerCase() === "s") {
      e.preventDefault();
      const save = document.getElementById("save-button");
      if (save) {
        window.dispatchEvent(new CustomEvent("bg:flush-source"));
        save.click();
      }
      return;
    }
    if (e.key === "Escape" && document.getElementById("steps-pane")?.hasAttribute("data-open")) {
      e.preventDefault();
      this.setDrawer(false);
      return;
    }
    if (isTyping(e.target)) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;

    const radio = e.target.closest && e.target.closest('[role="radiogroup"] [role="radio"]');
    if (radio && ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(e.key)) {
      e.preventDefault();
      this.setMode(this.mode === "edit" ? "view" : "edit");
      document.querySelector(`[data-bg-control="mode-${this.mode}"]`)?.focus();
      return;
    }

    if (this.editor && this.editor.onKey(e)) {
      e.preventDefault();
      return;
    }

    // Espaço: toque rápido toca/pausa; segurar e arrastar move a tela.
    if (e.key === " ") {
      e.preventDefault();
      if (!e.repeat) {
        this.spaceDown = true;
        this.spacePanned = false;
        this.el.classList.add("is-space");
      }
      return;
    }

    const map = {
      ArrowRight: () => this.runAction("next"),
      ArrowLeft: () => this.runAction("prev"),
      f: () => this.viewport.fit(),
      r: () => this.timeline.restart(),
      e: () => !this.presenting && this.setMode(this.mode === "edit" ? "view" : "edit"),
      p: () => this.pushEvent("present:toggle", {}),
    };

    const fn = map[e.key];
    if (fn) {
      e.preventDefault();
      fn();
    }
  },

  onKeyUp(e) {
    if (e.key !== " " || !this.spaceDown) return;
    this.spaceDown = false;
    this.el.classList.remove("is-space");
    if (!this.spacePanned && !isTyping(e.target)) this.timeline.toggle();
  },

  // Ao trocar de passo (←/→, clique), o passo inteiro vem para a tela.
  focusCurrent() {
    const box = this.stepBox(this.timeline.currentStep);
    if (box) this.viewport.ensureVisible(box);
  },

  syncControls(tl) {
    const started = tl.started;
    const current = tl.currentStep;
    const step = started ? this.scene.steps.find((s) => s.index === current) : null;
    const total = this.scene.steps.length;
    const label = step ? t("Passo {n} de {total} · {label}", { n: step.index + 1, total, label: t(step.label) }) : "—";
    // o anúncio (aria-live) só muda quando o passo muda, não a cada frame
    if (this._announced !== label) {
      this._announced = label;
      this.setText("step", label);
      this.setText("step-count", step ? `${step.index + 1} / ${total}` : `— / ${total}`);
      this.syncCaption();
    }
    const time = `${decimal(tl.t / 1000)} s / ${decimal(tl.total / 1000)} s`;
    this.setText("time", time);

    const scrub = document.querySelector('[data-bg-control="scrub"]');
    const ratio = tl.total > 0 ? tl.t / tl.total : 0;
    if (scrub) {
      if (document.activeElement !== scrub) scrub.value = String(Math.round(ratio * 1000));
      // o leitor de tela ouve o passo e o tempo, não "450 de 1000"
      scrub.setAttribute("aria-valuetext", step ? `${label} · ${time}` : time);
    }

    // segmentos da barra de tempo e barras de progresso dos cartões
    for (const s of this.schedule.steps) {
      const span = Math.max(s.end - s.start, 1);
      const fill = started ? Math.max(0, Math.min((tl.t - s.start) / span, 1)) : 0;
      const state = !started ? "" : s.index < current ? "done" : s.index === current ? "active" : "";
      const seg = document.querySelector(`.ba-scrubber__seg[data-step="${s.index}"]`);
      if (seg) {
        seg.dataset.state = state;
        seg.firstChild.style.width = `${(fill * 100).toFixed(1)}%`;
      }
      const bar = document.querySelector(`[data-bg-step-bar="${s.index}"]`);
      if (bar) bar.style.width = `${(fill * 100).toFixed(1)}%`;
    }

    // cada mensagem do painel de passos segue o estado da seta no diagrama
    document.querySelectorAll("[data-bg-msg]").forEach((li) => {
      const item = this.index.edges.get(li.dataset.bgMsg);
      const state = started && item ? item.group.dataset.state || "" : "";
      if (li.dataset.state !== state) li.dataset.state = state;
    });

    this.followActive(tl);

    document.querySelectorAll("[data-bg-play-icon]").forEach((node) => {
      node.hidden = (node.dataset.bgPlayIcon === "pause") !== tl.playing;
    });
    document.querySelectorAll('[data-bg-control="toggle"]').forEach((node) => {
      node.setAttribute("aria-label", tl.playing ? t("Pausar (Espaço)") : t("Tocar (Espaço)"));
    });

    document.querySelectorAll("[data-bg-step]").forEach((node) => {
      const index = Number(node.dataset.bgStep);
      if (started && index === current) node.setAttribute("aria-current", "step");
      else node.removeAttribute("aria-current");
      const done = started && index < current;
      if ((node.dataset.state === "done") !== done) node.dataset.state = done ? "done" : "";
    });
  },

  setText(name, value) {
    document.querySelectorAll(`[data-bg-display="${name}"]`).forEach((n) => (n.textContent = value));
  },
};

// Onde cada nó estava antes da cena nova — com o nó recém-solto na posição do
// gesto, que é onde a pessoa o está vendo.
function positions(scene, drop) {
  const map = new Map(scene.nodes.map((n) => [n.id, { x: n.x, y: n.y }]));
  if (drop && map.has(drop.id)) map.set(drop.id, { x: drop.x, y: drop.y });
  return map;
}

// FLIP: cada nó que mudou de lugar nasce onde estava e desliza até o lugar
// novo. Com movimento reduzido, é um corte.
function reconcile(svg, before, scene) {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  for (const node of scene.nodes) {
    const old = before.get(node.id);
    if (!old || (old.x === node.x && old.y === node.y)) continue;
    const g = svg.querySelector(`.bg-node[data-node="${CSS.escape(node.id)}"]`);
    if (!g) continue;
    g.style.transition = "none";
    g.style.transform = `translate(${old.x - node.x}px, ${old.y - node.y}px)`;
    requestAnimationFrame(() => {
      g.style.transition = `transform ${RECONCILE_MS}ms cubic-bezier(0.2, 0, 0, 1)`;
      g.style.transform = "";
    });
  }
}

function toBox(b) {
  return { x: b.x, y: b.y, w: b.width, h: b.height };
}

function unionBox(boxes) {
  if (boxes.length === 0) return null;
  const x1 = Math.min(...boxes.map((b) => b.x));
  const y1 = Math.min(...boxes.map((b) => b.y));
  const x2 = Math.max(...boxes.map((b) => b.x + b.width));
  const y2 = Math.max(...boxes.map((b) => b.y + b.height));
  return { x: x1, y: y1, w: x2 - x1, h: y2 - y1 };
}

function formatBytes(n) {
  if (n < 1024 * 1024) return `${Math.max(1, Math.round(n / 1024))} KB`;
  return `${decimal(n / (1024 * 1024))} MB`;
}

function isTyping(target) {
  const tag = (target && target.tagName ? target.tagName : "").toLowerCase();
  return tag === "textarea" || tag === "input" || tag === "select" || (target && target.isContentEditable);
}

function readMode() {
  try {
    return localStorage.getItem("bg:canvas-mode") === "view" ? "view" : "edit";
  } catch (_e) {
    return "edit";
  }
}

function slugify(title) {
  return (title || "diagrama")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}
