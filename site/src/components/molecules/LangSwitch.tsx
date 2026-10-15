import { useI18n } from "../../lib/i18n";

/** Troca entre português e inglês. Mostra o idioma para o qual vai. */
export function LangSwitch() {
  const { copy, toggle } = useI18n();
  return (
    <button type="button" className="lp-lang" onClick={toggle} aria-label={copy.langSwitch.otherName} title={copy.langSwitch.otherName}>
      {copy.langSwitch.other}
    </button>
  );
}
