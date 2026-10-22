# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Add your entry under **Unreleased** in the same pull request as the change, in
one of the sections *Added*, *Changed*, *Deprecated*, *Removed*, *Fixed* or
*Security*.

## [Unreleased]

## [0.2.0] - 2026-10-22

### Added

- **Embedding**: Export → Embed (iframe) gives a snippet, with a live preview
  and options, to play a public diagram inside any web page. The embed page
  (`/embed/:slug`) is a plain HTTP page with the app's player (no cookies, no
  WebSocket, cached), takes `theme`, `controls`, `autoplay`, `loop`, `step` and
  `lang`, and can be turned off or limited to some sites with
  `BRAINAGRAM_EMBED` and `BRAINAGRAM_EMBED_ORIGINS`.

## [0.1.0] - 2026-10-20

First public release.

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
- **Demo mode** (`BRAINAGRAM_DEMO=true`): a public playground with no database,
  diagrams in a temporary in-memory cache (24 h, 500 diagrams) and a notice on
  every screen.
- `examples/`: sequence and architecture diagrams with and without payloads,
  plus Mermaid and PlantUML sources next to their converted `.brain`; the
  READMEs link the examples and the landing page.
- Landing page in `site/` (static, React + react-three-fiber, pt-BR and en):
  the page itself is a sequence diagram that plays as you scroll.
  English by default, with a flagged language switch, and a roadmap section
  (MCP server, LLM integration, libraries and an embeddable player).
  Roadmap arrows travel as far as each idea has come and wait there; the
  READMEs list the same roadmap.
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
- The minimum supported Elixir is now 1.18 (with Erlang/OTP 27), the oldest
  version CI tests.

### Fixed

- "No connection" / "The server didn't respond" when the instance is reached
  on a domain other than `PHX_HOST`: the LiveView WebSocket now accepts the
  request's own host by default (`PHX_CHECK_ORIGIN` pins a list).
- Behind an HTTPS proxy (Coolify's Caddy or Traefik) the LiveView connection was
  refused with 403: the app now applies `X-Forwarded-Proto`, `-Port` and `-Host`
  before the socket's origin check.
- The new diagram dialog sends the name after a short pause instead of on every
  keystroke, so a slow or fallback connection no longer makes it churn.
- Dialogs flickered on every keystroke in Chromium: entrance animations kept
  `fill-mode: both`, so the overlay and the empty state stayed as composited
  layers and were recomposited on each update. They now use `backwards`.
- Menus support arrow keys; the Edit/Pan switch is a real radio group with a
  visible selection; the error badge is a button; untranslated toolbar labels.

[Unreleased]: https://github.com/LucasNasc/brainagram/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/LucasNasc/brainagram/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/LucasNasc/brainagram/releases/tag/v0.1.0
