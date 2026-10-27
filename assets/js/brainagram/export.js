// Exportação. Para SVG standalone é preciso "assar" as CSS custom properties
// dentro do arquivo, senão o diagrama abre sem cor fora do app.

const EXPORT_VARS = [
  "--bg-canvas",
  "--surface",
  "--surface-2",
  "--surface-3",
  "--text",
  "--text-muted",
  "--edge-label",
  "--edge-label-bg",
  "--border",
  "--border-strong",
  "--brand",
  "--brand-soft",
  "--brand-text",
  "--on-brand",
  "--impulse",
  "--impulse-glow",
  "--edge-sync",
  "--edge-return",
  "--edge-async",
  "--edge-fail",
  "--edge-pending",
  "--edge-active",
  "--node-stroke",
  "--node-actor",
  "--node-service",
  "--node-database",
  "--node-queue",
  "--node-external",
  "--node-neutral",
  "--group-bg",
  "--group-border",
  "--note-bg",
  "--note-border",
  "--note-text",
  "--font-sans",
  "--font-mono",
  "--dur-base",
  "--dur-fast",
  "--dur-pulse",
  "--dur-reveal",
  "--ease-ui",
  "--ease-pulso",
  "--ease-revelar",
];

function collectStyles() {
  const rules = [];
  for (const sheet of Array.from(document.styleSheets)) {
    let list;
    try {
      list = sheet.cssRules;
    } catch (_e) {
      continue; // folha de outra origem
    }
    for (const rule of Array.from(list || [])) {
      if (rule.cssText && rule.cssText.includes(".bg-")) rules.push(rule.cssText);
    }
  }
  return rules.join("\n");
}

function frozenVars() {
  const computed = getComputedStyle(document.documentElement);
  const decls = EXPORT_VARS.map((v) => `${v}: ${computed.getPropertyValue(v).trim()};`).join(" ");
  return `:root { ${decls} }`;
}

// As fontes da marca, embutidas no arquivo. Um SVG aberto como imagem — o
// arquivo exportado num visualizador e cada quadro do PNG/GIF, desenhados a
// partir de um <img> — não carrega fonte externa: sem isto, a exportação cai
// na fonte do sistema mesmo com a Geist na tela. Lidas uma vez e guardadas.
const EXPORT_FONTS = [
  { family: "Geist", url: "/fonts/Geist-Variable.woff2" },
  { family: "Geist Mono", url: "/fonts/GeistMono-Variable.woff2" },
];
let fontFacesPromise = null;

export function exportFontFaces() {
  fontFacesPromise ||= Promise.all(
    EXPORT_FONTS.map(async ({ family, url }) => {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`${url}: ${response.status}`);
      const dataUrl = await blobToDataUrl(await response.blob());
      return `@font-face{font-family:"${family}";src:url(${dataUrl}) format("woff2");font-weight:100 900;font-style:normal;font-display:block}`;
    }),
  )
    .then((faces) => faces.join("\n"))
    .catch(() => {
      // sem as fontes (offline, 404): exporta na fonte do sistema e tenta de novo na próxima
      fontFacesPromise = null;
      return "";
    });
  return fontFacesPromise;
}

function blobToDataUrl(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result.replace(/^data:[^;,]*/, "data:font/woff2"));
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });
}

// O CSS que vai dentro do arquivo: fontes embutidas + variáveis do tema
// "assadas" + regras `.bg-*`. Calculado uma vez por exportação — o GIF
// serializa dezenas de quadros.
export function svgStyleText(fontFaces = "") {
  // a raiz clonada perde a classe `.bg-canvas`, então a fonte vai explícita —
  // sem isto, o arquivo cai na serifada padrão do visualizador
  return `${fontFaces}
${frozenVars()}
svg{font-family:var(--font-sans)}
${collectStyles()}
.bg-edge.is-export{opacity:1}
.bg-node{opacity:1}`;
}

// `final: true` (SVG/PNG) mostra o diagrama completo; `final: false` (quadros do
// GIF) preserva o instante da animação: setas pendentes, impulso, passo atual.
export function toSvgString(svg, scene, { final = true, style = null } = {}) {
  const clone = svg.cloneNode(true);
  clone.setAttribute("xmlns", "http://www.w3.org/2000/svg");
  clone.removeAttribute("class");

  // O arquivo exportado mostra o diagrama inteiro, não o recorte onde o usuário
  // parou de arrastar.
  if (scene) {
    clone.setAttribute("viewBox", `0 0 ${scene.width} ${scene.height}`);
    clone.setAttribute("width", scene.width);
    clone.setAttribute("height", scene.height);
  }

  if (final) {
    // estado final: tudo visível
    clone.querySelectorAll(".bg-edge-line").forEach((p) => {
      p.style.strokeDasharray = "";
      p.style.strokeDashoffset = "";
    });
    clone.querySelectorAll(".bg-edge, .bg-note").forEach((g) => {
      g.classList.remove("is-pending", "is-active", "is-current-step");
      g.classList.add("is-done", "is-export");
    });
    clone.querySelectorAll(".bg-edge[data-arrow] .bg-edge-line").forEach((line) => {
      line.setAttribute("marker-end", `url(#bg-arrow-${line.parentNode.dataset.arrow})`);
    });
    clone.querySelectorAll(".bg-packet").forEach((p) => p.remove());
    // payload: no arquivo vale o que a pessoa fixou aberto; o resto fica chip
    clone.querySelectorAll(".bg-payload-full").forEach((g) => g.classList.remove("is-open", "is-live"));
    // estados de reprodução não devem vazar para o arquivo
    clone.querySelectorAll(".bg-node").forEach((g) => g.classList.remove("is-active", "is-hot"));
    clone.querySelectorAll(".bg-band").forEach((g) => g.classList.remove("is-current"));
  }

  clone.querySelectorAll(".bg-edit-layer").forEach((p) => p.remove());
  // cabeçalhos fixos ao rolar (apresentação): no arquivo, cada um no seu lugar
  clone.querySelectorAll(".bg-layer-nodes").forEach((layer) => {
    layer.removeAttribute("transform");
    layer.classList.remove("is-stuck");
    const edges = clone.querySelector(".bg-layer-edges");
    if (edges) clone.insertBefore(layer, edges);
  });
  // estados de edição e o deslocamento otimista de um arrasto não vão para o arquivo
  clone.querySelectorAll(".is-selected, .is-dragging, .is-target, .is-drop-target").forEach((g) =>
    g.classList.remove("is-selected", "is-dragging", "is-target", "is-drop-target"),
  );
  clone.querySelectorAll(".bg-node").forEach((g) => {
    g.removeAttribute("transform");
    g.style.transform = "";
    g.style.transition = "";
  });

  const styleEl = document.createElementNS("http://www.w3.org/2000/svg", "style");
  styleEl.textContent = style || svgStyleText();
  clone.insertBefore(styleEl, clone.firstChild);

  return new XMLSerializer().serializeToString(clone);
}

export async function downloadSvg(svg, scene, filename = "brainagram.svg") {
  const style = svgStyleText(await exportFontFaces());
  const blob = new Blob([toSvgString(svg, scene, { style })], { type: "image/svg+xml;charset=utf-8" });
  triggerDownload(URL.createObjectURL(blob), filename, true);
}

export async function downloadPng(svg, scene, filename = "brainagram.png", scale = 2) {
  const style = svgStyleText(await exportFontFaces());
  const source = toSvgString(svg, scene, { style });
  const img = new Image();
  const url = URL.createObjectURL(new Blob([source], { type: "image/svg+xml;charset=utf-8" }));

  img.onload = async () => {
    // a fonte embutida precisa estar decodificada antes de virar pixels
    await img.decode().catch(() => {});
    const canvas = document.createElement("canvas");
    canvas.width = scene.width * scale;
    canvas.height = scene.height * scale;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = getComputedStyle(document.documentElement).getPropertyValue("--bg-canvas").trim() || "#fbfbf9";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    URL.revokeObjectURL(url);
    canvas.toBlob((blob) => triggerDownload(URL.createObjectURL(blob), filename, true));
  };

  img.onerror = () => URL.revokeObjectURL(url);
  img.src = url;
}

export function triggerDownload(href, filename, revoke) {
  const a = document.createElement("a");
  a.href = href;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  if (revoke) setTimeout(() => URL.revokeObjectURL(href), 4000);
}
