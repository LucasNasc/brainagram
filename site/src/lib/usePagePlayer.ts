import { useCallback, useEffect, useRef, useState } from "react";

/** Pixels por segundo quando a página "toca" sozinha. */
const SPEED = 190;

/**
 * Tocar a página: ela rola sozinha, e com isso o diagrama avança. Qualquer
 * gesto de rolagem do visitante pausa.
 */
export function usePagePlayer() {
  const [playing, setPlaying] = useState(false);
  const frame = useRef(0);

  const stop = useCallback(() => {
    cancelAnimationFrame(frame.current);
    setPlaying(false);
  }, []);

  const play = useCallback(() => {
    const max = () => document.documentElement.scrollHeight - window.innerHeight;
    if (window.scrollY >= max() - 2) window.scrollTo(0, 0);
    let y = window.scrollY;
    let last = performance.now();
    setPlaying(true);
    const tick = (now: number) => {
      y += (SPEED * Math.min(now - last, 64)) / 1000;
      last = now;
      window.scrollTo(0, y);
      if (y >= max()) {
        setPlaying(false);
        return;
      }
      frame.current = requestAnimationFrame(tick);
    };
    frame.current = requestAnimationFrame(tick);
  }, []);

  useEffect(() => {
    if (!playing) return;
    const keys = new Set([" ", "ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End", "Escape"]);
    const onKey = (e: KeyboardEvent) => {
      if (keys.has(e.key)) stop();
    };
    window.addEventListener("wheel", stop, { passive: true });
    window.addEventListener("touchstart", stop, { passive: true });
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("wheel", stop);
      window.removeEventListener("touchstart", stop);
      window.removeEventListener("keydown", onKey);
    };
  }, [playing, stop]);

  useEffect(() => () => cancelAnimationFrame(frame.current), []);

  return { playing, toggle: playing ? stop : play };
}
