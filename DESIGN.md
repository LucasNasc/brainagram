---
name: Brainagram
description: Software diagrams that tell a story — calm technical surfaces where the only saturated color is the impulse that moves.
colors:
  brand: "#5b3fe6"
  brand-hover: "#4b30d2"
  brand-soft: "#ece8ff"
  brand-text: "#4a2fd4"
  on-brand: "#ffffff"
  bg-app: "#f6f6f3"
  bg-canvas: "#fbfbf9"
  surface: "#ffffff"
  surface-2: "#f0f0ec"
  surface-3: "#e7e7e1"
  border: "#e3e3de"
  border-strong: "#84848e"
  grid-dot: "#d6d6d0"
  text: "#16161b"
  text-muted: "#5f5f69"
  edge-sync: "#3a3a48"
  edge-return: "#7e7e8a"
  edge-async: "#0c8577"
  edge-fail: "#cc3a31"
  edge-pending: "#898993"
  node-actor: "#0068a3"
  node-service: "#2f86bf"
  node-database: "#00805d"
  node-queue: "#a86f00"
  node-external: "#b0508a"
  node-neutral: "#5f5f69"
  group-bg: "#f3f3ef"
  note-bg: "#fff3bf"
  note-border: "#c9a52a"
  note-text: "#4a3b00"
  success: "#0b7a5a"
  warning: "#945a00"
  danger: "#c2372e"
  info: "#2563c9"
typography:
  headline:
    fontFamily: "Geist, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: "30px"
    letterSpacing: "-0.015em"
  title:
    fontFamily: "Geist, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: "28px"
    letterSpacing: "-0.01em"
  subtitle:
    fontFamily: "Geist, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: "24px"
    letterSpacing: "-0.01em"
  heading:
    fontFamily: "Geist, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: "20px"
  body:
    fontFamily: "Geist, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: "20px"
  control:
    fontFamily: "Geist, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1
  caption:
    fontFamily: "Geist, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: "16px"
  overline:
    fontFamily: "Geist, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: "16px"
    letterSpacing: "0.06em"
  code:
    fontFamily: "Geist Mono, ui-monospace, SF Mono, Cascadia Code, Menlo, monospace"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: "20px"
  node-label:
    fontFamily: "Geist, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "14px"
    fontWeight: 600
    letterSpacing: "-0.01em"
  edge-label:
    fontFamily: "Geist, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "12px"
    fontWeight: 500
  landing-display:
    fontFamily: "Geist, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "clamp(2.5rem, 5.2vw, 5rem)"
    fontWeight: 600
    lineHeight: 1.02
    letterSpacing: "-0.04em"
  landing-title:
    fontFamily: "Geist, ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif"
    fontSize: "clamp(1.875rem, 3.4vw, 3rem)"
    fontWeight: 600
    lineHeight: 1.08
    letterSpacing: "-0.03em"
rounded:
  xs: "4px"
  sm: "6px"
  md: "10px"
  lg: "14px"
  full: "999px"
spacing:
  space-0-5: "2px"
  space-1: "4px"
  space-1-5: "6px"
  space-2: "8px"
  space-3: "12px"
  space-4: "16px"
  space-5: "20px"
  space-6: "24px"
  space-8: "32px"
  space-12: "48px"
  space-16: "64px"
components:
  button:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    typography: "{typography.control}"
    rounded: "{rounded.sm}"
    padding: "0 12px"
    height: "32px"
  button-hover:
    backgroundColor: "{colors.surface-2}"
  button-primary:
    backgroundColor: "{colors.brand}"
    textColor: "{colors.on-brand}"
    typography: "{typography.control}"
    rounded: "{rounded.sm}"
    padding: "0 12px"
    height: "32px"
  button-primary-hover:
    backgroundColor: "{colors.brand-hover}"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.text-muted}"
    rounded: "{rounded.sm}"
    height: "32px"
  button-pressed:
    backgroundColor: "{colors.brand-soft}"
    textColor: "{colors.brand-text}"
  input:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.sm}"
    padding: "0 10px"
    height: "32px"
  badge:
    backgroundColor: "{colors.surface-2}"
    textColor: "{colors.text-muted}"
    rounded: "{rounded.full}"
    padding: "0 8px"
    height: "20px"
  badge-brand:
    backgroundColor: "{colors.brand-soft}"
    textColor: "{colors.brand-text}"
  step-card-current:
    backgroundColor: "{colors.brand-soft}"
    textColor: "{colors.text}"
    rounded: "{rounded.md}"
    padding: "10px 12px 10px 10px"
  play-button:
    backgroundColor: "{colors.brand}"
    textColor: "{colors.on-brand}"
    rounded: "{rounded.full}"
    size: "44px"
  menu:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.md}"
    padding: "4px"
---

# Design System: Brainagram

## Overview

**Creative North Star: "The impulse is the brand"**

Brainagram is a technical drawing that keeps time. Everything at rest is calm and
neutral — paper and graphite in the light theme, graphite and chalk in the dark —
so that the one thing that matters stands out: the **impulse**, the violet dot that
travels along the active arrow and lights up what is happening *now*. The past stays
in quiet ink (done), the future in thin, legible grey (pending), and the present
glows (active). Every visual decision serves that reading of time.

The interface is an instrument, not a stage: dense, precise and quiet, with short
shadows, 1px hairlines and small, exact type. Personality lives in the details —
named motion curves, node shapes that carry meaning, a scrubber segmented by step —
rather than in decoration. There is no neon, no gradient, no "dark hacker" look; the
dark theme is graphite tinted toward violet, not an inverted light theme.

The same tokens drive the application chrome and the SVG diagram, and the SVG export
inlines the active theme's values, so a diagram looks the same in the app, in a PNG
and in a GIF.

**Key Characteristics:**
- One saturated color, reserved for motion, the current step, the primary action and focus.
- Technical-drawing neutrals: warm paper (light), violet-tinted graphite (dark).
- Meaning carried by form first — line style, arrowhead, node shape — and color second.
- Compact 4px rhythm, 32px controls, 1px borders, short shadows.
- Named motion curves for the impulse, the arrival pulse and reveals; reduced motion fully supported.
- Plain hand-written CSS on custom properties; both themes share every token name.

## Colors

A calm technical palette of warm paper and graphite neutrals with exactly one live
signal — the violet impulse — plus a colorblind-aware set (Okabe-Ito, adjusted) for
node kinds and arrow kinds. Values in the frontmatter are the light theme; every
token has a dark counterpart with the same name (see `assets/css/tokens.css`).

### Primary
- **Impulse Violet** (`brand`): the traveling dot, the active arrow, the current step, the
  primary call to action and the focus ring (`focus-ring` aliases it). In the dark theme it
  lightens to a softer violet and pairs with graphite text (`on-brand`), never white.
- **Impulse Violet, deep** (`brand-hover`): hover and pressed state of primary fills.
- **Violet Wash** (`brand-soft`): the selection ground — current step card, active edge
  label chip, synced code line, pressed toggles, input focus halo.
- **Violet Ink** (`brand-text`): text drawn in the brand color on neutral or wash grounds.

### Secondary
- **Edge kinds**: `edge-sync` graphite (solid line, filled head), `edge-return` grey
  (dashed 6/4, open head), `edge-async` teal (dotted, open head), `edge-fail` red
  (dashed, ending in ⊗), `edge-pending` thin grey for arrows that haven't played yet.
- **Node kinds**: `node-actor` deep blue, `node-service` sky blue, `node-database` green,
  `node-queue` amber, `node-external` orchid, each with a `*-soft` tile. They paint only
  the kind glyph and its tile — never the whole node. Component, participant, system,
  node and boundary use `node-neutral`.

### Neutral
- **Paper** (`bg-app`): the application background.
- **Drafting Sheet** (`bg-canvas`): the diagram stage, with a `grid-dot` dot grid every 16px.
- **Card White** (`surface`): panels, nodes, menus, modals.
- **Pencil Wash** (`surface-2`, `surface-3`): hover, tracks, pressed states.
- **Hairline** (`border`): dividers between regions. **Control Edge** (`border-strong`):
  borders of inputs and controls, at least 3:1.
- **Graphite** (`text`) and **Lead** (`text-muted`): reading text and metadata; both pass
  4.5:1 on every neutral surface and on `brand-soft` / `note-bg` in both themes.
- **Sticky Note** (`note-bg`, `note-border`, `note-text`): diagram notes only.
- **Group Ground** (`group-bg`): background of groups and the hover tint of step bands.

### Status
`success` (leaning blue-green so it never forms a red–green pair with `danger`),
`warning`, `danger` and `info`, each with a `*-soft` ground. Status is never color
alone: there is always an icon or dot **and** a word.

### Named Rules
**The One Live Signal Rule.** Violet means "moving or happening now". If something violet
neither moves nor responds to an action, it is wrong.

**The Form Before Color Rule.** Arrow kinds are read by line style and arrowhead, node kinds
by shape and glyph; color only reinforces.

**The Token-Only Rule.** Components never use literal colors. Both themes swap the same names;
anything drawn in the canvas uses a `--` token listed in the export (`EXPORT_VARS`).

## Typography

**Display Font:** Geist (with ui-sans-serif, system-ui, Segoe UI fallback)
**Body Font:** Geist (same stack)
**Label/Mono Font:** Geist Mono (with ui-monospace, SF Mono, Cascadia Code, Menlo)

**Character:** A neutral, engineered sans for the interface and the diagram, and its mono
sibling for anything that is code, time or a number — the pairing reads like a well-set
technical manual.

Both ship with the app as variable `.woff2` files in `priv/static/fonts` (OFL, from Vercel's
`geist` package), declared with `@font-face` in `base.css` and preloaded in the root layout —
no CDN. Exports (SVG, PNG, GIF) embed both fonts, so files look exactly like the screen.

### Hierarchy
- **Headline** (600, 22px/30px, −0.015em): the management area's page title.
- **Title** (600, 20px/28px, −0.01em): page headers.
- **Subtitle** (600, 17px/24px, −0.01em): modal titles; the wordmark uses 17px with −0.03em.
- **Heading** (600, 14px/20px): the editor's diagram title, card titles, empty states (16px/24px).
- **Body** (400, 14px/20px): default reading text.
- **Control** (500, 13px): buttons, tabs, menu items (13px/18px).
- **Caption** (400, 12px/16px): hints, metadata, timestamps.
- **Overline** (600, 11px/16px, +0.06em, UPPERCASE): panel headers, menu group labels, group titles.
- **Code** (Geist Mono 400, 13px/20px): the DSL editor; line height fixed so the gutter aligns.
- **Diagram**: node labels 600 14px (−0.01em); edge labels 500 12px (600 when active);
  payloads, step numbers and kind tags in Geist Mono 11–12px.

### Named Rules
**The Tabular Numbers Rule.** Time, zoom, counters and step numbers use Geist Mono with
`tabular-nums`, so playing never makes digits jitter.

**The Sentence Case Rule.** Everything is sentence case except overlines, which are uppercase.

## Layout

A compact application on a 4px rhythm (`space-1` … `space-16`). Controls are 32px
(28px small, 40px large); panels pad 16px, modals 20px.

- **Editor:** a 48px top bar, then three columns — **Code** (360px), the **canvas**, and
  **Steps** (280px) — with a 64px **player** under the canvas. Floating canvas controls sit
  in the corners (diagram kind top-left, zoom bottom-right).
- **Management area:** a sidebar of projects and a responsive grid of diagram cards
  (`minmax(236px, 1fr)`), each with a canvas-dot thumbnail at 16:10.
- **Breakpoints:** at 1080px the Steps panel hides; at 860px the management grid collapses;
  at 760px the editor stacks code above the canvas (code capped at 40vh) and secondary
  top-bar actions hide.
- The canvas grid is 16px; thumbnails use a 12px grid.

## Elevation & Depth

Flat by default, with short, quiet shadows that only mark what floats. Surfaces are
separated by 1px hairlines and tonal steps (`bg-app` → `surface` → `surface-2`), not by
depth. In the dark theme shadows deepen to stay visible on graphite.

### Shadow Vocabulary
- **Resting lift** (`shadow-sm`): pressed segmented options, scrubber knob.
- **Floating** (`shadow-md`): anything floating over the canvas — zoom and authoring bars, toasts, hovered cards.
- **Overlay** (`shadow-lg`): menus, modals, the command palette, autocomplete.
- **Focus halo** (`shadow-halo`): a 4px `brand-soft` ring on focused inputs and the chosen option.

### Named Rules
**The Float-Only Shadow Rule.** A shadow means "this sits above the canvas or the page".
Cards and panels at rest are bordered, not lifted; a card may lift 2px on hover.

## Shapes

Gently rounded, never pill-everything. `radius-xs` (4px) for kbd keys and label chips,
`radius-sm` (6px) for buttons and inputs, `radius-md` (10px) for menus, step cards and
service nodes, `radius-lg` (14px) for modals, groups and diagram cards, and `radius-full`
for badges, the play button, actor and queue nodes.

In the diagram, **shape carries meaning**: actors are pills, services rounded rectangles,
databases cylinders, queues capsules, external systems dashed (5/4) and boundaries dotted
(2/3). Groups are dashed 4/4 with their title in a chip on the top edge; notes are sticky
paper with a folded corner.

## Components

### Buttons
Tactile and quiet: hairline-bordered, 32px tall, 13px medium labels, a 1px press.
- **Shape:** gently curved (6px; 10px on the 40px large size).
- **Default:** `surface` with a `border` hairline and `text`; hover moves to `surface-2`.
- **Primary:** `brand` fill with `on-brand` text — one per view (Save, New diagram, Play).
- **Ghost:** transparent, `text-muted`; hover gains `surface-2` and `text`.
- **Danger:** `danger` text; hover `danger-soft`.
- **Pressed toggle** (`aria-pressed`): `brand-soft` with `brand-text`.
- **Disabled:** 45% opacity, no press. **Busy:** the icon spins.

### Badges and chips
Pills (`radius-full`, 20px) in `surface-2`/`text-muted`, with semantic variants on `*-soft`
grounds; "soon" badges are dashed outlines. The node-kind chip pairs an 18px tinted tile
with the kind name.

### Inputs / Fields
- **Style:** `surface` with a `border-strong` 1px edge, 6px radius, 32px tall.
- **Focus:** border turns `brand` with the `shadow-halo` ring; no outline glow beyond it.
- **Error:** `danger` border plus an icon and message under the field.
- Read-only and code fields switch to Geist Mono 12px.

### Navigation
A 48px top bar on `surface` with the logo and wordmark, a slash-separated breadcrumb
title, and right-aligned actions; menus are `details` dropdowns with `shadow-lg`, 10px
radius and uppercase overline group labels. Segmented controls (theme, filters) sit on
`surface-2` with the selected option lifted to `surface`.

### Steps panel (signature)
Each step is a card: a 24px numbered circle, a 13px semibold title, mono message lines and
a 2px progress bar. The current step (`aria-current="step"`) fills with `brand-soft` and its
number with `brand`; done steps turn their number to `surface-2`. Message lines turn
`brand-text` while active and `text` once done.

### Player and scrubber (signature)
A 64px bar with a 44px round **play** button in `brand` and a **scrubber segmented by step**:
6px tracks (8px on hover) in `surface-3`, the played part in `edge-sync`, the current
segment in `brand`, and a 14px knob ringed in `surface`. Time reads in Geist Mono
tabular numbers ("0.0 s / 10.8 s").

### Diagram canvas (signature)
- **Arrows** have three states: pending (only the thin track in `edge-pending`), active
  (2.25px `brand` line with the impulse at its tip and the label on a `brand-soft` chip in
  `brand-text`), done (1.5px in the kind's color and pattern, label in `text`).
- **The impulse** is a `brand` core with an `impulse-glow` halo; the destination node pulses
  (`dur-pulse`, `ease-pulso`) when it arrives, and the current step's nodes take a 2px `brand` stroke.
- **Payload chips** sit under the arrow in Geist Mono 11px, dashed while pending, `brand`-edged
  while active; they expand during playback and can be pinned open.
- **Sequence diagrams** use dashed lifelines, `surface-3` activation bars and full-width step
  bands that tint `group-bg` on hover; the current band turns `brand-soft`, with its number
  filled in `brand` and its label in `brand-text`.

### Motion
Named curves are part of the identity: **`ease-impulso`** (the dot leaves slowly, accelerates,
settles), **`ease-pulso`** (arrival ring expands fast, fades slow), **`ease-revelar`** (notes and
cards: fade + 4px rise); the UI uses `ease-ui` and `ease-exit`. An arrow draws in 500–800ms
proportional to its length, with `dur-step-gap` (240ms) between messages. Under
`prefers-reduced-motion`, transitions drop to `dur-fast`, the story stays readable through the
step list, the scrubber and the final state, and pause is always reachable.

## Do's and Don'ts

### Do:
- **Do** reserve `brand` for what moves or is current: the impulse, the active arrow, the current step, one primary action, focus.
- **Do** use tokens for every color, in the app and in the canvas, and add any new canvas token to `EXPORT_VARS`.
- **Do** distinguish kinds and states by form (line style, arrowhead, node shape, icon + word) before color.
- **Do** keep text at 4.5:1 and control edges, arrows, icons and focus at 3:1 in both themes.
- **Do** dim inactive diagram elements by swapping tokens (e.g. `text-muted`, `border`), not by lowering opacity on text.
- **Do** use Geist Mono with tabular numbers for time, zoom, counters and code.
- **Do** keep controls at 32px on the 4px rhythm, with 1px hairlines and the shadow vocabulary above.

### Don't:
- **Don't** paint anything violet that neither moves nor responds to an action.
- **Don't** use neon, gradients or a "dark hacker" look; the dark theme is graphite, not black.
- **Don't** fill whole nodes with their kind color — only the glyph and its tile.
- **Don't** use Unicode glyphs or emoji as icons; use Heroicons through `<.icon>`, with an `aria-label` that names the shortcut on icon-only buttons.
- **Don't** introduce a CSS framework, utility classes or literal hex values in components.
- **Don't** lift cards and panels at rest with shadows; shadows are for what floats.

## Landing page (site/)

Scope: the static marketing site in `site/` (Vite, React, WebGL) and nothing else. It is an
extension of this system, not a second one: dark theme only, with the dark values of
`assets/css/tokens.css` copied into `site/src/styles/tokens.css` and mirrored for WebGL in
`site/src/lib/tokens.ts`. The page is laid out as a sequence diagram: sections are steps,
scrolling (or the transport's play button) advances time, and every arrow uses the product's
own edge kinds and impulse. The app's rules above all hold here; this section records only
what the landing adds.

- **Naming:** hand-written CSS with the `lp-` BEM prefix (`.lp-thing`, `.lp-thing__part`,
  `.lp-thing--variant`); state lives in attributes (`data-state`, `data-current`,
  `aria-current`, and `data-compact` / `data-mid` on the root).
- **Display type:** the only place the system sets type above 22px. `landing-display` is the
  hero headline; the closing headline uses the same style capped lower
  (`clamp(2.25rem, 4.6vw, 4.25rem)`). `landing-title` heads every other step, held to 22ch.
  Both balance their lines. Reading text grows with them: body 16px/1.6, lede 19px/1.6 in
  `text-muted`, held to 36rem. Sentence case throughout; the landing uses no overline.
- **Step wash** (`--step-wash`, #211d42, site only): a violet a step darker than the dark
  `brand-soft`, drawn as a full-bleed band behind the heading of the current step and faded
  in and out as the step changes. It is the landing's version of the sequence diagram's
  current step band.
- **Lanes:** five lifelines whose x positions come from one function (`site/src/lib/lanes.ts`),
  read by the CSS as `--lane-0` … `--lane-4` and by the WebGL scene. Text sits between the
  first and last lane with a 44px gutter, and each text block covers the lifelines behind it
  with the page ground. The participant row is fixed at 88px and the transport bar at 56px.
  Below 820px there are two lifelines, 22px from each edge, and the sections become a row of
  text links between the two end participants (header 100px); from 820px to 1239px the
  wordmark collapses to the symbol.
- **Participant header:** a sequence-diagram participant used as a nav link: 124×44px,
  1.5px `border-strong` edge, `radius-md`, `surface`, 14px semibold. The current section's
  header takes a `brand` edge on `brand-soft` with `brand-text`; the fifth is filled
  `brand` and opens the demo.
- **Message label:** a pill chip centered over its arrow, `surface-2` with `text-muted` while
  pending, `brand-soft` with `brand-text` while active, `text` once done (`edge-fail` for a
  failure, `edge-async` in Geist Mono for an async message). Labels are real text and links;
  the canvas draws only lifelines, arrows, the impulse, the arrival ring and the dot grid, so
  the page stays readable without WebGL.
- **Transport:** the app's player reduced to a fixed bar: previous, play and next, one 6px
  scrubber segment per step filling in `brand`, tabular time in Geist Mono and the current
  step as "2/5 name". Under `prefers-reduced-motion` the play button is removed and previous
  and next remain.
- **Icons:** inline SVG drawn on a 20px grid with a 1.5px stroke (the app's `<.icon>`
  component is not available outside Phoenix); never glyphs.

### Named Rules
**The Participant Row Rule.** On the landing, navigation is the diagram's participant row: one header per section, each sitting on its own lifeline, the last one the filled demo action. Don't add a separate nav bar, menu or tab strip beside it.

**The Step Wash Rule.** `--step-wash` exists only in `site/` and only as the full-bleed band behind the current step's heading. Everywhere else the selection ground is `brand-soft`.
