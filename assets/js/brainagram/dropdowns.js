// Menus `<details class="ba-dropdown">`: o navegador abre e fecha no clique do
// `<summary>`, mas não fecha sozinho quando se clica fora, quando se escolhe
// uma opção nem no Esc — e um `role="menu"` promete navegação pelas setas.
// Isto completa o comportamento, para a página toda, inclusive menus que o
// LiveView acabou de inserir.

const ITEMS = '.ba-menu__item:not([aria-disabled="true"]):not([disabled])';

export function installDropdowns() {
  const closeAll = (except = null) => {
    document.querySelectorAll("details.ba-dropdown[open]").forEach((d) => {
      if (d !== except) d.removeAttribute("open");
    });
  };

  const items = (details) => Array.from(details.querySelectorAll(ITEMS)).filter((el) => el.offsetParent !== null);

  document.addEventListener("click", (e) => {
    const inside = e.target.closest("details.ba-dropdown");
    // clique fora: fecha tudo; clique num summary: fecha os outros
    closeAll(inside);
    // escolheu uma opção: fecha este também (a ação já foi disparada)
    if (inside && e.target.closest(".ba-menu__item")) inside.removeAttribute("open");
  });

  document.addEventListener("keydown", (e) => {
    const open = document.querySelector("details.ba-dropdown[open]");

    // ↓ (ou Enter/Espaço) no botão do menu fechado: abre e entra na lista
    const summary = e.target.closest && e.target.closest("details.ba-dropdown > summary");
    if (summary && !summary.parentElement.open && (e.key === "ArrowDown" || e.key === "ArrowUp")) {
      e.preventDefault();
      closeAll();
      summary.parentElement.setAttribute("open", "");
      const list = items(summary.parentElement);
      (e.key === "ArrowUp" ? list[list.length - 1] : list[0])?.focus();
      return;
    }

    if (!open) return;

    if (e.key === "Escape") {
      open.removeAttribute("open");
      open.querySelector("summary")?.focus();
      return;
    }

    if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(e.key)) return;
    const list = items(open);
    if (list.length === 0) return;
    e.preventDefault();
    const at = list.indexOf(document.activeElement);
    let next;
    if (e.key === "Home") next = 0;
    else if (e.key === "End") next = list.length - 1;
    else if (e.key === "ArrowDown") next = at < 0 ? 0 : (at + 1) % list.length;
    else next = at < 0 ? list.length - 1 : (at - 1 + list.length) % list.length;
    list[next].focus();
  });

  // aberto pelo teclado (Enter/Espaço no summary): o foco vai ao primeiro item
  document.addEventListener(
    "toggle",
    (e) => {
      const details = e.target;
      if (!(details instanceof HTMLDetailsElement) || !details.classList.contains("ba-dropdown") || !details.open) return;
      if (document.activeElement === details.querySelector("summary") && details.matches(":focus-within")) {
        const first = items(details)[0];
        if (first && details.dataset.openedBy !== "pointer") first.focus();
      }
      delete details.dataset.openedBy;
    },
    true,
  );

  // abrir com o mouse não rouba o foco para dentro da lista
  document.addEventListener("pointerdown", (e) => {
    const summary = e.target.closest && e.target.closest("details.ba-dropdown > summary");
    if (summary) summary.parentElement.dataset.openedBy = "pointer";
  });
}
