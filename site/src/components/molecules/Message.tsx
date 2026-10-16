import { useEffect, useRef, type CSSProperties, type ReactNode } from "react";
import { timeline } from "../../lib/timeline";
import type { EdgeKind } from "../../lib/tokens";

interface Props {
  from: number;
  to: number;
  kind?: EdgeKind;
  href?: string;
  /** Até onde a seta toca (0..1); menor que 1, ela para no meio e espera. */
  cap?: number;
  children: ReactNode;
}

/**
 * Uma mensagem do diagrama da página. O rótulo é DOM (texto de verdade, e um
 * link quando tem `href`); a seta e o impulso são desenhados pelo WebGL na
 * altura deste elemento.
 */
export function Message({ from, to, kind = "sync", href, cap = 1, children }: Props) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => timeline.addMessage(ref.current!, from, to, kind, cap), [from, to, kind, cap]);

  const style = { "--from": `var(--lane-${from})`, "--to": `var(--lane-${to})` } as CSSProperties;
  return (
    <div ref={ref} className="lp-msg" data-kind={kind} data-state="pending" style={style}>
      {href ? (
        <a className="lp-msg__label" href={href} {...(/^https?:/.test(href) ? { rel: "noopener" } : {})}>
          {children}
        </a>
      ) : (
        <span className="lp-msg__label">{children}</span>
      )}
    </div>
  );
}
