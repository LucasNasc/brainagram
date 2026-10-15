import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { useEffect, useMemo, useRef } from "react";
import * as THREE from "three";
import { arrowEnds, isCompact, laneXs } from "../lib/lanes";
import { useReducedMotion } from "../lib/motion";
import { timeline, type Msg, type MsgState } from "../lib/timeline";
import { COLOR } from "../lib/tokens";
import { Arrow, DotField, Halo, Impulse, Seg, screenSpace } from "./primitives";

const PULSE_MS = 620;

interface Pulse {
  msg: Msg;
  start: number;
}

function Scene() {
  const size = useThree((s) => s.size);
  const invalidate = useThree((s) => s.invalidate);
  const dpr = useThree((s) => s.viewport.dpr);
  const reduced = useReducedMotion();

  const gfx = useMemo(() => {
    const root = new THREE.Group();
    const dots = new DotField();
    const lifelines = Array.from({ length: 5 }, () => new Seg(1));
    const impulse = new Impulse();
    const pulses = Array.from({ length: 3 }, () => new Halo("ring", 5));
    const arrows = new THREE.Group();
    root.add(dots.points, ...lifelines.map((l) => l.mesh), arrows, ...pulses.map((p) => p.mesh), impulse.group);
    return { root, dots, lifelines, impulse, pulses, arrows, pool: [] as Arrow[] };
  }, []);

  const pointer = useRef<[number, number] | null>(null);
  const live = useRef<Pulse[]>([]);

  useEffect(() => {
    screenSpace(size.width, size.height, gfx.root);
    gfx.dots.resize(size.width, size.height, dpr);
    invalidate();
  }, [size.width, size.height, dpr, gfx, invalidate]);

  useEffect(() => {
    const wake = () => invalidate();
    const move = (e: PointerEvent) => {
      pointer.current = e.pointerType === "mouse" ? [e.clientX, e.clientY] : null;
      invalidate();
    };
    const leave = () => {
      pointer.current = null;
      invalidate();
    };
    window.addEventListener("scroll", wake, { passive: true });
    window.addEventListener("pointermove", move, { passive: true });
    document.addEventListener("pointerleave", leave);
    const off = timeline.subscribe(wake);
    return () => {
      window.removeEventListener("scroll", wake);
      window.removeEventListener("pointermove", move);
      document.removeEventListener("pointerleave", leave);
      off();
    };
  }, [invalidate]);

  useFrame(() => {
    const { width: w, height: h } = size;
    const now = performance.now();
    const sy = window.scrollY;
    const xs = laneXs(w);
    const compact = isCompact(w);
    const top = compact ? 100 : 88;
    const bottom = h - 56;
    const playhead = timeline.playhead(now);

    gfx.lifelines.forEach((line, i) => {
      line.visible = !compact || i < 2;
      line.set(xs[i], top, xs[i], bottom, 1.5).style(COLOR.lifeline, [4, 6], 1, sy + top);
    });

    while (gfx.pool.length < timeline.msgs.length) {
      const arrow = new Arrow();
      gfx.pool.push(arrow);
      gfx.arrows.add(arrow.group);
    }

    let impulseAt: [number, number] | null = null;
    gfx.pool.forEach((arrow, i) => {
      const m = timeline.msgs[i];
      if (!m) {
        arrow.visible = false;
        return;
      }
      const y = m.y - sy;
      const p = timeline.progressOf(m, playhead);
      const state: MsgState = p <= 0 ? "pending" : p >= 1 ? "done" : "active";
      if (state !== m.state) {
        if (state === "done" && m.state === "active" && !reduced) {
          live.current = [...live.current.slice(-2), { msg: m, start: now }];
        }
        m.state = state;
        m.el.dataset.state = state;
      }
      const onScreen = y > top - 20 && y < bottom + 20;
      arrow.visible = onScreen;
      if (!onScreen) return;
      const [ax, bx] = arrowEnds(w, m.from, m.to);
      const x = arrow.update(m.kind, ax, bx, y, p, compact ? 0.9 : 1);
      if (state === "active") impulseAt = [x, y];
    });

    gfx.impulse.visible = impulseAt !== null;
    if (impulseAt) gfx.impulse.set(impulseAt[0], impulseAt[1]);

    live.current = live.current.filter((p) => now - p.start < PULSE_MS);
    gfx.pulses.forEach((ring, i) => {
      const pulse = live.current[i];
      ring.visible = Boolean(pulse);
      if (!pulse) return;
      const t = (now - pulse.start) / PULSE_MS;
      const eased = 1 - Math.pow(1 - t, 3);
      const [, end] = arrowEnds(w, pulse.msg.from, pulse.msg.to);
      ring.ring(0.2 + eased * 0.7, 0.07).set(end, pulse.msg.y - sy, 96, (1 - t) * 0.9, COLOR.brand);
    });

    const wave = live.current[live.current.length - 1];
    if (wave) {
      const t = (now - wave.start) / PULSE_MS;
      const [, end] = arrowEnds(w, wave.msg.from, wave.msg.to);
      gfx.dots.wave(end, wave.msg.y - sy, (1 - Math.pow(1 - t, 3)) * 240, 1 - t);
    } else {
      gfx.dots.wave(0, 0, 0, 0);
    }
    gfx.dots.update(sy, impulseAt, pointer.current);

    if (timeline.introRunning || live.current.length > 0) invalidate();
  });

  return <primitive object={gfx.root} />;
}

/** O diagrama da página: fixo atrás do conteúdo, dirigido pela rolagem. */
export function PageDiagram() {
  return (
    <div className="lp-stage" aria-hidden="true">
      <Canvas
        orthographic
        frameloop="demand"
        dpr={[1, 2]}
        gl={{ alpha: true, antialias: true, powerPreference: "low-power" }}
        camera={{ position: [0, 0, 10], near: 0.1, far: 100 }}
      >
        <Scene />
      </Canvas>
    </div>
  );
}
