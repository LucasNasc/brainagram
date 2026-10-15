import type { CSSProperties, ReactNode } from "react";

interface Props {
  lane: number;
  href: string;
  current?: boolean;
  primary?: boolean;
  children: ReactNode;
}

/** O cabeçalho de um participante: na página, é um item de navegação. */
export function LaneHeader({ lane, href, current, primary, children }: Props) {
  const style = { "--lane": `var(--lane-${lane})` } as CSSProperties;
  return (
    <a
      className={primary ? "lp-lane lp-lane--primary" : "lp-lane"}
      href={href}
      style={style}
      aria-current={current ? "step" : undefined}
      {...(/^https?:/.test(href) ? { rel: "noopener" } : {})}
    >
      {children}
    </a>
  );
}
