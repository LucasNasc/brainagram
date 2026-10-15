import * as THREE from "three";
import { COLOR, DASH, type EdgeKind } from "../lib/tokens";

/**
 * Peças do diagrama em WebGL, em coordenadas de tela (px, y para baixo).
 * Tudo é um quad com shader: traços nítidos em qualquer densidade de pixels,
 * sem depender de `linewidth`.
 */
const QUAD = new THREE.PlaneGeometry(1, 1);
const DISC = new THREE.CircleGeometry(1, 40);
const TRI = (() => {
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute([0, 0, 0, -1, 0.5, 0, -1, -0.5, 0], 3));
  return g;
})();

const VERT = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

const base = {
  transparent: true,
  depthTest: false,
  depthWrite: false,
  side: THREE.DoubleSide,
} as const;

/** Um segmento de reta: contínuo ou tracejado, com revelação parcial. */
export class Seg {
  readonly mesh: THREE.Mesh;
  private u: Record<string, THREE.IUniform>;

  constructor(order = 1) {
    this.u = {
      uColor: { value: new THREE.Color(COLOR.pending) },
      uOpacity: { value: 1 },
      uLen: { value: 1 },
      uDash: { value: 0 },
      uGap: { value: 0 },
      uReveal: { value: 1 },
      uOffset: { value: 0 },
    };
    const mat = new THREE.ShaderMaterial({
      ...base,
      uniforms: this.u,
      vertexShader: VERT,
      fragmentShader: /* glsl */ `
        uniform vec3 uColor;
        uniform float uOpacity, uLen, uDash, uGap, uReveal, uOffset;
        varying vec2 vUv;
        void main() {
          if (vUv.x > uReveal) discard;
          if (uDash > 0.0 && mod(vUv.x * uLen + uOffset, uDash + uGap) > uDash) discard;
          gl_FragColor = vec4(uColor, uOpacity);
          #include <colorspace_fragment>
        }
      `,
    });
    this.mesh = new THREE.Mesh(QUAD, mat);
    this.mesh.renderOrder = order;
  }

  set(ax: number, ay: number, bx: number, by: number, thickness: number) {
    const dx = bx - ax;
    const dy = by - ay;
    const len = Math.max(0.001, Math.hypot(dx, dy));
    this.mesh.position.set((ax + bx) / 2, (ay + by) / 2, 0);
    this.mesh.rotation.z = Math.atan2(dy, dx);
    this.mesh.scale.set(len, thickness, 1);
    this.u.uLen.value = len;
    return this;
  }

  style(color: string, dash: readonly [number, number] = [0, 0], reveal = 1, offset = 0, opacity = 1) {
    (this.u.uColor.value as THREE.Color).set(color);
    this.u.uDash.value = dash[0];
    this.u.uGap.value = dash[1];
    this.u.uReveal.value = reveal;
    this.u.uOffset.value = offset;
    this.u.uOpacity.value = opacity;
    return this;
  }

  set visible(v: boolean) {
    this.mesh.visible = v;
  }
}

/** Um quad com brilho radial (o halo do impulso) ou um anel (o pulso). */
export class Halo {
  readonly mesh: THREE.Mesh;
  private u: Record<string, THREE.IUniform>;

  constructor(mode: "glow" | "ring", order = 5) {
    this.u = {
      uColor: { value: new THREE.Color(COLOR.brand) },
      uOpacity: { value: 1 },
      uRadius: { value: 0.8 },
      uWidth: { value: 0.08 },
    };
    const mat = new THREE.ShaderMaterial({
      ...base,
      blending: mode === "glow" ? THREE.AdditiveBlending : THREE.NormalBlending,
      uniforms: this.u,
      vertexShader: VERT,
      fragmentShader:
        mode === "glow"
          ? /* glsl */ `
            uniform vec3 uColor; uniform float uOpacity;
            varying vec2 vUv;
            void main() {
              float a = smoothstep(1.0, 0.0, length(vUv - 0.5) * 2.0);
              gl_FragColor = vec4(uColor, a * a * uOpacity);
              #include <colorspace_fragment>
            }`
          : /* glsl */ `
            uniform vec3 uColor; uniform float uOpacity, uRadius, uWidth;
            varying vec2 vUv;
            void main() {
              float d = length(vUv - 0.5) * 2.0;
              float a = smoothstep(uWidth, uWidth * 0.35, abs(d - uRadius));
              gl_FragColor = vec4(uColor, a * uOpacity);
              #include <colorspace_fragment>
            }`,
    });
    this.mesh = new THREE.Mesh(QUAD, mat);
    this.mesh.renderOrder = order;
  }

  set(x: number, y: number, size: number, opacity = 1, color?: string) {
    this.mesh.position.set(x, y, 0);
    this.mesh.scale.set(size, size, 1);
    this.u.uOpacity.value = opacity;
    if (color) (this.u.uColor.value as THREE.Color).set(color);
    return this;
  }

  ring(radius: number, width: number) {
    this.u.uRadius.value = radius;
    this.u.uWidth.value = width;
    return this;
  }

  set visible(v: boolean) {
    this.mesh.visible = v;
  }
}

/** O impulso: um ponto violeta com halo. */
export class Impulse {
  readonly group = new THREE.Group();
  private dot: THREE.Mesh;
  private glow = new Halo("glow", 6);

  constructor() {
    this.dot = new THREE.Mesh(DISC, new THREE.MeshBasicMaterial({ ...base, color: COLOR.brand }));
    this.dot.renderOrder = 7;
    this.group.add(this.glow.mesh, this.dot);
  }

  set(x: number, y: number, radius = 5.5) {
    this.dot.position.set(x, y, 0);
    this.dot.scale.set(radius, radius, 1);
    this.glow.set(x, y, radius * 11, 0.55);
  }

  set visible(v: boolean) {
    this.group.visible = v;
  }
}

/**
 * Uma seta do diagrama, com a forma de cada tipo: chamada (contínua, ponta
 * cheia), retorno (tracejada, ponta aberta), assíncrona (pontilhada, ponta
 * aberta) e falha (tracejada, terminando em um círculo cortado).
 */
export class Arrow {
  readonly group = new THREE.Group();
  private rest = new Seg(2);
  private live = new Seg(3);
  private fill: THREE.Mesh;
  private fillMat: THREE.MeshBasicMaterial;
  private wingA = new Seg(4);
  private wingB = new Seg(4);
  private ring = new Halo("ring", 4);
  private crossA = new Seg(4);
  private crossB = new Seg(4);

  constructor() {
    this.fillMat = new THREE.MeshBasicMaterial({ ...base, color: COLOR.pending });
    this.fill = new THREE.Mesh(TRI, this.fillMat);
    this.fill.renderOrder = 4;
    this.ring.ring(0.82, 0.16);
    this.group.add(
      this.rest.mesh,
      this.live.mesh,
      this.fill,
      this.wingA.mesh,
      this.wingB.mesh,
      this.ring.mesh,
      this.crossA.mesh,
      this.crossB.mesh,
    );
  }

  /**
   * @param progress 0 = ainda não tocou, 1 = já tocou; entre os dois, tocando.
   * @returns o x do impulso enquanto toca.
   */
  update(kind: EdgeKind, ax: number, bx: number, y: number, progress: number, scale = 1): number {
    const dir = bx >= ax ? 1 : -1;
    const pending = progress <= 0;
    const done = progress >= 1;
    const head = 10 * scale;
    const inset = kind === "fail" ? head * 0.95 : kind === "sync" ? head * 0.9 : 1;
    const end = bx - dir * inset;
    const dash = DASH[kind];
    const ink = pending || !done ? COLOR.pending : COLOR[kind];

    this.rest.set(ax, y, end, y, pending ? 1 : 1.5).style(ink, dash);
    this.live.visible = !pending && !done;
    this.live.set(ax, y, end, y, 2.5).style(COLOR.brand, dash, progress);

    const tip = done ? COLOR[kind] : progress > 0.96 ? COLOR.brand : COLOR.pending;
    const filled = kind === "sync";
    const open = kind === "return" || kind === "async";
    const failed = kind === "fail";

    this.fill.visible = filled;
    this.wingA.visible = this.wingB.visible = open;
    this.ring.visible = failed;
    this.crossA.visible = this.crossB.visible = failed;

    if (filled) {
      this.fill.position.set(bx, y, 0);
      this.fill.scale.set(head * dir, head, 1);
      this.fillMat.color.set(tip);
    } else if (open) {
      const back = bx - dir * head;
      this.wingA.set(bx, y, back, y - head * 0.5, 1.5).style(tip);
      this.wingB.set(bx, y, back, y + head * 0.5, 1.5).style(tip);
    } else {
      const cx = bx - dir * 1;
      const r = head * 0.72;
      this.ring.set(cx, y, r * 2.5, 1, tip);
      const k = r * 0.5;
      this.crossA.set(cx - k, y - k, cx + k, y + k, 1.5).style(tip);
      this.crossB.set(cx - k, y + k, cx + k, y - k, 1.5).style(tip);
    }
    return ax + (end - ax) * progress;
  }

  set visible(v: boolean) {
    this.group.visible = v;
  }
}

/** A malha de pontos da folha, que acende perto do impulso e do ponteiro. */
export class DotField {
  readonly points: THREE.Points;
  private u: Record<string, THREE.IUniform>;
  readonly spacing: number;

  constructor(spacing = 24) {
    this.spacing = spacing;
    this.u = {
      uScroll: { value: 0 },
      uSpacing: { value: spacing },
      uImpulse: { value: new THREE.Vector2(-9999, -9999) },
      uPointer: { value: new THREE.Vector2(-9999, -9999) },
      uDpr: { value: 1 },
      uWave: { value: new THREE.Vector4(0, 0, 0, 0) },
      uBase: { value: new THREE.Color(COLOR.dot) },
      uLit: { value: new THREE.Color(COLOR.dotLit) },
    };
    const mat = new THREE.ShaderMaterial({
      ...base,
      uniforms: this.u,
      vertexShader: /* glsl */ `
        uniform float uScroll, uSpacing, uDpr;
        uniform vec2 uImpulse, uPointer;
        uniform vec4 uWave;
        varying float vLit;
        void main() {
          vec3 p = position;
          p.y -= mod(uScroll, uSpacing);
          float byImpulse = smoothstep(200.0, 0.0, distance(p.xy, uImpulse));
          float byPointer = smoothstep(130.0, 0.0, distance(p.xy, uPointer)) * 0.5;
          float byWave = smoothstep(34.0, 0.0, abs(distance(p.xy, uWave.xy) - uWave.z)) * uWave.w;
          vLit = max(max(byImpulse * byImpulse, byPointer * byPointer), byWave);
          gl_PointSize = (2.2 + vLit * 3.4) * uDpr;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
        }
      `,
      fragmentShader: /* glsl */ `
        uniform vec3 uBase, uLit;
        varying float vLit;
        void main() {
          float edge = smoothstep(0.5, 0.3, length(gl_PointCoord - 0.5));
          if (edge <= 0.0) discard;
          gl_FragColor = vec4(mix(uBase, uLit, vLit), edge);
          #include <colorspace_fragment>
        }
      `,
    });
    this.points = new THREE.Points(new THREE.BufferGeometry(), mat);
    this.points.renderOrder = 0;
    this.points.frustumCulled = false;
  }

  resize(width: number, height: number, dpr: number) {
    const s = this.spacing;
    const cols = Math.ceil(width / s) + 1;
    const rows = Math.ceil(height / s) + 2;
    const pos = new Float32Array(cols * rows * 3);
    let i = 0;
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        pos[i++] = c * s + s / 2;
        pos[i++] = r * s;
        pos[i++] = 0;
      }
    }
    this.points.geometry.dispose();
    this.points.geometry = new THREE.BufferGeometry();
    this.points.geometry.setAttribute("position", new THREE.BufferAttribute(pos, 3));
    this.u.uDpr.value = dpr;
  }

  /** A onda do pulso de chegada, atravessando a malha. */
  wave(x: number, y: number, radius: number, strength: number) {
    (this.u.uWave.value as THREE.Vector4).set(x, y, radius, strength);
  }

  update(scroll: number, impulse: [number, number] | null, pointer: [number, number] | null) {
    this.u.uScroll.value = scroll;
    (this.u.uImpulse.value as THREE.Vector2).set(...(impulse ?? [-9999, -9999]));
    (this.u.uPointer.value as THREE.Vector2).set(...(pointer ?? [-9999, -9999]));
  }
}

/** Grupo-raiz que converte coordenadas de tela (origem no topo esquerdo). */
export function screenSpace(width: number, height: number, root: THREE.Group) {
  root.position.set(-width / 2, height / 2, 0);
  root.scale.set(1, -1, 1);
}
