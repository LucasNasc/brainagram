import type { CSSProperties } from "react";

interface Props {
  /** Tamanho relativo de cada passo. */
  sizes: number[];
  value: number;
  max: number;
  label: string;
  valueText: string;
  onSeek: (value: number) => void;
}

/** Barra de tempo segmentada por passo, operável por teclado (é um range). */
export function Scrubber({ sizes, value, max, label, valueText, onSeek }: Props) {
  const total = sizes.reduce((a, b) => a + b, 0);
  let before = 0;
  const fraction = max > 0 ? value / max : 0;
  return (
    <div className="lp-scrub" style={{ "--at": fraction } as CSSProperties}>
      <div className="lp-scrub__track" aria-hidden="true">
        {sizes.map((size, i) => {
          const start = before / total;
          before += size;
          const fill = Math.max(0, Math.min(1, (fraction - start) / (size / total)));
          return (
            <span key={i} className="lp-scrub__seg" style={{ flexGrow: size }}>
              <i style={{ transform: `scaleX(${fill})` }} />
            </span>
          );
        })}
        <span className="lp-scrub__thumb" />
      </div>
      <input
        className="lp-scrub__input"
        type="range"
        min={0}
        max={max}
        step={0.05}
        value={value}
        aria-label={label}
        aria-valuetext={valueText}
        onChange={(e) => onSeek(Number(e.target.value))}
      />
    </div>
  );
}
