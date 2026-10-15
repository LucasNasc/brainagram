// Paleta de comandos (⌘K / Ctrl+K) — spec 001, §9.
//
// Todas as ações do editor num lugar só, com o atalho de cada uma à vista.
// Ações do canvas e do editor de texto viajam como `bg:command` (os hooks de
// lá escutam); as que mudam o fonte vão ao servidor pelo mesmo evento `canvas`
// dos gestos, e entram na mesma pilha de desfazer.

import { icon } from "../brainagram/icons";
import { t } from "../brainagram/i18n";

const isMac = /Mac|iPhone|iPad/.test(navigator.platform);
const MOD = isMac ? "⌘" : "Ctrl";

function staticCommands() {
  return [
    { id: "toggle", group: t("Reprodução"), label: t("Tocar / pausar"), icon: "play", keys: [t("Espaço")], run: (h) => h.command({ action: "toggle" }) },
    { id: "restart", group: t("Reprodução"), label: t("Reiniciar do começo"), icon: "arrow-path", keys: ["R"], run: (h) => h.command({ action: "restart" }) },
    { id: "loop", group: t("Reprodução"), label: t("Repetir em loop (liga/desliga)"), icon: "arrow-path-rounded-square", run: (h) => h.command({ action: "loop" }) },
    { id: "present", group: t("Reprodução"), label: t("Apresentar / editar"), icon: "presentation-chart-bar", keys: ["P"], run: (h) => h.pushEvent("present:toggle", {}) },
    { id: "add-node", group: t("Canvas"), label: t("Adicionar nó"), icon: "plus", run: (h) => h.command({ action: "add-node" }) },
    { id: "connect", group: t("Canvas"), label: t("Conectar dois nós"), icon: "link", run: (h) => h.command({ action: "connect" }) },
    { id: "untangle", group: t("Canvas"), label: t("Organizar setas (menos cruzamentos)"), icon: "sparkles", run: (h) => h.edit("untangle") },
    { id: "clear-layout", group: t("Canvas"), label: t("Soltar posições (voltar ao layout automático)"), icon: "arrow-uturn-left", run: (h) => h.edit("clear_layout") },
    { id: "mode", group: t("Canvas"), label: t("Alternar entre editar e mover a tela"), icon: "hand-raised", keys: ["E"], run: (h) => h.command({ action: h.editing() ? "mode-view" : "mode-edit" }) },
    { id: "format", group: t("Código"), label: t("Formatar código"), icon: "sparkles", keys: ["Shift", "Alt", "F"], run: (h) => h.command({ action: "format" }) },
    { id: "next-error", group: t("Código"), label: t("Ir para o próximo erro"), icon: "exclamation-triangle", keys: ["F8"], run: (h) => h.command({ action: "next-error" }) },
    { id: "switch-kind", group: t("Código"), label: t("Alternar tipo do diagrama (sequência ↔ arquitetura)"), icon: "arrows-right-left", run: (h) => h.edit("switch_kind") },
    { id: "undo", group: t("Código"), label: t("Desfazer"), icon: "arrow-uturn-left", keys: [MOD, "Z"], run: (h) => h.command({ action: "undo" }) },
    { id: "redo", group: t("Código"), label: t("Refazer"), icon: "arrow-uturn-right", keys: [MOD, "Shift", "Z"], run: (h) => h.command({ action: "redo" }) },
    { id: "import", group: t("Arquivo"), label: t("Importar diagrama (.brain, Mermaid, PlantUML)…"), icon: "document-plus", run: (h) => h.pushEvent("import:open", {}) },
    { id: "save", group: t("Arquivo"), label: t("Salvar"), icon: "cloud-arrow-up", run: (h) => h.pushEvent("save", {}) },
    { id: "export-svg", group: t("Arquivo"), label: t("Exportar como SVG"), icon: "code-bracket-square", run: (h) => h.command({ action: "export-svg" }) },
    { id: "export-png", group: t("Arquivo"), label: t("Exportar como PNG 2×"), icon: "photo", run: (h) => h.command({ action: "export-png" }) },
    { id: "export-gif", group: t("Arquivo"), label: t("Exportar como GIF animado"), icon: "play", run: (h) => h.command({ action: "export-gif" }) },
    { id: "export-brain", group: t("Arquivo"), label: t("Exportar como arquivo .brain"), icon: "arrow-down-tray", run: (h) => h.command({ action: "export-brain" }) },
    { id: "export-gif-light", group: t("Arquivo"), label: t("Exportar como GIF leve (para chats)"), icon: "play", run: (h) => h.command({ action: "export-gif-light" }) },
  ];
}

// Passos e exemplos vêm da página, então a paleta acompanha o diagrama atual.
function dynamicCommands() {
  const steps = [...document.querySelectorAll("[data-bg-step]")].map((el) => {
    const index = Number(el.dataset.bgStep);
    const title = el.querySelector(".ba-step__title")?.textContent.trim() || t("Passo {n}", { n: index + 1 });
    return { id: `step-${index}`, group: t("Passos"), label: t("Ir para {n} · {title}", { n: index + 1, title }), icon: "chevron-right", run: (h) => h.command({ step: index }) };
  });

  const examples = [...document.querySelectorAll("#examples-menu [phx-value-slug]")].map((el) => ({
    id: `example-${el.getAttribute("phx-value-slug")}`,
    group: t("Exemplos"),
    label: t("Carregar exemplo: {name}", { name: el.textContent.trim() }),
    icon: "document-plus",
    run: (h) => h.pushEvent("example", { slug: el.getAttribute("phx-value-slug") }),
  }));

  return [...steps, ...examples];
}

export const CommandPalette = {
  mounted() {
    this.open = false;
    this._keys = (e) => {
      if ((e.metaKey || e.ctrlKey) && !e.altKey && e.key.toLowerCase() === "k") {
        e.preventDefault();
        this.open ? this.close() : this.show();
      }
    };
    this._openEvent = () => this.show();
    document.addEventListener("keydown", this._keys);
    window.addEventListener("bg:palette", this._openEvent);
  },

  destroyed() {
    document.removeEventListener("keydown", this._keys);
    window.removeEventListener("bg:palette", this._openEvent);
  },

  command(detail) {
    window.dispatchEvent(new CustomEvent("bg:command", { detail }));
  },

  edit(op) {
    window.dispatchEvent(new CustomEvent("bg:flush-source"));
    this.pushEvent("canvas", { op, params: {} });
  },

  editing() {
    return !!document.querySelector("#stage.is-edit-mode");
  },

  show() {
    this.open = true;
    this.returnFocus = document.activeElement;
    this.all = [...staticCommands(), ...dynamicCommands()];
    this.active = 0;

    this.el.hidden = false;
    this.el.innerHTML = `
      <div class="ba-cmdk" role="dialog" aria-modal="true" aria-label="${t("Paleta de comandos")}">
        <div class="ba-cmdk__search">${icon("magnifying-glass")}
          <input id="cmdk-input" type="text" autocomplete="off" spellcheck="false" placeholder="${t("O que você quer fazer?")}" role="combobox" aria-expanded="true" aria-controls="cmdk-list" aria-label="${t("Buscar comando")}">
          <span class="ba-kbd">Esc</span>
        </div>
        <div class="ba-cmdk__list" id="cmdk-list" role="listbox"></div>
        <div class="ba-cmdk__foot"><span><span class="ba-kbd">↑</span><span class="ba-kbd">↓</span> ${t("navegar")}</span><span><span class="ba-kbd">↵</span> ${t("executar")}</span><span><span class="ba-kbd">${MOD}</span><span class="ba-kbd">K</span> ${t("abrir e fechar")}</span></div>
      </div>`;

    this.input = this.el.querySelector("input");
    this.list = this.el.querySelector(".ba-cmdk__list");
    this.input.addEventListener("input", () => {
      this.active = 0;
      this.renderList();
    });
    this.input.addEventListener("keydown", (e) => this.onKey(e));
    this.el.addEventListener("mousedown", (e) => {
      if (e.target === this.el) this.close();
    });
    this.list.addEventListener("mousedown", (e) => {
      const item = e.target.closest("[data-index]");
      if (!item) return;
      e.preventDefault();
      this.run(Number(item.dataset.index));
    });

    this.renderList();
    this.input.focus();
  },

  close() {
    this.open = false;
    this.el.hidden = true;
    this.el.innerHTML = "";
    this.returnFocus && this.returnFocus.focus && this.returnFocus.focus();
  },

  filtered() {
    const q = normalize(this.input.value.trim());
    if (!q) return this.all;
    return this.all.filter((c) => normalize(`${c.group} ${c.label}`).includes(q));
  },

  renderList() {
    const q = this.input.value.trim();
    this.items = this.filtered();
    let group = null;
    const html = [];

    this.items.forEach((c, i) => {
      if (c.group !== group) {
        group = c.group;
        html.push(`<div class="ba-menu__label">${group}</div>`);
      }
      const keys = (c.keys || []).map((k) => `<span class="ba-kbd">${k}</span>`).join("");
      html.push(
        `<div class="ba-menu__item" role="option" id="cmdk-${i}" data-index="${i}" aria-selected="${i === this.active}" ${i === this.active ? "data-active" : ""}>${icon(c.icon)}<span>${highlight(c.label, q)}</span>${keys ? `<span class="ba-row" style="gap:3px">${keys}</span>` : ""}</div>`,
      );
    });

    this.list.innerHTML = html.join("") || `<div class="ba-menu__label">${t("Nada encontrado")}</div>`;
    this.input.setAttribute("aria-activedescendant", `cmdk-${this.active}`);
    this.list.querySelector("[data-active]")?.scrollIntoView({ block: "nearest" });
  },

  onKey(e) {
    if (e.key === "Escape") {
      e.preventDefault();
      return this.close();
    }
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      const n = this.items.length || 1;
      this.active = (this.active + (e.key === "ArrowDown" ? 1 : -1) + n) % n;
      return this.renderList();
    }
    if (e.key === "Enter") {
      e.preventDefault();
      this.run(this.active);
    }
  },

  run(index) {
    const cmd = this.items[index];
    this.close();
    if (cmd) cmd.run(this);
  },
};

function normalize(text) {
  return text.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
}

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
}

// Destaca o trecho que casou com a busca (sem acento e sem caixa).
function highlight(label, q) {
  if (!q) return escapeHtml(label);
  const i = normalize(label).indexOf(normalize(q));
  if (i < 0) return escapeHtml(label);
  return escapeHtml(label.slice(0, i)) + `<mark>${escapeHtml(label.slice(i, i + q.length))}</mark>` + escapeHtml(label.slice(i + q.length));
}
