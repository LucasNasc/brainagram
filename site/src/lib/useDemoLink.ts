import { DEMO_URL, REPO_URL } from "./config";
import { useI18n } from "./i18n";

interface DemoLink {
  href: string;
  /** Rótulo do botão principal. */
  label: string;
  /** Rótulo curto, para o participante no topo. */
  short: string;
  /** Rótulo da seta do início. */
  message: string;
}

/**
 * Para onde vai a ação principal. Com VITE_DEMO_URL, é a demo pública; sem
 * ela, é o README no GitHub, e nenhum rótulo promete uma demo que não existe.
 */
export function useDemoLink(): DemoLink {
  const { copy } = useI18n();
  if (DEMO_URL) {
    return { href: DEMO_URL, label: copy.cta.demo, short: copy.lanes[4], message: copy.hero.message };
  }
  return { href: `${REPO_URL}#readme`, label: copy.cta.demoRepo, short: "GitHub", message: copy.hero.messageRepo };
}
