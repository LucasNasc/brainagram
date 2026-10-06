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
- Spec 002: browser-only mode and optional accounts (not implemented yet).
- Deployment guide for Coolify (auto deploy on push to `main`); CI also tests
  the Elixir/OTP version used by the production image.
- Community files: contributing guide, code of conduct, security policy,
  support guide, issue forms, pull request template and Dependabot.

[Unreleased]: https://github.com/LucasNasc/brainagram/commits/main
