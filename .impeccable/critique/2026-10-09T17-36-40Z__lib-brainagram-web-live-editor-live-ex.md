---
target: editor
total_score: 24
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "file:C:\\projetos\\brainagram\\lib\\brainagram_web\\live\\editor_live.ex"
target_fingerprint: "sha256:5ac5a6445773ac7eb57bb47153b325b94fb97956e759b16dc807354464d75edb"
target_path: "C:\\projetos\\brainagram\\lib\\brainagram_web\\live\\editor_live.ex"
timestamp: 2026-10-09T17-36-40Z
slug: lib-brainagram-web-live-editor-live-ex
---
Method: dual-agent (A: design review · B: detector + browser)

## Design Health Score — editor (lib/brainagram_web/live/editor_live.ex)

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | No unsaved/dirty state; Edit/Move selected option nearly invisible (surface on surface track) |
| 2 | Match System / Real World | 3 | Plain PT-BR and "Passos" metaphor, but authoring jargon ("Soltar posições", "Nó") shown to everyone |
| 3 | User Control and Freedom | 2 | Undo spans text and canvas; closing the tab loses edits with no guard; Public/Private flips in one click |
| 4 | Consistency and Standards | 2 | role="menu" without arrow keys; Import hidden under "Exemplos" |
| 5 | Error Prevention | 2 | No Ctrl+S, no beforeunload; errors appear mid-typing |
| 6 | Recognition Rather Than Recall | 3 | Autocomplete, quick reference, tooltips with shortcuts |
| 7 | Flexibility and Efficiency | 3 | Good shortcuts; command palette lacks play/loop/speed |
| 8 | Aesthetic and Minimalist Design | 3 | Calm and token-disciplined; chrome wins the space contest against the diagram |
| 9 | Error Recovery | 2 | Last valid scene preserved; message doesn't say what was expected; "Linha N" cited with no line numbers |
| 10 | Help and Documentation | 2 | Quick reference collapsed at the bottom; no guidance for a viewer |
| **Total** | | **24/40** | **Acceptable** |

## Design Specificity Verdict

LLM: concept and canvas are specific (violet impulse, step bands, live step line, mono time, product-voiced copy); the shell (code | canvas | panel + floating toolbars) is category-interchangeable. The distinctive part is the smallest thing on screen: fit lands at 29% desktop / 14% mobile, labels at 4–6px.

Deterministic scan: CLI 0 findings on editor_live.ex, core_components.ex, layouts.ex (also with --no-config). Browser detect.js: only overused-font (Geist, user-confirmed; browser detector does not read ignoreValues). 3 low-contrast hits were transition artifacts of a mid-session theme switch; clean reloads in light theme reported none. Nothing fired inside the SVG canvas.

## Priority Issues

1. [P1] Shared link opens the authoring tool — /d/:slug shows code, Save, Duplicate, Node, Connect; canvas defaults to Edit (readMode). Contradicts PRODUCT.md success (understand by pressing play without the author). Fix: view/present mode default for shared links (or P key): collapse code, default Move, keep diagram + player + steps. Command: /impeccable layout
2. [P1] Diagram illegible at fit — 29% desktop (8 lanes), 14% mobile; lane names scroll off when zoomed; playback doesn't follow the active arrow (only ←/→ call focusY); resize calls fit() and drops user zoom (diagram_canvas.js:51). Fix: sticky lane headers, camera follows the step during play, readable minimum zoom with panning, keep user zoom on resize. Command: /impeccable adapt
3. [P1] Mobile overflow — at 375px the top bar lays out ~869px wide (Save, locale, theme, speed, loop off-screen); code textarea 64px; Steps panel display:none below 1080px removes the aria-live announcer. Fix: overflow menu, two-row player, Steps as a drawer with the live region outside it. Command: /impeccable adapt
4. [P2] Steps and scrubber don't carry the story — DESIGN.md signature step card (mono messages, progress bar, done state) has CSS (components.css:160–165) but is never rendered (editor_live.ex renders number/title/count only); scrubber is a single native range, not step-segmented, announces 0–1000 with no aria-valuetext; SVG content unreachable for screen readers. Fix: render messages and done state, segment the scrubber, aria-valuetext with step label. Command: /impeccable polish
5. [P2] Unsaved work is invisible — no dirty marker, no Ctrl+S, no beforeunload, Save always primary; loading an example silently replaces a saved diagram's text (undo toast only). Fix: "Alterações não salvas" marker, quiet Save when clean, Ctrl+S, leave guard. Command: /impeccable harden

## Persona Red Flags

Alex (power user): no Ctrl+S; Ctrl+K lacks play/pause, loop, speed; error bar flickers while typing; resize resets zoom; errors cite line numbers the editor doesn't show.
Sam (keyboard + screen reader): scrubber value meaningless; canvas content unreachable; menus without arrow keys; "1 erro" badge is a focusable-less span; #source lacks aria-invalid; aria-label "Canvas"/"Zoom" hard-coded and untranslated (editor_live.ex:780, 855); live region disappears below 1080px.
Audience viewer (never saw the DSL): sees DSL code first with Edit mode on; 4–6px labels at fit; authoring jargon in the toolbar; step cards give titles and counts, not what happens.

## Minor Observations

- Step 1 filled violet at t=0 before anything plays (strains One Live Signal).
- At 89% zoom the floating canvas toolbar covers arrows.
- Public badge acts as a control but reads as status; no confirmation.
- Code textarea wraps long lines, no line-number gutter.
- Edit-mode selection is also violet and would compete with the active step during playback.
- Cognitive load: 4/8 checklist items fail; top bar 9 options, player 7, canvas toolbar 6–7.

## Questions to Consider

1. If the audience were the default and authoring the opt-in, what would /d/:slug remove?
2. "Time is the product", yet the canvas gets ~55% of the width and play isn't in Ctrl+K. What would a timeline-first layout look like?
3. Could the code pane play along, highlighting the line of the message in flight?
