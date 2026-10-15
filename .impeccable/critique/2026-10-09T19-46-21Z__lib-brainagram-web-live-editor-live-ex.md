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
timestamp: 2026-10-09T19-46-21Z
slug: lib-brainagram-web-live-editor-live-ex
---
Method: dual-agent (A: design review · B: detector + browser)

## Design Health Score — editor, run 3 (29/40, Good)

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Same step status shown 3-4 times; canvas gives no "stale" marker after a syntax error |
| 2 | Match System / Real World | 3 | "Abrir" opens examples/import, not saved diagrams |
| 3 | User Control and Freedom | 3 | Mobile Passos drawer stays open after picking a step |
| 4 | Consistency and Standards | 3 | Restart and loop icons nearly identical on mobile |
| 5 | Error Prevention | 2 | Undeclared participants silently auto-created (ghost -> nobody = "Sem erros") |
| 6 | Recognition Rather Than Recall | 3 | Ctrl K hint is a small ghost button |
| 7 | Flexibility and Efficiency | 4 | Palette, keys, undo across text and canvas, speed, loop |
| 8 | Aesthetic and Minimalist Design | 2 | Edit top bar ~14 controls; edit canvas ~66% zoom with ~6px text |
| 9 | Error Recovery | 3 | Message quotes the line and explains the syntax |
| 10 | Help and Documentation | 3 | Collapsed quick reference; no first-run cue |
| **Total** | | **29/40** | **Good** |

## Priority Issues

1. [P1] Mobile presentation poster state shows 1 of 7 participants — at 100% on 375px; first label clipped. Fix: fit-to-width or ~50-60% minimum on narrow viewports until play, then camera follows. Command: /impeccable adapt
2. [P1] Mobile Passos drawer layering and flow — step caption and "+N →" cue draw above the drawer; picking a step keeps it open covering ~85% of the canvas; no dialog semantics. Fix: raise drawer above overlays, close on step selection or half-height sheet, role=dialog/aria-modal, focus return. Command: /impeccable harden
3. [P2] Edit mode compresses the canvas — 3 columns leave ~480px at 66%; ~14 top-bar controls; code lines clipped. Fix: collapse steps panel in edit mode, fold Duplicar/theme into overflow. Command: /impeccable layout
4. [P2] Silent auto-creation of undeclared participants. Fix: non-blocking warning with "declare" quick fix / near-duplicate name hint. Command: /impeccable clarify
5. [P3] "Abrir" mislabeled. Fix: rename (7 locales). Command: /impeccable clarify

## Detector

CLI 0 findings. Browser: only overused-font (Geist, user-confirmed; detect.js ignores config) and flat-type-hierarchy on desktop (h2 11px / body 12px / h1 14px, 1.17:1). No contrast or overflow findings.

## Observations

- "+4 →" cue can overlap an arrow label; no left-side cue.
- Selected Editar/Mover state subtle; Soltar posições disabled with same weight.
- No finish state marking the end of the story.
