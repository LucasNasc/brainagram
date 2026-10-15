---
target: editor
total_score: 29
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 2
target_identity: "file:C:\\projetos\\brainagram\\lib\\brainagram_web\\live\\editor_live.ex"
target_fingerprint: "sha256:5089585dd7c03acbf09fac453d172d0058e6213033bbbacd95f070f13a6cbba6"
target_path: "C:\\projetos\\brainagram\\lib\\brainagram_web\\live\\editor_live.ex"
timestamp: 2026-10-09T18-06-31Z
slug: lib-brainagram-web-live-editor-live-ex
---
Method: dual-agent (A: design review · B: detector + browser)

## Design Health Score — editor (lib/brainagram_web/live/editor_live.ex), run 2

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Dirty marker, error badge, step announce; canvas doesn't flag "last valid version" during errors; no step title on canvas in mobile presentation |
| 2 | Match System / Real World | 3 | Plain PT-BR; step messages set in mono read like code |
| 3 | User Control and Freedom | 3 | Coalesced undo, leave guard; switching modes resets the camera |
| 4 | Consistency and Standards | 3 | "Editar" means mode switch and canvas tool; restart/loop icons nearly identical |
| 5 | Error Prevention | 3 | Making public confirms; making private doesn't |
| 6 | Recognition Rather Than Recall | 3 | Palette Save row lacks Ctrl+S hint |
| 7 | Flexibility and Efficiency | 3 | Strong shortcuts; no code↔playing-step sync |
| 8 | Aesthetic and Minimalist Design | 3 | Calm; edit top bar ~11 controls |
| 9 | Error Recovery | 3 | Message quotes the line and lists valid forms |
| 10 | Help and Documentation | 2 | No cue for the audience ("press play / ←→") |
| **Total** | | **29/40** | **Good** |

## Design Specificity Verdict

LLM: now product-specific (step-segmented scrubber, numbered bands, violet active arrow with wash label chip, payload chips, "who → who · what" step cards, two modes for two audiences); color discipline holds; dark theme passes contrast. Weak point moved from identity to legibility of the story for the audience.

Deterministic scan: CLI 0 findings (editor_live.ex, core_components.ex, layouts.ex). Browser detect.js across presentation/editor//new, light/dark, desktop/mobile: no element-level findings (no low-contrast, no overflow). Page-level: overused-font (Geist, user-confirmed; browser detector ignores config) and flat-type-hierarchy (h1 14px vs body 12px, 1.17:1 < 1.25:1) — judgment call for a dense tool UI.

## Priority Issues

1. [P1] Default framing is neither whole nor readable — presentation at 1440 shows 5 of 7 lanes (mobile 2); Fit gives the same 66% (MIN_READABLE); labels ~8px, chips ~7px; no cue that more lanes exist. Fix: readability floor by on-screen label size (≥11px), edge cue "+2 →" or mini-map, separate "fit all" vs "fit readable" in presentation, collapsible steps panel. Command: /impeccable adapt
2. [P1] Step context disappears from the canvas — band labels anchored at the diagram's left edge go offscreen when the camera follows; mobile presentation shows no step title. Fix: presentation caption ("3/5 · Em paralelo…") or sticky band labels. Command: /impeccable clarify
3. [P2] Steps panel reads like code; heavy semantics — 12px mono messages wrap mid-arrow in 280px; <ol> inside <button class="ba-step"> is invalid and makes the whole card the accessible name. Fix: sans prose, mono only for routes/payloads; collapse non-current messages; only the header is the button. Command: /impeccable typeset
4. [P2] Edit chrome density and risky toggle — ~11 top-bar controls; Público/Privado badge changes data in one click (private without confirmation); two violet primaries (dirty Save + Play); "Abrir" doesn't open own diagrams. Fix: overflow "⋯" for Duplicar/visibility, rename "Abrir" to "Exemplos e importação". Command: /impeccable distill
5. [P2] Keyboard/screen-reader gaps — mobile drawer lacks dialog role/inert background; Esc leaves focus on a hidden step (setDrawer doesn't return focus); Conectar lacks aria-pressed; error line marked only by a red gutter number. Command: /impeccable harden

## Persona Red Flags

Alex: mode switch loses camera; no playback→code line sync (DESIGN.md mentions it); palette Save lacks Ctrl+S.
Sam: very long step-button names; focus lost on drawer close; connect state not exposed.
Audience: lands on grey diagram with tiny labels and cut lanes; no step caption; mono step text; mobile 2 lanes and no step title.

## Minor Observations

- /new on mobile flashes an empty canvas ("100%", "0.0 s") before the scene; no loading state.
- Mobile player wraps to 3 rows (125px); touch targets 28–32px.
- Dark scrubber track surface-3 vs surface 1.24:1.
- Font preload "not used within a few seconds" console warning (fonts do load).
- Motion unverified live (rAF frozen in the pane); judged from code.

## Questions to Consider

1. Why does presentation inherit the author's 66% density instead of a "projector" scale where no label is under 12px?
2. Should the current step's title be the headline of presentation mode, a caption that changes with time?
3. Could the code pane follow playback, highlighting the line of the message in flight?
