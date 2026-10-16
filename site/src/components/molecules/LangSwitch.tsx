import { useI18n } from "../../lib/i18n";
import { Flag } from "../atoms/Flag";

/** Troca entre inglês e português. Mostra a bandeira do idioma para o qual vai. */
export function LangSwitch() {
  const { lang, copy, toggle } = useI18n();
  const target = lang === "pt" ? "en" : "pt";
  return (
    <button type="button" className="lp-lang" onClick={toggle} aria-label={copy.langSwitch.otherName} title={copy.langSwitch.otherName}>
      <Flag lang={target} />
      {copy.langSwitch.other}
    </button>
  );
}
