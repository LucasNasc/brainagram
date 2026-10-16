# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Add your entry under **Unreleased** in the same pull request as the change, in
one of the sections *Added*, *Changed*, *Deprecated*, *Removed*, *Fixed* or
*Security*.

## [Unreleased]

### Added

- Text DSL for **sequence** and **architecture** diagrams, with steps, groups,
  notes and a `layout {}` block that pins positions.
- Animated playback: play, pause, scrub, speed and step-by-step navigation,
  computed in the browser at 60 fps.
- Visual authoring on the canvas (add, connect, drag, rename), with every
  gesture written back to the text as a surgical edit.
- **Tidy arrows** for architecture diagrams: an orthogonal A\* router that
  reduces crossings and overlaps.
- **Payload balloons** on sequence arrows: collapsed by default, expanded
  while the animation passes, toggled by click.
- Import from **Mermaid** (`sequenceDiagram`) and **PlantUML** (sequence and
  component diagrams).
- Export to **SVG**, **PNG**, **GIF** (HD and light presets), the `.brain` source,
  and a JSON bundle with projects. The same files can be imported back.
- Management area with **projects**, search, filters and sorting.
- UI in **7 languages**: Brazilian Portuguese, English, Simplified Chinese,
  Russian, Italian, Japanese and Hindi, with a flag menu in the top bar.
- Light and dark themes, built on design tokens and hand-written CSS.
- `mix brainagram.render` to render diagrams from the command line.
- Production **Dockerfile** (Elixir release) with an embedded PostgreSQL
  (data in the `/app/data` volume; an external one via `DATABASE_URL`), which
  runs migrations on start, plus a `GET /health` endpoint and a container
  `HEALTHCHECK`.
- The app refuses to start with a `SECRET_KEY_BASE` shorter than 64 bytes.
- External database configuration: `DATABASE_URL` plus `DATABASE_SSL` (`false`,
  `true`, `verify`) and `DATABASE_SSL_CA_FILE`; `.env.example` and a
  `docker-compose.yml` document every variable.
- Spec 002: browser-only mode and optional accounts (not implemented yet).
- `examples/`: sequence and architecture diagrams with and without payloads,
  plus Mermaid and PlantUML sources next to their converted `.brain`; the
  READMEs link the examples and the landing page.
- Landing page in `site/` (static, React + react-three-fiber, pt-BR and en):
  the page itself is a sequence diagram that plays as you scroll.
  English by default, with a flagged language switch, and a roadmap section
  (MCP server, LLM integration, libraries and an embeddable player).
- **Presentation mode**: shared links (`/d/:slug`) open with just the diagram,
  the player and the steps; *Edit* or `P` switches to the editor
  (`?edit=1` opens it directly, as the management area does).
- Steps panel: topics only (number, title, message count) with the current
  step's progress; the messages stay available to screen readers; the timeline is segmented by step; the camera follows the arrow
  that is playing; sequence participants stay pinned at the top while scrolling.
- Editor safety: "unsaved changes" marker, `Ctrl/⌘ S`, a guard before leaving
  with unsaved work, and confirmation before making a diagram public or
  replacing a saved diagram with an example.
- Code editor line numbers; syntax errors say what each line may declare.
- Command palette: play/pause, restart, loop and presentation commands.
- Brand fonts (Geist, Geist Mono) bundled and embedded in SVG/PNG/GIF exports.
- Deployment guide for Coolify (auto deploy on push to `main`); CI also tests
  the Elixir/OTP version used by the production image.
- Community files: contributing guide, code of conduct, security policy,
  support guide, issue forms, pull request template and Dependabot.

### Changed

- The editor's "Examples" menu is now **Open** (examples and import).
- The diagram opens at a readable minimum zoom (66%) instead of shrinking
  wide diagrams until labels are unreadable; resizing keeps the chosen zoom.
- Narrow screens: icon-only top bar, two-row player, steps as a drawer.
- Presentation uses a "projector" scale (no arrow label under ~12px on screen),
  shows how many participants are off-screen ("+2 →") and captions the current
  step over the canvas; the editor keeps the more compact view.
- Nothing is highlighted before playback starts (one live signal).

### Fixed

- Menus support arrow keys; the Edit/Pan switch is a real radio group with a
  visible selection; the error badge is a button; untranslated toolbar labels.

[Unreleased]: https://github.com/LucasNasc/brainagram/commits/main
