import { useEffect, useRef } from "react";
import { formatSeconds, useI18n } from "../../lib/i18n";
import { useReducedMotion } from "../../lib/motion";
import { timeline } from "../../lib/timeline";
import { useCurrentStep } from "../../lib/useCurrentStep";
import { usePagePlayer } from "../../lib/usePagePlayer";
import { IconButton } from "../atoms/IconButton";

/** Duração nominal da página, em segundos: rolar tudo é assistir a tudo. */
const DURATION = 24;

/** A barra de transporte da página: play, passos e a barra de tempo. */
export function Transport() {
  const { copy, lang } = useI18n();
  const current = useCurrentStep();
  const reduced = useReducedMotion();
  const { playing, toggle } = usePagePlayer();
  const segs = useRef<(HTMLLIElement | null)[]>([]);
  const time = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    const update = () => {
      const { fractions } = timeline.stepAt(timeline.playhead());
      timeline.steps.forEach((step, i) => {
        const el = segs.current[i];
        if (!el) return;
        el.style.flexGrow = String(Math.max(1, Math.round(step.bottom - step.top)));
        el.style.setProperty("--fill", String(fractions[i] ?? 0));
      });
      const max = document.documentElement.scrollHeight - window.innerHeight;
      const at = max > 0 ? Math.min(1, window.scrollY / max) : 0;
      if (time.current) time.current.textContent = formatSeconds(lang, at * DURATION);
    };
    update();
    window.addEventListener("scroll", update, { passive: true });
    const off = timeline.subscribe(update);
    return () => {
      window.removeEventListener("scroll", update);
      off();
    };
  }, [lang]);

  const total = copy.stepNames.length;
  return (
    <div className="lp-transport" role="group" aria-label={copy.transportLabel}>
      <div className="lp-transport__keys">
        <IconButton icon="prev" label={copy.player.prev} disabled={current === 0} onClick={() => timeline.scrollToStep(current - 1)} />
        {!reduced && (
          <IconButton
            icon={playing ? "pause" : "play"}
            tone="brand"
            label={playing ? copy.player.pausePage : copy.player.playPage}
            aria-pressed={playing}
            onClick={toggle}
          />
        )}
        <IconButton icon="next" label={copy.player.next} disabled={current === total - 1} onClick={() => timeline.scrollToStep(current + 1)} />
      </div>
      <ol className="lp-transport__segs">
        {copy.stepNames.map((name, i) => (
          <li
            key={name}
            ref={(el) => {
              segs.current[i] = el;
            }}
          >
            <button
              type="button"
              className="lp-transport__seg"
              aria-current={i === current ? "step" : undefined}
              aria-label={`${copy.player.goTo}: ${name}`}
              title={name}
              onClick={() => timeline.scrollToStep(i)}
            >
              <i />
            </button>
          </li>
        ))}
      </ol>
      <p className="lp-transport__time">
        <span ref={time}>{formatSeconds(lang, 0)}</span> {copy.player.seconds} / {formatSeconds(lang, DURATION)} {copy.player.seconds}
      </p>
      <p className="lp-transport__caption" aria-live="polite">
        <b>
          {current + 1}/{total}
        </b>{" "}
        {copy.stepNames[current]}
      </p>
    </div>
  );
}
