---
version: 1
slug: "site-index-html"
primary_target: "site/index.html"
related_targets: []
---

# Landing page (site/)

Scope: static marketing site in `site/` (Vite, React, atomic design, react-three-fiber). Mode: Persuade. Languages: pt-BR and en.
Audience: developers and tech leads evaluating a diagram tool; they should open the demo first, self-host second.
Proof on hand: the product's own mechanism (played live on the page), the checkout example, the README recording. No testimonials, numbers or logos.
Constraints: demo URL is configurable (`VITE_DEMO_URL`); until set, the action points at the GitHub README. Dark graphite world from DESIGN.md is inherited, not replaced.

## Direction contract

THESIS: The page is a sequence diagram. Navigation is the row of participants, scrolling advances time, each section is a step. It refuses the split hero with a product screenshot and a row of feature cards.

OWN-WORLD: Violet-tinted graphite ground, chalk text, dashed lifelines, arrows in the product's own kinds (solid call, dashed return, dotted async, red dashed fail ending in a crossed ring), one violet impulse, a dot grid that reacts to it. Geist and Geist Mono. Pill label chips on arrows.

STORY: The visitor sees an arrow travel on load, reads that still diagrams lose the narration (four failed messages), watches a real checkout flow play from its text, learns three steps to run it, and opens the demo.

FIRST VIEWPORT: Five participant headers pinned on top as navigation, the fifth is the filled demo button. Lifelines run the full height. A violet arrow from "You" to "Demo" crosses the page above a headline up to 96px set between the lanes, lede and two actions below it, a transport bar with play and a step-segmented scrubber at the bottom.

FORM: "The page is the diagram", candidate 1 of 7 on the ordered list, dealt by seed 11de040f. Signature interaction: scroll (or the play button) drives every arrow's impulse; motion grammar is the product's impulse, arrival pulse and reveal.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
