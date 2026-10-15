import { lazy, Suspense, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { checkoutFlow, flowLayout, FlowClock, FLOW_KINDS, STEP_SIZES, TOTAL } from "../../lib/checkout";
import { checkoutSource } from "../../lib/copy";
import { formatSeconds, useI18n } from "../../lib/i18n";
import { useReducedMotion } from "../../lib/motion";
import { Icon } from "../atoms/Icon";
import { IconButton } from "../atoms/IconButton";
import { CodeBlock } from "../molecules/CodeBlock";
import { Scrubber } from "../molecules/Scrubber";
import { StageBoundary } from "./StageBoundary";

const CheckoutDiagram = lazy(() => import("../../three/CheckoutDiagram").then((m) => ({ default: m.CheckoutDiagram })));

/**
 * O produto em miniatura: o texto .brain de um lado e o diagrama tocando do
 * outro. A linha destacada no código é a mensagem que está tocando.
 */
export function MiniPlayer() {
  const { copy, lang } = useI18n();
  const reduced = useReducedMotion();
  const clock = useMemo(() => new FlowClock(), []);
  const flow = useMemo(() => checkoutFlow(copy.how.lastReply), [copy.how.lastReply]);
  const source = useMemo(() => checkoutSource(copy), [copy]);
  const stage = useRef<HTMLDivElement>(null);
  const root = useRef<HTMLDivElement>(null);
  const [box, setBox] = useState({ width: 640, height: 420 });

  // Re-renderiza no máximo dez vezes por segundo, e sempre que o estado muda.
  useSyncExternalStore(
    clock.subscribe,
    () => `${clock.index}|${clock.playing}|${Math.round(clock.t * 10)}`,
    () => "",
  );

  useEffect(() => {
    const el = stage.current!;
    const observer = new ResizeObserver(([entry]) => {
      const { width, height } = entry.contentRect;
      setBox({ width, height });
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  // Toca sozinho ao entrar na tela, uma vez; pausa ao sair.
  useEffect(() => {
    let started = false;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && !started && !reduced) {
          started = true;
          clock.play();
        } else if (!entry.isIntersecting) {
          clock.pause();
        }
      },
      { threshold: 0.55 },
    );
    observer.observe(root.current!);
    return () => observer.disconnect();
  }, [clock, reduced]);

  const { xs, ys } = flowLayout(box.width, box.height);
  const index = clock.index;
  const step = index < 0 ? 0 : flow[index].step;
  const time = `${formatSeconds(lang, clock.t)} ${copy.player.seconds} / ${formatSeconds(lang, TOTAL)} ${copy.player.seconds}`;

  return (
    <div className="lp-player" ref={root}>
      <CodeBlock
        lines={source}
        language="brain"
        label={copy.how.source}
        activeLine={index < 0 ? undefined : flow[index].line}
        copyable={false}
      />
      <div className="lp-player__main">
        <div className="lp-player__stage" ref={stage} role="img" aria-label={copy.how.diagramLabel}>
          <StageBoundary>
            <Suspense fallback={null}>
              <CheckoutDiagram clock={clock} flow={flow} />
            </Suspense>
          </StageBoundary>
          {copy.how.participants.map((name, i) => (
            <span key={name} className="lp-player__who" data-kind={FLOW_KINDS[i]} style={{ left: xs[i] }}>
              <Icon name={FLOW_KINDS[i]} size={14} />
              {name}
            </span>
          ))}
          {flow.map((m, i) => (
            <span
              key={i}
              className="lp-player__label"
              data-state={i === index && clock.progressOf(i) < 1 ? "active" : i <= index ? "done" : "pending"}
              style={{ left: (xs[m.from] + xs[m.to]) / 2, top: ys[i] }}
            >
              {m.label}
            </span>
          ))}
        </div>
        <div className="lp-player__bar">
          {reduced ? (
            <>
              <IconButton icon="prev" label={copy.player.prev} onClick={() => clock.stepBy(-1)} />
              <IconButton icon="next" tone="brand" label={copy.player.next} onClick={() => clock.stepBy(1)} />
            </>
          ) : (
            <IconButton
              icon={clock.playing ? "pause" : "play"}
              tone="brand"
              label={clock.playing ? copy.player.pause : copy.player.play}
              onClick={() => clock.toggle()}
            />
          )}
          <Scrubber
            sizes={STEP_SIZES}
            value={clock.t}
            max={TOTAL}
            label={copy.player.seek}
            valueText={time}
            onSeek={(t) => {
              clock.pause();
              clock.seek(t);
            }}
          />
          <span className="lp-player__time">{time}</span>
          <span className="lp-player__caption" aria-live="polite">
            <b>
              {step + 1}/{STEP_SIZES.length}
            </b>{" "}
            {copy.how.steps[step]}
          </span>
        </div>
      </div>
    </div>
  );
}
