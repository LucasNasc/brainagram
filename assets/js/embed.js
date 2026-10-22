// O player embutível (/embed/:slug): o diagrama tocando dentro do iframe de
// outro site. Sem LiveView e sem rede: a cena chega pronta no HTML, e daqui em
// diante tudo é local, com o mesmo renderizador e a mesma linha do tempo do app.

import { render, measure } from "./brainagram/renderer";
import { Timeline, buildSchedule } from "./brainagram/timeline";
import { Viewport } from "./brainagram/viewport";

// No iframe cabe pouco: o enquadramento pode diminuir mais que no app para o
// diagrama inteiro aparecer; zoom e arrasto continuam à mão.
const MIN_READABLE = 0.35;

function start() {
  const data = document.getElementById("bg-scene");
  const stage = document.getElementById("embed-stage");
  if (!data || !stage) return;

  const scene = JSON.parse(data.textContent);
  const opts = document.body.dataset;
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const index = measure(render(stage, scene));
  const schedule = buildSchedule(scene);
  const bar = document.getElementById("embed-bar");
  const part = (name) => bar && bar.querySelector(`[data-embed="${name}"]`);
  const play = part("play");
  const scrub = part("scrub");
  const caption = part("caption");

  const timeline = new Timeline(index, schedule, {
    loop: opts.loop === "true",
    onTick: (tl) => sync(tl),
  });

  const viewport = new Viewport(index.svg, scene, { insetTop: 8, minReadable: MIN_READABLE });
  new ResizeObserver(() => viewport.resize()).observe(stage);

  function sync(tl) {
    if (play) {
      play.setAttribute("aria-pressed", String(tl.playing));
      const label = tl.playing ? play.dataset.labelPause : play.dataset.labelPlay;
      play.setAttribute("aria-label", label);
      play.title = label;
    }
    if (scrub && document.activeElement !== scrub) {
      scrub.value = String(Math.round((tl.t / tl.total) * 1000));
    }
    if (caption) {
      const step = schedule.steps.find((s) => s.index === tl.currentStep);
      caption.textContent = tl.started && step ? `${step.index + 1}/${schedule.steps.length} · ${step.label}` : "";
    }
  }

  play && play.addEventListener("click", () => timeline.toggle());
  part("prev") && part("prev").addEventListener("click", () => timeline.prevStep());
  part("next") && part("next").addEventListener("click", () => timeline.nextStep());
  scrub &&
    scrub.addEventListener("input", () => {
      timeline.pause();
      timeline.seek((Number(scrub.value) / 1000) * timeline.total);
    });

  // Espaço toca e pausa; ← e → andam um passo (só quando o foco está no iframe).
  document.addEventListener("keydown", (e) => {
    if (e.target === scrub) return;
    if (e.key === " ") {
      e.preventDefault();
      timeline.toggle();
    } else if (e.key === "ArrowRight") {
      timeline.nextStep();
    } else if (e.key === "ArrowLeft") {
      timeline.prevStep();
    }
  });

  // Clique no chip do payload fixa o balão aberto, como no app.
  index.svg.addEventListener("click", (e) => {
    const chip = e.target.closest("[data-payload]");
    const item = chip && index.edges.get(chip.dataset.payload);
    if (!item || !item.payload) return;
    const pinned = !item.payload.classList.contains("is-pinned");
    item.payload.classList.toggle("is-pinned", pinned);
    item.group.querySelector(".bg-payload-chip")?.classList.toggle("is-pinned", pinned);
  });

  const first = Number(opts.step) || 1;
  if (first > 1) timeline.gotoStep(first - 1);
  else sync(timeline);

  // Autoplay só quando o iframe aparece na tela, e pausa quando sai dela.
  // Com movimento reduzido, nunca toca sozinho.
  if (opts.autoplay === "true" && !reduced) {
    new IntersectionObserver(
      ([entry]) => (entry.isIntersecting ? timeline.play() : timeline.pause()),
      { threshold: 0.5 },
    ).observe(stage);
  }
}

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
else start();
