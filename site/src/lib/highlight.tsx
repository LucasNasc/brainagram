import type { ReactNode } from "react";

const KEYWORDS = new Set(["diagram", "sequence", "step", "actor", "participant", "service", "database", "queue"]);
const TOKEN = /("[^"]*")|(-->|->>|->)|([A-Za-z_]+)|([^"A-Za-z_-]+|-)/g;

/** Realce de sintaxe mínimo para uma linha de .brain. */
export function highlightBrain(line: string): ReactNode[] {
  const out: ReactNode[] = [];
  let key = 0;
  for (const match of line.matchAll(TOKEN)) {
    const [text, str, arrow, word] = match;
    if (str) out.push(<span key={key++} className="lp-syn-string">{text}</span>);
    else if (arrow) out.push(<span key={key++} className="lp-syn-arrow">{text}</span>);
    else if (word && KEYWORDS.has(word)) out.push(<span key={key++} className="lp-syn-keyword">{text}</span>);
    else out.push(text);
  }
  return out;
}
