import { useI18n } from "../../lib/i18n";
import { Flag } from "../atoms/Flag";

/** Troca entre inglês e português. Mostra o idioma atual; clicar troca. */
export function LangSwitch() {
  const { lang, copy, toggle } = useI18n();
  return (
    <button type="button" className="lp-lang" onClick={toggle} aria-label={copy.langSwitch.otherName} title={copy.langSwitch.otherName}>
      <Flag lang={lang} />
      <span className="lp-lang__code">{copy.langSwitch.code}</span>
    </button>
  );
}
