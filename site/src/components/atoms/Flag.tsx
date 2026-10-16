import type { Lang } from "../../lib/copy";

const STRIPES = Array.from({ length: 7 }, (_, i) => (i * 2 * 14) / 13);
const STARS = Array.from({ length: 12 }, (_, i) => [1.3 + (i % 4) * 2.1, 1.3 + Math.floor(i / 4) * 2.3]);

/** A bandeira de cada idioma, desenhada como no app (20 × 14). */
export function Flag({ lang }: { lang: Lang }) {
  return (
    <svg className="lp-flag" viewBox="0 0 20 14" width="20" height="14" aria-hidden="true" focusable="false">
      {lang === "pt" ? (
        <>
          <rect width="20" height="14" fill="var(--flag-br-green)" />
          <path d="M10 1.7 18.3 7 10 12.3 1.7 7Z" fill="var(--flag-br-yellow)" />
          <circle cx="10" cy="7" r="3.3" fill="var(--flag-br-blue)" />
          <path d="M6.8 6.2Q10 5.3 13.2 7.5" fill="none" stroke="#ffffff" strokeWidth="0.6" />
        </>
      ) : (
        <>
          <rect width="20" height="14" fill="#ffffff" />
          {STRIPES.map((y) => (
            <rect key={y} y={y} width="20" height={14 / 13} fill="var(--flag-us-red)" />
          ))}
          <rect width="9" height={(14 * 7) / 13} fill="var(--flag-us-navy)" />
          {STARS.map(([x, y]) => (
            <circle key={`${x}-${y}`} cx={x} cy={y} r="0.45" fill="#ffffff" />
          ))}
        </>
      )}
    </svg>
  );
}
