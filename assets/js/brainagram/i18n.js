// Textos da interface no JavaScript: português (padrão), inglês, chinês,
// russo, italiano, japonês e hindi.
//
// Mesmo contrato do Gettext no servidor: o texto em português é a chave e
// cada dicionário (`locales/<idioma>.js`) traz a tradução. Chave ausente num
// dicionário cai no inglês, e depois no próprio português. O idioma é o do `<html lang>`, que o servidor
// escreve a partir do cookie `bg_locale` — trocar de idioma recarrega a
// página, então não há o que observar aqui.
//
// Variáveis entre chaves: t("Passo {n}", { n: 3 }).

import en from "./locales/en";
import zh from "./locales/zh";
import ru from "./locales/ru";
import it from "./locales/it";
import ja from "./locales/ja";
import hi from "./locales/hi";

const DICTS = { en, zh, ru, it, ja, hi };

// `<html lang>` → dicionário e locale do Intl.
const LANGS = {
  en: { dict: "en", intl: "en" },
  zh: { dict: "zh", intl: "zh-CN" },
  ru: { dict: "ru", intl: "ru" },
  it: { dict: "it", intl: "it" },
  ja: { dict: "ja", intl: "ja" },
  hi: { dict: "hi", intl: "hi" },
};

// O idioma da página, como chave de LANGS ("pt-BR" para o padrão).
export function lang() {
  const code = (document.documentElement.lang || "pt-BR").toLowerCase().split("-")[0];
  return LANGS[code] ? code : "pt-BR";
}

export function t(text, vars = {}) {
  const code = lang();
  const base = code === "pt-BR" ? text : (DICTS[LANGS[code].dict][text] ?? en[text] ?? text);
  return base.replace(/\{(\w+)\}/g, (match, key) => (key in vars ? String(vars[key]) : match));
}

// Número com a vírgula ou o ponto do idioma.
export function decimal(n, digits = 1) {
  const code = lang();
  const intl = code === "pt-BR" ? "pt-BR" : LANGS[code].intl;
  return n.toLocaleString(intl, { minimumFractionDigits: digits, maximumFractionDigits: digits });
}
