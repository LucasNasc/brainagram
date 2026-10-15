// Renderiza uma Scene (vinda do servidor) em SVG.
//
// Regra do módulo: nada aqui decide posição. O servidor já resolveu toda a
// geometria; este arquivo só traduz números em elementos SVG e devolve um
// índice de elementos para o motor de animação mexer depois.

import { t } from "./i18n";

const NS = "http://www.w3.org/2000/svg";

const ARROW_CLASS = {
  sync: "is-sync",
  return: "is-return",
  async: "is-async",
  fail: "is-fail",
};

function el(name, attrs = {}, parent = null) {
  const node = document.createElementNS(NS, name);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === null || v === undefined) continue;
    node.setAttribute(k, String(v));
  }
  if (parent) parent.appendChild(node);
  return node;
}

function text(value, attrs, parent) {
  const node = el("text", attrs, parent);
  node.textContent = value;
  return node;
}

function defs(svg) {
  const d = el("defs", {}, svg);

  // "active" é a ponta da seta que está tocando agora (cor do impulso); a
  // timeline troca o marker quando a seta muda de estado.
  for (const [kind, color] of [
    ["sync", "var(--edge-sync)"],
    ["return", "var(--edge-return)"],
    ["async", "var(--edge-async)"],
    ["fail", "var(--edge-fail)"],
    ["active", "var(--edge-active)"],
  ]) {
    const marker = el(
      "marker",
      {
        id: `bg-arrow-${kind}`,
        viewBox: "0 0 10 10",
        refX: 9,
        refY: 5,
        markerWidth: 7,
        markerHeight: 7,
        orient: "auto-start-reverse",
        markerUnits: "strokeWidth",
      },
      d,
    );

    if (kind === "return" || kind === "async") {
      // cabeça aberta (linha fina) — convenção UML para retorno/assíncrono
      el("path", { d: "M 0 0 L 10 5 L 0 10", fill: "none", stroke: color, "stroke-width": 1.6 }, marker);
    } else if (kind === "fail") {
      // falha termina em ⊗, não em ponta: a mensagem não chegou
      el("circle", { cx: 5, cy: 5, r: 4.2, fill: "var(--bg-canvas)", stroke: color, "stroke-width": 1.2 }, marker);
      el("path", { d: "M 3.3 3.3 L 6.7 6.7 M 6.7 3.3 L 3.3 6.7", stroke: color, "stroke-width": 1.2 }, marker);
    } else {
      el("path", { d: "M 0 0 L 10 5 L 0 10 z", fill: color }, marker);
    }
  }

  const glow = el("filter", { id: "bg-glow", x: "-80%", y: "-80%", width: "260%", height: "260%" }, d);
  el("feGaussianBlur", { stdDeviation: 3.2, result: "blur" }, glow);
  const merge = el("feMerge", {}, glow);
  el("feMergeNode", { in: "blur" }, merge);
  el("feMergeNode", { in: "SourceGraphic" }, merge);

  return d;
}

// ── glifos por tipo de nó ───────────────────────────────────────────────────

function glyph(kind, x, y, parent) {
  const g = el("g", { class: "bg-glyph", transform: `translate(${x} ${y})` }, parent);

  switch (kind) {
    case "actor":
      el("circle", { cx: 0, cy: -5, r: 3.6 }, g);
      el("path", { d: "M 0 -1 L 0 6 M -4.5 2 L 4.5 2 M 0 6 L -3.5 11 M 0 6 L 3.5 11" }, g);
      break;
    case "database":
      el("ellipse", { cx: 0, cy: -4, rx: 6, ry: 2.4 }, g);
      el("path", { d: "M -6 -4 L -6 6 A 6 2.4 0 0 0 6 6 L 6 -4" }, g);
      break;
    case "queue":
      el("path", { d: "M -6 -5 L -6 6 M -2 -5 L -2 6 M 2 -5 L 2 6 M 6 -5 L 6 6" }, g);
      break;
    case "external":
      el("path", { d: "M -6 -5 L 6 -5 L 6 6 L -6 6 Z", "stroke-dasharray": "3 2" }, g);
      el("path", { d: "M -2 0 L 2 0" }, g);
      break;
    case "service":
      el("path", { d: "M -6 -5 L 6 -5 L 6 6 L -6 6 Z" }, g);
      el("path", { d: "M -6 -1.5 L 6 -1.5" }, g);
      break;
    default:
      el("rect", { x: -6, y: -5, width: 12, height: 11, rx: 2 }, g);
      el("path", { d: "M -3 -1 L 3 -1 M -3 2 L 1 2" }, g);
  }

  return g;
}

// ── desenho ────────────────────────────────────────────────────────────────

export function render(container, scene) {
  container.replaceChildren();

  const svg = el(
    "svg",
    {
      class: "bg-canvas",
      viewBox: `0 0 ${scene.width} ${scene.height}`,
      preserveAspectRatio: "xMidYMin meet",
      role: "img",
      "aria-label": scene.title || t("Diagrama"),
    },
    container,
  );

  defs(svg);

  const layers = {};
  for (const name of ["groups", "bands", "lifelines", "activations", "nodes", "edges", "notes", "packets", "payloads"]) {
    layers[name] = el("g", { class: `bg-layer bg-layer-${name}` }, svg);
  }

  const index = { svg, edges: new Map(), nodes: new Map(), steps: new Map(), packets: new Map(), scene };

  drawGroups(layers.groups, scene);
  if (scene.kind === "sequence") {
    drawBands(layers.bands, scene, index);
    drawLifelines(layers.lifelines, scene);
    drawActivations(layers.activations, scene);
  } else {
    scene.steps.forEach((s) => index.steps.set(s.index, { band: null, label: null }));
  }
  drawNodes(layers.nodes, scene, index);
  drawEdges(layers.edges, layers.packets, layers.payloads, scene, index);
  drawNotes(layers.notes, scene, index);

  return index;
}

function drawGroups(layer, scene) {
  for (const group of scene.groups) {
    const g = el("g", { class: "bg-group", "data-group": group.label }, layer);
    el("rect", { x: group.x, y: group.y, width: group.w, height: group.h, rx: 14, class: "bg-group-box" }, g);
    text(group.label, { x: group.x + 12, y: group.y + 16, class: "bg-group-label" }, g);
  }
}

function drawBands(layer, scene, index) {
  for (const step of scene.steps) {
    const g = el("g", { class: "bg-band", "data-step": step.index }, layer);

    el("rect", { x: 0, y: step.y - 4, width: scene.width, height: 30, rx: 8, class: "bg-band-strip" }, g);
    el("circle", { cx: 26, cy: step.y + 11, r: 11, class: "bg-band-dot" }, g);
    text(String(step.index + 1), { x: 26, y: step.y + 15, class: "bg-band-num" }, g);
    text(step.label, { x: 46, y: step.y + 15, class: "bg-band-label" }, g);

    index.steps.set(step.index, { band: g });
  }
}

function drawLifelines(layer, scene) {
  for (const node of scene.nodes) {
    el(
      "line",
      {
        x1: node.cx,
        y1: node.lifeline_y1,
        x2: node.cx,
        y2: node.lifeline_y2,
        class: "bg-lifeline",
        "data-node": node.id,
      },
      layer,
    );
  }
}

function drawActivations(layer, scene) {
  for (const bar of scene.activations) {
    const node = scene.nodes.find((n) => n.id === bar.node);
    if (!node) continue;
    el(
      "rect",
      {
        x: node.cx - 6 + bar.depth * 6,
        y: bar.y1,
        width: 12,
        height: Math.max(bar.y2 - bar.y1, 16),
        rx: 3,
        class: "bg-activation",
        "data-node": bar.node,
      },
      layer,
    );
  }
}

function drawNodes(layer, scene, index) {
  // Sequência: fundo e filete dos cabeçalhos, visíveis só quando eles ficam
  // fixos no topo ao rolar (`.is-stuck`) — as linhas não passam por baixo.
  if (scene.kind === "sequence" && scene.nodes.length) {
    const top = Math.min(...scene.nodes.map((n) => n.y));
    const bottom = Math.max(...scene.nodes.map((n) => n.y + n.h));
    el("rect", { x: -2000, y: top - 12, width: scene.width + 4000, height: bottom - top + 20, class: "bg-header-backdrop" }, layer);
    el("line", { x1: -2000, y1: bottom + 8, x2: scene.width + 2000, y2: bottom + 8, class: "bg-header-rule" }, layer);
  }

  for (const node of scene.nodes) {
    const g = el("g", { class: `bg-node is-${node.kind}${node.pinned ? " is-pinned" : ""}`, "data-node": node.id }, layer);

    el("rect", { x: node.x, y: node.y, width: node.w, height: node.h, rx: 12, class: "bg-node-box" }, g);
    glyph(node.kind, node.x + 20, node.y + node.h / 2, g);
    text(node.label, { x: node.x + 36, y: node.y + node.h / 2 + 5, class: "bg-node-label" }, g);

    index.nodes.set(node.id, g);
  }
}

function drawEdges(layer, packetLayer, payloadLayer, scene, index) {
  for (const edge of scene.edges) {
    const g = el(
      "g",
      {
        class: `bg-edge ${ARROW_CLASS[edge.arrow] || "is-sync"}`,
        "data-edge": edge.id,
        "data-step": edge.step ?? 0,
        "data-arrow": edge.arrow,
      },
      layer,
    );

    el("path", { d: edge.path, class: "bg-edge-hit" }, g);
    // "trilho": mostra o traçado (e o tracejado de retorno/assíncrono) mesmo
    // antes da linha ser revelada pela animação.
    el("path", { d: edge.path, class: "bg-edge-track" }, g);
    const line = el(
      "path",
      { d: edge.path, class: "bg-edge-line", "marker-end": `url(#bg-arrow-${edge.arrow})` },
      g,
    );

    if (edge.label) {
      const label = el("g", { class: "bg-edge-label-wrap" }, g);
      const t = text(
        edge.label,
        { x: edge.label_x, y: edge.label_y, class: "bg-edge-label", "text-anchor": edge.label_anchor },
        label,
      );
      // fundo do rótulo desenhado depois de medir, para não cortar a linha
      const bbox = safeBBox(t);
      if (bbox) {
        const rect = el(
          "rect",
          {
            x: bbox.x - 6,
            y: bbox.y - 2,
            width: bbox.width + 12,
            height: bbox.height + 4,
            rx: 4,
            class: "bg-edge-label-bg",
          },
          label,
        );
        label.insertBefore(rect, t);
      }
    }

    let payload = null;
    if (edge.payload) {
      drawChip(g, edge);
      payload = drawFull(payloadLayer, edge);
    }

    const packet = el("g", { class: "bg-packet", "data-edge": edge.id }, packetLayer);
    el("circle", { r: 6.5, class: "bg-packet-halo", filter: "url(#bg-glow)" }, packet);
    el("circle", { r: 3.4, class: "bg-packet-core" }, packet);
    packet.style.opacity = "0";

    index.edges.set(edge.id, { group: g, line, packet, payload, meta: edge, length: 0 });
    index.packets.set(edge.id, packet);
  }
}

// Payload: um CHIP minimizado sob a seta (dentro do grupo da seta — herda o
// estado da timeline e a cor do tipo) e o BALÃO inteiro, numa camada acima de
// tudo, que abre por cima do que vem abaixo. Quem abre e fecha é a timeline
// (`is-open`, enquanto a mensagem é a da vez) e o clique (`is-pinned`).
const PAYLOAD_LINE_H = 15;
const PAYLOAD_PAD_X = 10;
const PAYLOAD_PAD_Y = 8;

function drawChip(parent, edge) {
  const p = edge.payload;
  const c = p.chip;
  const g = el("g", { class: "bg-payload-chip", "data-payload": edge.id }, parent);
  el("title", {}, g).textContent = p.text;
  el("path", { d: balloonPath({ ...c, tip_x: p.tip_x, tip_y: p.tip_y }, 10), class: "bg-payload-chip-box" }, g);
  const label = el("text", { x: c.x + 10, y: c.y + 14, class: "bg-payload-chip-text" }, g);
  el("tspan", {}, label).textContent = c.label;
  if (c.count > 1) el("tspan", { class: "bg-payload-chip-more" }, label).textContent = ` · ${t("{n} linhas", { n: c.count })}`;
  el("text", { x: c.x + c.w - 16, y: c.y + 14, class: "bg-payload-chevron" }, g).textContent = "▾";
}

function drawFull(layer, edge) {
  const p = edge.payload;
  const g = el("g", { class: `bg-payload-full ${ARROW_CLASS[edge.arrow] || "is-sync"}`, "data-payload": edge.id }, layer);
  el("title", {}, g).textContent = p.text;
  el("path", { d: balloonPath(p, 6), class: "bg-payload-box" }, g);
  const body = el("text", { x: p.x + PAYLOAD_PAD_X, y: p.y + PAYLOAD_PAD_Y + 10.5, class: "bg-payload-text" }, g);
  p.lines.forEach((line, i) => {
    const span = el("tspan", { x: p.x + PAYLOAD_PAD_X, dy: i === 0 ? 0 : PAYLOAD_LINE_H }, body);
    span.textContent = line || "\u00a0";
  });
  // "×" no canto: só aparece quando o balão foi fixado pelo clique
  el("text", { x: p.x + p.w - 14, y: p.y + 15, class: "bg-payload-close" }, g).textContent = "×";
  return g;
}

export function balloonPath({ x, y, w, h, tip_x, tip_y }, r = 6) {
  const base = Math.min(Math.max(tip_x, x + 14), x + w - 14);
  return [
    `M ${x + r} ${y}`,
    `L ${base - 6} ${y}`,
    `L ${tip_x} ${tip_y}`,
    `L ${base + 6} ${y}`,
    `L ${x + w - r} ${y}`,
    `Q ${x + w} ${y} ${x + w} ${y + r}`,
    `L ${x + w} ${y + h - r}`,
    `Q ${x + w} ${y + h} ${x + w - r} ${y + h}`,
    `L ${x + r} ${y + h}`,
    `Q ${x} ${y + h} ${x} ${y + h - r}`,
    `L ${x} ${y + r}`,
    `Q ${x} ${y} ${x + r} ${y}`,
    "Z",
  ].join(" ");
}

function drawNotes(layer, scene, index) {
  for (const note of scene.notes) {
    const g = el("g", { class: "bg-note", "data-note": note.id, "data-step": note.step ?? 0 }, layer);
    el("rect", { x: note.x, y: note.y, width: note.w, height: note.h, rx: 8, class: "bg-note-box" }, g);
    text(note.text, { x: note.x + 14, y: note.y + note.h / 2 + 5, class: "bg-note-text" }, g);
    index.edges.set(note.id, { group: g, line: null, packet: null, meta: { ...note, note: true }, length: 0 });
  }
}

function safeBBox(node) {
  try {
    return node.getBBox();
  } catch (_e) {
    return null;
  }
}

// Comprimentos só podem ser medidos depois que o SVG está no documento.
export function measure(index) {
  for (const entry of index.edges.values()) {
    if (!entry.line) continue;
    try {
      entry.length = entry.line.getTotalLength() || 0;
    } catch (_e) {
      entry.length = 0;
    }
    entry.line.style.strokeDasharray = `${entry.length}`;
    entry.line.style.strokeDashoffset = `${entry.length}`;
  }
  return index;
}
