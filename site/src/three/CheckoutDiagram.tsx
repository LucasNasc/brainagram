import { Canvas, useFrame, useThree } from "@react-three/fiber";
import { useEffect, useMemo } from "react";
import * as THREE from "three";
import { flowLayout, type FlowClock, type FlowMsg } from "../lib/checkout";
import { COLOR } from "../lib/tokens";
import { Arrow, DotField, Impulse, Seg, screenSpace } from "./primitives";

interface Props {
  clock: FlowClock;
  flow: FlowMsg[];
}

function Scene({ clock, flow }: Props) {
  const size = useThree((s) => s.size);
  const invalidate = useThree((s) => s.invalidate);
  const dpr = useThree((s) => s.viewport.dpr);

  const gfx = useMemo(() => {
    const root = new THREE.Group();
    const dots = new DotField(16);
    const band = new Seg(0);
    const lifelines = Array.from({ length: 5 }, () => new Seg(1));
    const arrows = flow.map(() => new Arrow());
    const impulse = new Impulse();
    root.add(dots.points, band.mesh, ...lifelines.map((l) => l.mesh), ...arrows.map((a) => a.group), impulse.group);
    return { root, dots, band, lifelines, arrows, impulse };
  }, [flow]);

  useEffect(() => {
    screenSpace(size.width, size.height, gfx.root);
    gfx.dots.resize(size.width, size.height, dpr);
    invalidate();
  }, [size.width, size.height, dpr, gfx, invalidate]);

  useEffect(() => clock.subscribe(() => invalidate()), [clock, invalidate]);

  useFrame((_, delta) => {
    clock.advance(Math.min(delta, 0.1));
    const { xs, ys, row, headerBottom } = flowLayout(size.width, size.height);
    const scale = size.width < 520 ? 0.8 : 1;

    gfx.lifelines.forEach((line, i) => {
      line.set(xs[i], headerBottom, xs[i], size.height, 1.5).style(COLOR.lifeline, [4, 6]);
    });

    const current = clock.index;
    const step = current < 0 ? -1 : flow[current].step;
    const rows = flow.map((m, i) => (m.step === step ? i : -1)).filter((i) => i >= 0);
    gfx.band.visible = rows.length > 0;
    if (rows.length > 0) {
      const top = ys[rows[0]] - row / 2;
      const bottom = ys[rows[rows.length - 1]] + row / 2;
      gfx.band.set(0, (top + bottom) / 2, size.width, (top + bottom) / 2, bottom - top).style(COLOR.brandSoft, [0, 0], 1, 0, 0.55);
    }

    let at: [number, number] | null = null;
    flow.forEach((m, i) => {
      const p = clock.progressOf(i);
      const x = gfx.arrows[i].update(m.kind, xs[m.from], xs[m.to], ys[i], p, scale);
      if (p > 0 && p < 1) at = [x, ys[i]];
    });
    gfx.impulse.visible = at !== null;
    if (at) gfx.impulse.set(at[0], at[1], 5 * scale + 0.5);
    gfx.dots.update(0, at, null);

    if (clock.playing) invalidate();
  });

  return <primitive object={gfx.root} />;
}

/** O diagrama de checkout em WebGL. Os rótulos ficam no DOM, por cima. */
export function CheckoutDiagram(props: Props) {
  return (
    <div className="lp-player__canvas" aria-hidden="true">
      <Canvas
        orthographic
        frameloop="demand"
        dpr={[1, 2]}
        gl={{ alpha: true, antialias: true, powerPreference: "low-power" }}
        camera={{ position: [0, 0, 10], near: 0.1, far: 100 }}
      >
        <Scene {...props} />
      </Canvas>
    </div>
  );
}
