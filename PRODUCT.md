# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Two audiences with **equal weight**; neither yields to the other by default.

- **Authors**: developers, tech leads and architects who describe the flows
  of systems they build or run (a request crossing services, an async job, an
  authorization chain) to explain them, review them or record a decision.
  They write the `.brain` text or draw on the canvas, often while the system
  is still being designed.
- **Audience**: the people the diagram is played for: new developers being
  onboarded, reviewers of an RFC or postmortem, PMs and non-technical
  stakeholders in a meeting. They may never see the DSL; they press play,
  scrub and read.

A design that serves one audience must not cost the other: writing has to stay
fast for authors, and the result has to be understandable to someone who has
never seen the syntax.

## Product Purpose

Every sequence diagram gets explained out loud ("first the client calls the
API, then it publishes an event…"), and that narration is lost when the
meeting ends. Brainagram turns the narration into the artifact: the
**timeline is part of the diagram**. Messages are grouped into steps and
played in order, with an impulse traveling along each arrow.

Success: someone understands how a flow works by pressing play, without the
author in the room.

## Positioning

Diagram tools such as draw.io, Excalidraw, Mermaid and D2 produce still
images. Brainagram adds **time**, the step-by-step "and then…", while keeping
the diagram as plain text that lives in a repository, diffs cleanly in a pull
request and renders in CI.

## Operating Context

- Used in onboarding, RFCs, postmortems, design reviews and technical
  presentations.
- Diagrams are `.brain` text files: written in the editor or by hand,
  reviewed in pull requests, rendered and formatted by a CLI
  (`mix brainagram.render`, `mix brainagram.fmt`) in CI.
- Existing diagrams come in from Mermaid (`sequenceDiagram`) and PlantUML
  (sequence and component); results go out as SVG, PNG, animated GIF, `.brain`
  files and JSON bundles for docs, slides and chats.
- **Distribution: open source (MIT) for self-hosting.** Teams and individuals
  run their own instance from the GitHub repository. The production Docker image
  embeds PostgreSQL; an external database is a recorded TODO.

## Capabilities and Constraints

- Two diagram kinds: **sequence** (lanes, activation bars, notes, payloads)
  and **architecture** (groups, orthogonal routing, "tidy arrows" to minimize
  crossings).
- **Text is the source of truth.** Canvas gestures (drag, connect, rename,
  change arrow type, delete) are surgical edits of the text; nothing about a
  diagram may exist only in the UI.
- Layout is computed on the server; playback (play, pause, scrub, step, loop,
  speed) runs entirely in the browser.
- Management area with colored projects, search, filters and thumbnails;
  command palette (`Ctrl/⌘ K`); undo/redo across text and canvas.
- UI in **7 languages**: Brazilian Portuguese (default and source language),
  English, Simplified Chinese, Russian, Italian, Japanese and Hindi. Every
  user-facing string is translated; nothing is hard-coded.
- Light and dark themes.
- Implementation constraints for UI work (see `AGENTS.md`): Phoenix LiveView
  1.2, **plain hand-written CSS with design tokens**, no CSS framework, BEM
  `ba-*` component classes, state in attributes.
- **No user accounts yet**: every diagram on an instance is visible to anyone
  who can reach it.
- **Undecided**:
  - browser-only storage and optional accounts are specified in
    `docs/specs/002-contas-e-modo-local.md` but not implemented;
  - whether a public hosted service will ever exist;
  - real-time collaboration, embeds and a public read-only page are roadmap
    ideas, not commitments.

## Brand Commitments

- Name **Brainagram**, written as the lowercase wordmark "brainagram" next to
  the mark in the UI.
- Logo mark: `priv/static/images/logo.svg`, `priv/static/images/favicon.svg`,
  and the README lockups `docs/images/logo-light.svg` /
  `docs/images/logo-dark.svg`.
- Tagline used in the README: "Software diagrams that tell a story."

## Evidence on Hand

- Example diagrams: `docs/examples/*.brain` (checkout sequence and platform
  architecture, in English and Portuguese) and the in-app example catalog.
- Demo recordings: `docs/images/*.gif` (dark mode, produced by the app's own
  exporter; regenerate with `docs/tools/record_gifs.mjs`).
- No testimonials, user counts, adoption figures, benchmarks or customer
  logos exist. Future work must not invent them.

## Product Principles

1. **The text is the diagram.** Every capability must round-trip to the
   `.brain` source; a feature that cannot be written down does not ship.
2. **Time is the product.** A feature earns its place by making the
   step-by-step story clearer to watch or faster to tell.
3. **Write fast, watch without the syntax.** Authors and audience weigh the
   same; neither experience is traded away for the other.
4. **Self-hosting stays simple.** One container runs the whole product; no
   external service is required to use it.
5. **Every language is first-class.** All seven locales ship complete;
   layouts must hold for longer strings and CJK text.

## Accessibility & Inclusion

- Target: **WCAG 2.1 AA**.
- Full keyboard operation of the editor and playback (shortcuts already
  exist: Space, ←/→, F, R, `Ctrl/⌘ K`).
- Respect reduced motion on screen; the story must remain understandable
  without animation (step list, scrubber, final state).
- Meaning is never carried by color alone (arrow kinds already differ by
  line style: solid call, dashed return, dotted async).
- Contrast meets AA in both themes, including inside the diagram canvas.
