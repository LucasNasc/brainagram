// Troca de idioma pelo menu de bandeiras do topo.
//
// O idioma vale para a página inteira (textos do servidor e deste JS), então
// a troca é: gravar o cookie que o servidor lê, recarregar. Para não perder
// nada, o código do editor vai antes para o sessionStorage e volta quando o
// editor monta de novo (`takeRestoredSource`) — inclusive o que ainda não foi
// salvo.

const COOKIE = "bg_locale";
const STASH = "bg:restore";
const ONE_YEAR = 60 * 60 * 24 * 365;

export function installLocaleSwitch() {
  document.addEventListener("click", (e) => {
    const button = e.target.closest("[data-bg-locale]");
    if (!button || button.getAttribute("aria-checked") === "true") return;

    stashSource();
    document.cookie = `${COOKIE}=${button.dataset.bgLocale}; path=/; max-age=${ONE_YEAR}; samesite=lax`;
    const group = button.closest(".ba-locale");
    if (group) group.dataset.state = "switching";
    window.location.reload();
  });
}

function stashSource() {
  const textarea = document.getElementById("source");
  if (!textarea) return;
  try {
    sessionStorage.setItem(STASH, JSON.stringify({ path: window.location.pathname, source: textarea.value }));
  } catch (_e) {
    // armazenamento bloqueado: troca o idioma mesmo assim
  }
}

// O código guardado antes da troca, se for desta mesma página. Lê uma vez só.
export function takeRestoredSource() {
  try {
    const raw = sessionStorage.getItem(STASH);
    if (!raw) return null;
    sessionStorage.removeItem(STASH);
    const { path, source } = JSON.parse(raw);
    return path === window.location.pathname && typeof source === "string" ? source : null;
  } catch (_e) {
    return null;
  }
}
