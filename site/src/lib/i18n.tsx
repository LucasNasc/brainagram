import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { COPY, type Copy, type Lang } from "./copy";

interface I18n {
  lang: Lang;
  copy: Copy;
  toggle: () => void;
}

const Ctx = createContext<I18n | null>(null);
const KEY = "bg_site_lang";

function initialLang(): Lang {
  const fromUrl = new URLSearchParams(window.location.search).get("lang");
  if (fromUrl === "pt" || fromUrl === "en") return fromUrl;
  try {
    const saved = window.localStorage.getItem(KEY);
    if (saved === "pt" || saved === "en") return saved;
  } catch {
    // armazenamento bloqueado: segue pelo idioma do navegador
  }
  return navigator.language.toLowerCase().startsWith("pt") ? "pt" : "en";
}

export function I18nProvider({ children }: { children: ReactNode }) {
  const [lang, setLang] = useState<Lang>(initialLang);
  const copy = COPY[lang];

  useEffect(() => {
    document.documentElement.lang = copy.htmlLang;
    document.title = copy.title;
  }, [copy]);

  const toggle = useCallback(() => {
    setLang((current) => {
      const next: Lang = current === "pt" ? "en" : "pt";
      try {
        window.localStorage.setItem(KEY, next);
      } catch {
        // sem armazenamento, a escolha vale só para esta visita
      }
      return next;
    });
  }, []);

  const value = useMemo(() => ({ lang, copy, toggle }), [lang, copy, toggle]);
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useI18n(): I18n {
  const value = useContext(Ctx);
  if (!value) throw new Error("useI18n fora do I18nProvider");
  return value;
}

/** 4.8 → "4,8" em português, "4.8" em inglês. */
export function formatSeconds(lang: Lang, seconds: number): string {
  return seconds.toLocaleString(lang === "pt" ? "pt-BR" : "en-US", {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  });
}
