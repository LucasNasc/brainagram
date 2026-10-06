// Menus `<details class="ba-dropdown">`: o navegador abre e fecha no clique do
// `<summary>`, mas não fecha sozinho quando se clica fora, quando se escolhe
// uma opção nem no Esc. Isto completa o comportamento — para a página toda,
// inclusive menus que o LiveView acabou de inserir.

export function installDropdowns() {
  const closeAll = (except = null) => {
    document.querySelectorAll("details.ba-dropdown[open]").forEach((d) => {
      if (d !== except) d.removeAttribute("open");
    });
  };

  document.addEventListener("click", (e) => {
    const inside = e.target.closest("details.ba-dropdown");
    // clique fora: fecha tudo; clique num summary: fecha os outros
    closeAll(inside);
    // escolheu uma opção: fecha este também (a ação já foi disparada)
    if (inside && e.target.closest(".ba-menu__item")) inside.removeAttribute("open");
  });

  document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape") return;
    const open = document.querySelector("details.ba-dropdown[open]");
    if (!open) return;
    open.removeAttribute("open");
    open.querySelector("summary")?.focus();
  });
}
