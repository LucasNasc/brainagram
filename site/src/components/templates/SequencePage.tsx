import { lazy, Suspense, useEffect, useRef, type ReactNode } from "react";
import { useI18n } from "../../lib/i18n";
import { isCompact, isMid, laneXs } from "../../lib/lanes";
import { timeline } from "../../lib/timeline";
import { LaneNav } from "../organisms/LaneNav";
import { StageBoundary } from "../organisms/StageBoundary";
import { Transport } from "../organisms/Transport";

const PageDiagram = lazy(() => import("../../three/PageDiagram").then((m) => ({ default: m.PageDiagram })));

/**
 * O molde da página: um diagrama de sequência. Os participantes ficam fixos
 * no topo, as linhas de vida descem atrás do conteúdo e a barra de transporte
 * fica embaixo. Aqui as raias viram variáveis CSS (`--lane-0` … `--lane-4`).
 */
export function SequencePage({ children }: { children: ReactNode }) {
  const { copy, lang } = useI18n();
  const main = useRef<HTMLElement>(null);

  useEffect(() => {
    const root = document.documentElement;
    const layout = () => {
      const width = root.clientWidth;
      laneXs(width).forEach((x, i) => root.style.setProperty(`--lane-${i}`, `${x}px`));
      root.toggleAttribute("data-compact", isCompact(width));
      root.toggleAttribute("data-mid", isMid(width));
      timeline.measure();
    };
    layout();
    timeline.startIntro();
    const observer = new ResizeObserver(layout);
    observer.observe(main.current!);
    window.addEventListener("resize", layout);
    window.addEventListener("scroll", timeline.sync, { passive: true });
    document.fonts?.ready.then(layout);
    return () => {
      observer.disconnect();
      window.removeEventListener("resize", layout);
      window.removeEventListener("scroll", timeline.sync);
    };
  }, []);

  // Trocar de idioma muda as alturas: mede de novo.
  useEffect(() => {
    timeline.measure();
  }, [lang]);

  return (
    <>
      <a className="lp-skip" href="#conteudo">
        {copy.skip}
      </a>
      <StageBoundary>
        <Suspense fallback={null}>
          <PageDiagram />
        </Suspense>
      </StageBoundary>
      <LaneNav />
      <main id="conteudo" ref={main}>
        {children}
      </main>
      <Transport />
    </>
  );
}
