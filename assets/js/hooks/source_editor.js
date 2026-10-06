// Editor de código: uma pilha de desfazer só, autocomplete e atalhos.
//
// Undo/redo (spec 001, §8): todo gesto — digitar, arrastar no canvas, importar,
// formatar — produz um fonte novo, então desfazer é voltar ao fonte anterior.
// A pilha vive aqui, no cliente, e guarda os últimos 100 estados. Arrastar uma
// caixa, digitar e desfazer duas vezes funciona porque as duas ações estão na
// mesma linha do tempo: são a mesma coisa.

import { arrowGlyph } from "../brainagram/icons";
import { t } from "../brainagram/i18n";
import { takeRestoredSource } from "../brainagram/locale";

const LIMIT = 100;
const TYPING_PAUSE = 450;
const LINE_H = 20;

const KINDS = ["actor", "participant", "service", "component", "database", "queue", "external", "system", "node", "boundary"];
const KIND_HINT = {
  actor: "quem inicia",
  participant: "participante genérico",
  service: "serviço",
  component: "componente",
  database: "banco de dados",
  queue: "fila",
  external: "sistema externo",
  system: "sistema",
  node: "nó de implantação",
  boundary: "fronteira",
};
const KEYWORDS = [
  ["step", 'step "…" {', "um passo da animação"],
  ["group", 'group "…" {', "agrupamento"],
  ["note", "note over ", "nota"],
  ["layout", "layout {", "posições fixadas"],
  ["payload", "payload: ", "o que a mensagem carrega"],
  ['payload """', 'payload """', "payload em várias linhas"],
];
const ARROWS = [
  ["->", "chamada síncrona", "sync"],
  ["-->", "retorno", "return"],
  ["->>", "assíncrona", "async"],
  ["-x", "falha / timeout", "fail"],
];

export const SourceEditor = {
  mounted() {
    this.ta = this.el;
    // voltando de uma troca de idioma: o código de antes, mesmo sem salvar
    const restored = takeRestoredSource();
    if (restored !== null && restored !== this.ta.value) {
      this.ta.value = restored;
      this.pushEvent("edit", { source: restored });
    }
    this.history = [this.ta.value];
    this.pointer = 0;
    this.lastSent = this.ta.value;
    this.typingTimer = null;
    this.popup = null;

    this.handleEvent("bg:source", (payload) => this.applyServer(payload));

    this._input = () => this.onInput();
    this._keydown = (e) => this.onKeydown(e);
    this._globalKeys = (e) => this.onGlobalKey(e);
    this._flush = () => this.flush();
    this._command = (e) => this.onCommand(e.detail || {});
    this._blur = () => setTimeout(() => this.closePopup(), 120);

    this.ta.addEventListener("input", this._input);
    this.ta.addEventListener("keydown", this._keydown);
    this.ta.addEventListener("blur", this._blur);
    document.addEventListener("keydown", this._globalKeys);
    window.addEventListener("bg:flush-source", this._flush);
    window.addEventListener("bg:command", this._command);
    this.syncUndoButtons();
  },

  destroyed() {
    document.removeEventListener("keydown", this._globalKeys);
    window.removeEventListener("bg:flush-source", this._flush);
    window.removeEventListener("bg:command", this._command);
    this.closePopup();
  },

  // O LiveView não mexe no valor de um campo com foco; por isso o texto que o
  // servidor reescreve (gesto no canvas, import, formatar) chega por evento.
  applyServer({ source, line, record = true }) {
    if (typeof source !== "string") return;
    if (this.ta.value !== source) {
      const caret = this.caretLineCol();
      this.ta.value = source;
      this.placeCaret(line || caret.line, caret.col);
    }
    this.lastSent = source;
    if (record) this.record(source);
  },

  // ── histórico ────────────────────────────────────────────────────────────

  record(source) {
    if (this.history[this.pointer] === source) return;
    this.history = this.history.slice(0, this.pointer + 1);
    this.history.push(source);
    if (this.history.length > LIMIT) this.history.shift();
    this.pointer = this.history.length - 1;
    this.syncUndoButtons();
  },

  commitTyping() {
    clearTimeout(this.typingTimer);
    this.typingTimer = null;
    this.record(this.ta.value);
  },

  undo() {
    this.commitTyping();
    if (this.pointer === 0) return;
    this.pointer -= 1;
    this.restore();
  },

  redo() {
    this.commitTyping();
    if (this.pointer >= this.history.length - 1) return;
    this.pointer += 1;
    this.restore();
  },

  restore() {
    const source = this.history[this.pointer];
    const caret = this.caretLineCol();
    this.ta.value = source;
    this.placeCaret(caret.line, caret.col);
    this.send(source);
    this.syncUndoButtons();
  },

  send(source) {
    this.lastSent = source;
    this.pushEvent("edit", { source });
  },

  // Antes de um gesto no canvas: o que está no debounce vai agora.
  flush() {
    if (this.ta.value !== this.lastSent) this.send(this.ta.value);
    this.commitTyping();
  },

  syncUndoButtons() {
    document.querySelectorAll('[data-bg-history="undo"]').forEach((b) => (b.disabled = this.pointer === 0));
    document.querySelectorAll('[data-bg-history="redo"]').forEach((b) => (b.disabled = this.pointer >= this.history.length - 1));
  },

  onInput() {
    clearTimeout(this.typingTimer);
    this.typingTimer = setTimeout(() => this.commitTyping(), TYPING_PAUSE);
    // o `phx-change` do formulário leva o texto ao servidor (com debounce);
    // `flush/0` antecipa o envio quando um gesto não pode esperar
    this.updatePopup();
  },

  // ── atalhos ──────────────────────────────────────────────────────────────

  onGlobalKey(e) {
    const mod = e.metaKey || e.ctrlKey;
    const inOtherField = e.target !== this.ta && /^(input|textarea|select)$/i.test(e.target.tagName || "");
    if (inOtherField) return;

    if (mod && !e.altKey && e.key.toLowerCase() === "z") {
      e.preventDefault();
      e.shiftKey ? this.redo() : this.undo();
      return;
    }
    if (mod && !e.altKey && e.key.toLowerCase() === "y") {
      e.preventDefault();
      this.redo();
      return;
    }
    if (e.key === "F8") {
      e.preventDefault();
      this.nextError(e.shiftKey ? -1 : 1);
      return;
    }
    if (e.shiftKey && e.altKey && (e.key === "F" || e.key === "f" || e.code === "KeyF")) {
      e.preventDefault();
      this.flush();
      this.pushEvent("canvas", { op: "format", params: {} });
    }
  },

  onKeydown(e) {
    if (this.popup && this.handlePopupKey(e)) return;

    if (e.altKey && !e.ctrlKey && !e.metaKey && (e.key === "ArrowUp" || e.key === "ArrowDown")) {
      e.preventDefault();
      this.flush();
      const direction = e.key === "ArrowUp" ? "up" : "down";
      this.pushEvent("canvas", { op: "move_step", params: { line: this.caretLineCol().line, direction } });
      return;
    }
  },

  onCommand(detail) {
    if (detail.action === "undo") this.undo();
    if (detail.action === "redo") this.redo();
    if (detail.action === "next-error") this.nextError(1);
    if (detail.action === "format") {
      this.flush();
      this.pushEvent("canvas", { op: "format", params: {} });
    }
  },

  // F8: próxima linha com erro de sintaxe (Shift+F8 volta).
  nextError(dir) {
    const lines = JSON.parse(this.ta.dataset.errorLines || "[]");
    if (lines.length === 0) return;
    const current = this.caretLineCol().line;
    const sorted = [...lines].sort((a, b) => a - b);
    const target =
      dir > 0
        ? sorted.find((l) => l > current) ?? sorted[0]
        : [...sorted].reverse().find((l) => l < current) ?? sorted[sorted.length - 1];
    this.selectLine(target);
  },

  selectLine(line) {
    const starts = lineStarts(this.ta.value);
    const start = starts[line - 1] ?? 0;
    const end = (starts[line] ?? this.ta.value.length + 1) - 1;
    this.ta.focus();
    this.ta.setSelectionRange(start, end);
    this.ta.scrollTop = Math.max(0, (line - 4) * LINE_H);
  },

  caretLineCol() {
    const before = this.ta.value.slice(0, this.ta.selectionStart);
    const lines = before.split("\n");
    return { line: lines.length, col: lines[lines.length - 1].length };
  },

  placeCaret(line, col) {
    const starts = lineStarts(this.ta.value);
    const start = starts[Math.min(line, starts.length) - 1] ?? 0;
    const lineEnd = (starts[Math.min(line, starts.length)] ?? this.ta.value.length + 1) - 1;
    const pos = Math.min(start + col, lineEnd);
    if (document.activeElement === this.ta) this.ta.setSelectionRange(pos, pos);
  },

  // ── autocomplete ─────────────────────────────────────────────────────────

  // Três momentos: começo de linha (tipos de nó, palavras-chave e ids), depois
  // de um id (setas) e depois de uma seta (ids). Os ids vêm da AST atual.
  suggestions() {
    const pos = this.ta.selectionStart;
    if (pos !== this.ta.selectionEnd) return null;
    const lineStart = this.ta.value.lastIndexOf("\n", pos - 1) + 1;
    const before = this.ta.value.slice(lineStart, pos);
    if (/["#]/.test(before) || before.includes(":")) return null;

    const ids = JSON.parse(this.ta.dataset.ids || "[]");
    const idItem = (id) => ({ text: id, hint: "nó", insert: id + " " });

    let m;
    if ((m = before.match(/^(\s*)([A-Za-z_][\w.-]*)?$/))) {
      const prefix = m[2] || "";
      if (!prefix) return null;
      const items = [
        ...KINDS.map((k) => ({ text: k, hint: KIND_HINT[k], insert: k + " " })),
        ...KEYWORDS.map(([k, insert, hint]) => ({ text: k, hint, insert })),
        ...ids.map(idItem),
      ];
      return { prefix, items: filter(items, prefix) };
    }

    if ((m = before.match(/^\s*[A-Za-z_][\w.-]*\s+(-[->x]*)?$/))) {
      const prefix = m[1] || "";
      const items = ARROWS.map(([a, hint, kind]) => ({ text: a, hint, insert: a + " ", arrow: kind }));
      return { prefix, items: items.filter((i) => i.text.startsWith(prefix)) };
    }

    if ((m = before.match(/^\s*[A-Za-z_][\w.-]*\s*(?:->>|-->|->|-x)\s*([A-Za-z_][\w.-]*)?$/))) {
      const prefix = m[1] || "";
      return { prefix, items: filter(ids.map((id) => ({ text: id, hint: "nó", insert: id + " : " })), prefix) };
    }

    return null;
  },

  updatePopup() {
    const found = this.suggestions();
    if (!found || found.items.length === 0 || (found.items.length === 1 && found.items[0].text === found.prefix)) {
      return this.closePopup();
    }
    this.openPopup(found);
  },

  openPopup({ prefix, items }) {
    if (!this.popup) {
      this.popup = document.createElement("div");
      this.popup.className = "ba-complete";
      this.popup.setAttribute("role", "listbox");
      this.popup.addEventListener("mousedown", (e) => {
        const item = e.target.closest("[data-index]");
        if (!item) return;
        e.preventDefault();
        this.popupState.active = Number(item.dataset.index);
        this.accept();
      });
      // numa camada que o LiveView não corrige — senão o próximo patch o apagaria
      this.layer().appendChild(this.popup);
    }

    this.popupState = { prefix, items: items.slice(0, 8), active: 0 };
    this.renderPopup();

    const at = caretCoordinates(this.ta);
    const parent = this.layer().getBoundingClientRect();
    const ta = this.ta.getBoundingClientRect();
    this.popup.style.left = `${Math.max(8, Math.min(ta.left - parent.left + at.left, parent.width - 310))}px`;
    this.popup.style.top = `${ta.top - parent.top + at.top + LINE_H + 2}px`;
  },

  layer() {
    return document.getElementById("complete-layer") || this.ta.parentElement;
  },

  renderPopup() {
    const { items, active } = this.popupState;
    this.popup.innerHTML =
      items
        .map(
          (item, i) =>
            `<div class="ba-complete__item" role="option" data-index="${i}" aria-selected="${i === active}"><span class="ba-complete__glyph">${item.arrow ? arrowGlyph(item.arrow) : ""}</span><code>${escapeHtml(item.text)}</code><small>${escapeHtml(t(item.hint))}</small></div>`,
        )
        .join("") +
      `<div class="ba-complete__foot"><span class="ba-kbd">↵</span> ${t("inserir")} <span class="ba-kbd">Esc</span> ${t("fechar")}</div>`;
  },

  handlePopupKey(e) {
    const st = this.popupState;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const d = e.key === "ArrowDown" ? 1 : -1;
      st.active = (st.active + d + st.items.length) % st.items.length;
      this.renderPopup();
      return true;
    }
    if (e.key === "Enter" || e.key === "Tab") {
      e.preventDefault();
      this.accept();
      return true;
    }
    if (e.key === "Escape") {
      e.preventDefault();
      this.closePopup();
      return true;
    }
    return false;
  },

  accept() {
    const { prefix, items, active } = this.popupState;
    const item = items[active];
    this.closePopup();
    if (!item) return;
    const pos = this.ta.selectionStart;
    this.ta.setSelectionRange(pos - prefix.length, pos);
    // execCommand mantém o desfazer nativo do navegador e dispara `input`
    document.execCommand("insertText", false, item.insert);
  },

  closePopup() {
    if (this.popup) this.popup.remove();
    this.popup = null;
    this.popupState = null;
  },
};

function filter(items, prefix) {
  const p = prefix.toLowerCase();
  const seen = new Set();
  return items.filter((i) => {
    if (seen.has(i.text) || !i.text.toLowerCase().startsWith(p)) return false;
    seen.add(i.text);
    return true;
  });
}

function lineStarts(text) {
  const starts = [0];
  for (let i = 0; i < text.length; i++) if (text[i] === "\n") starts.push(i + 1);
  return starts;
}

// Posição do cursor dentro do textarea, pela técnica do espelho: um div com o
// mesmo estilo recebe o texto até o cursor, e um marcador diz onde ele caiu.
function caretCoordinates(ta) {
  const div = document.createElement("div");
  const style = getComputedStyle(ta);
  for (const prop of ["fontFamily", "fontSize", "fontWeight", "lineHeight", "letterSpacing", "tabSize", "paddingTop", "paddingLeft", "paddingRight", "borderLeftWidth", "borderTopWidth", "boxSizing", "width"]) {
    div.style[prop] = style[prop];
  }
  div.style.position = "absolute";
  div.style.visibility = "hidden";
  div.style.whiteSpace = "pre-wrap";
  div.style.wordWrap = "break-word";
  div.textContent = ta.value.slice(0, ta.selectionStart);
  const mark = document.createElement("span");
  mark.textContent = "​";
  div.appendChild(mark);
  document.body.appendChild(div);
  const coords = { left: mark.offsetLeft, top: mark.offsetTop - ta.scrollTop };
  div.remove();
  return coords;
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
}
