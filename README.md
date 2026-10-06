<div align="center">

<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.svg">
    <img src="docs/images/logo-light.svg" alt="Brainagram" width="300">
  </picture>
</h1>

**Software diagrams that tell a story.**
Write the flow as text, press play, and watch the messages travel along the arrows — step by step.

**English** · [Português (Brasil)](README.pt-BR.md)

[![CI](https://github.com/LucasNasc/brainagram/actions/workflows/ci.yml/badge.svg)](https://github.com/LucasNasc/brainagram/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-0.1.0-7c5cff.svg)](CHANGELOG.md)
[![Tests](https://img.shields.io/badge/tests-350%2B%20passing-2f9e4f.svg)](#development)
[![License: MIT](https://img.shields.io/badge/license-MIT-7c5cff.svg)](LICENSE)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)
<br>
![Elixir](https://img.shields.io/badge/Elixir-1.15%2B-4e2a8e.svg)
![Phoenix](https://img.shields.io/badge/Phoenix-1.8-f05423.svg)
![Phoenix LiveView](https://img.shields.io/badge/LiveView-1.2-f05423.svg)
![Languages](https://img.shields.io/badge/languages-7-0c9b8c.svg)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-0c9b8c.svg)](CONTRIBUTING.md)

</div>

<p align="center">
  <img src="docs/images/checkout.en.svg" alt="A sequence diagram rendered by Brainagram: a checkout flow in three steps, with payload chips under the arrows" width="760">
</p>

---

## Why

Every sequence diagram gets explained out loud: *"first the client calls the API,
then it publishes an event…"*. That narration is what makes the diagram make
sense — and it is lost the moment the meeting ends.

Brainagram turns the narration into the artifact. The **timeline is part of the
diagram**: you group messages into steps, and the diagram plays them in order,
with an impulse traveling along each arrow. It is built for onboarding, RFCs,
postmortems and design reviews — anywhere someone would otherwise point at a
static image and say "and then…".

## Features

- **Text is the source of truth.** A small DSL (`.brain`) describes the diagram;
  layout is computed, never stored. Diffs are readable and reviewable in a PR.
- **Animated timeline.** Play, pause, scrub, step forward and back, loop, change speed.
- **Two diagram kinds.** *Sequence* (lanes, activation bars, notes) and
  *architecture* (layered layout with groups and orthogonal routing).
- **Visual authoring on top of the text.** Drag nodes, connect them, rename,
  change arrow types, delete — every gesture is a surgical edit of the text, so
  comments and formatting survive.
- **Payloads.** Attach what a message carries (a JSON body, a SQL statement,
  headers) as a chip under the arrow. It expands while the message plays and
  can be pinned open with a click.
- **Tidy arrows.** One click rearranges an architecture diagram to minimize
  crossings — e.g. 8 → 1 crossing on the example below.
- **Import** Mermaid `sequenceDiagram`, PlantUML sequence and component diagrams,
  `.brain` files and Brainagram bundles.
- **Export** SVG, PNG (2×), animated GIF (HD or light), `.brain` files and
  `.json` bundles of whole projects.
- **Projects.** A management area to organize diagrams into colored projects,
  with search, filters, thumbnails and live updates.
- **Command palette** (`Ctrl/⌘ K`), keyboard shortcuts, undo/redo that covers
  both text and canvas edits.
- UI in **7 languages** — Brazilian Portuguese, English, Simplified Chinese,
  Russian, Italian, Japanese and Hindi — plus light and dark themes.
- **CLI** to render and format `.brain` files in CI — no browser needed.

<p align="center">
  <img src="docs/images/platform.en.svg" alt="An architecture diagram: Edge, Application and Data groups with orthogonal arrows" width="460">
</p>

## Quick start

**Requirements:** Elixir 1.15+ and Erlang/OTP 25+ (CI runs Elixir 1.18 / OTP 27),
and PostgreSQL (CI uses 16).

```bash
git clone https://github.com/LucasNasc/brainagram.git
cd brainagram

# Postgres for development (skip if you already have one on localhost:5432)
docker run -d --name brainagram-pg -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:16

mix setup          # deps, database, migrations, example diagrams, assets
mix phx.server     # http://localhost:4000
```

The development database defaults to `postgres` / `postgres` on `localhost`
(see `config/dev.exs`). `mix setup` also runs `priv/repo/seeds.exs`, which loads
the example diagrams through the same command bus the UI uses.

## Using Brainagram

### 1. The management area (`/`)

Your diagrams, as cards with a live thumbnail.

- **Projects** on the left: create one with **+**, give it a name and a color.
  *All diagrams* and *No project* are always there. Deleting a project never
  deletes its diagrams — they move to *No project*.
- **New diagram** asks for a name, a kind (sequence or architecture) and a
  project, and opens the editor with a short starter example.
- Each card's **⋯** menu: open, rename, move to project, duplicate, make
  public/private, download `.brain`, delete.
- Search, filter by kind and sort; the filter lives in the URL, so a project
  view can be bookmarked and shared.
- **Import** and **Export** — see [Import and export](#import-and-export).

The **Scratch editor** (`/new`) opens the editor without saving anything until
you press **Save**.

### 2. The editor (`/d/:slug`)

```
┌───────────── code ─────────────┬──────────── canvas ────────────┬─ steps ─┐
│ diagram sequence "Checkout"    │  ○ Customer   ○ API   ○ Orders │ 1 ...   │
│ user -> api : POST /orders     │      ●─────────▶               │ 2 ...   │
│   payload: {"items": 3}        │                                │ 3 ...   │
└────────────────────────────────┴──────── ▶ timeline ───────────┴─────────┘
```

- **Code** on the left: the diagram recompiles as you type. Errors point to the
  line and the last valid diagram stays on screen. Autocomplete suggests node
  kinds, keywords, arrows and existing ids.
- **Canvas** in the middle, with two modes (`E` toggles):
  - **Edit** — drag nodes, drag from a node's handle to connect, double-click
    to rename a node or an arrow label, double-click an empty area to add a
    node, select an arrow to change its type or add a payload (`P`).
  - **Pan** — dragging moves the view; clicks still toggle payloads.
- **Steps** on the right: click one to jump there.
- **Toolbar:** *Node*, *Connect*, *Tidy arrows* (architecture), *Release
  positions* (forget dragged positions and go back to automatic layout).

### Keyboard shortcuts

| Key | Action |
|---|---|
| `Space` | play / pause (hold and drag to pan) |
| `←` `→` | previous / next step |
| `F` | fit diagram to screen |
| `R` | restart |
| `E` | toggle Edit / Pan mode |
| `Ctrl/⌘ K` | command palette |
| `Ctrl/⌘ Z`, `Ctrl/⌘ Shift Z` | undo / redo (text and canvas) |
| `Shift Alt F` | format code |
| `F8` | go to next error |
| `Alt ↑` `Alt ↓` | move the current `step` block up / down |
| `Enter` | rename the selected node / arrow |
| `P` | edit the selected arrow's payload |
| `Delete` | remove the selection |
| `Esc` | cancel (also cancels a GIF recording) |

## The DSL

A diagram is plain text. Nodes used in arrows are declared automatically —
`a -> b` is already a valid diagram — and without any `step`, every message
becomes its own step.

```text
diagram sequence "Checkout"          # or: diagram architecture "Platform"

actor       user   "Customer"        # <kind> <id> "<label>"
participant api    "API Gateway"
service     orders "Order Service"
database    db     "PostgreSQL"

step "Customer places the order" {   # a step of the animation
  user -> api : POST /orders
    payload """
    {"items": [{"sku": "A-1", "qty": 2}]}
    """
  api -> orders : CreateOrder
  note over user, api : notes anchor to one or more nodes
}
```

**Arrows**

| Arrow | Meaning |
|---|---|
| `a -> b` | synchronous call (opens an activation bar) |
| `a --> b` | return / response (closes the bar) |
| `a ->> b` | asynchronous, fire-and-forget |
| `a -x b` | failure / timeout |

**Node kinds:** `actor`, `participant`, `service`, `component`, `database`,
`queue`, `external`, `system`, `node`, `boundary`.

**Blocks and lines**

| Syntax | What it does |
|---|---|
| `step "…" { … }` | a step of the timeline |
| `group "…" { … }` | groups nodes (a VPC, a bounded context…) |
| `note over a, b : text` · `note left of a : …` · `note right of a : …` | annotation |
| `payload: …` (right below a message) | what the message carries; several lines add up |
| `payload """ … """` | multi-line payload — raw text, `#` and `//` are content here |
| `layout { api at (420, 680) }` | positions pinned by dragging (written for you by the canvas) |
| `#` or `//` | comment (quotes are respected) |

Portuguese aliases are accepted too, e.g. `diagram arquitetura` and `dados:`.
More examples live in [`docs/examples/`](docs/examples).

## Import and export

| Format | Export | Import |
|---|---|---|
| `.brain` (one diagram, the DSL text) | editor → *Export → .brain file*; card → *Download .brain* | management area → *Import*; editor → *Import* |
| `.json` bundle (diagrams + their projects) | management area → *Export* (the open project, *No project* or everything) | management area → *Import* (projects are recreated; one with the same name is reused) |
| Mermaid `sequenceDiagram` | — | both import dialogs |
| PlantUML (sequence → sequence, component → architecture) | — | both import dialogs |
| SVG, PNG 2× | editor → *Export* | — |
| GIF (HD 2× or light 1×) | editor → *Export* | — |

What doesn't convert on import becomes a comment at the top of the code, never a
hard failure. Importing many files at once reports, per file, what went in and
what didn't (with the line of the error).

## Command line

The domain runs without Phoenix or a database, so diagrams can be rendered and
formatted in CI:

```bash
mix brainagram.render docs/examples/checkout.en.brain                 # → .svg next to it
mix brainagram.render docs/examples/checkout.en.brain -o out/c.svg
mix brainagram.render docs/examples/checkout.en.brain --format png --scale 2   # needs resvg, rsvg-convert or ImageMagick

mix brainagram.fmt                       # format every **/*.brain
mix brainagram.fmt --check-formatted     # for CI: fails if anything would change
```

The images in this README were generated with `mix brainagram.render`.

## How it works

```
        ┌──────────────── server (Elixir) ────────────────┐   ┌── browser (JS) ──┐
text →  │ Parser → AST → Layout → Scene (positions, paths) │ → │ SVG → Timeline   │
        └──────────────────────────────────────────────────┘   └──────────────────┘
              runs as you type (debounced)                         60 fps, local
```

- **The server decides *where*** — layout is the hard, rule-heavy part, and in
  Elixir it is pure, testable code. The `Scene` carries absolute coordinates and
  the SVG path of every arrow.
- **The browser only draws and plays.** Play, scrub, zoom and pan never touch
  the server. `seek(t)` is a pure function of time.
- **Layered architecture with CQRS.** `web → application → domain → shared`;
  infrastructure (Ecto, PubSub) implements ports and is wired only in
  `config/config.exs`. The rule is enforced by a test
  (`test/brainagram/architecture_test.exs`). Every change goes through
  `Bus.dispatch/2`, every read through `Bus.ask/2`.

```
lib/brainagram/
├── shared/                         no business rules
├── domain/diagramming/             pure rules — no Ecto, no Phoenix
│   ├── diagram.ex  project.ex      aggregates
│   ├── dsl/                        parser, printer, surgical editor
│   ├── layout/                     sequence, architecture, router, untangle
│   ├── authoring.ex                canvas gestures as text edits
│   └── import/  render/            Mermaid/PlantUML import, server-side SVG
├── application/                    commands, queries, handlers, read models
└── infrastructure/                 Ecto repositories/readers, PubSub, catalog
lib/brainagram_web/                 LiveViews, controllers, components
assets/                             hand-written CSS (design tokens) and JS hooks
```

The design decisions are documented (in Portuguese) in
[`docs/ARQUITETURA.md`](docs/ARQUITETURA.md) and
[`docs/specs/001-autoria-visual.md`](docs/specs/001-autoria-visual.md).

## Development

```bash
mix test            # unit, property-based (StreamData) and LiveView tests
mix precommit       # compile with warnings as errors, format, test
```

Most tests don't need the database: the domain and application layers are
tested with in-memory repositories. CI (`.github/workflows/ci.yml`) checks for
unused dependencies, formatting, warnings (as errors) and up-to-date gettext
extraction, then runs the full suite against Postgres.

**Conventions worth knowing** (the full list is in [`AGENTS.md`](AGENTS.md)):

- **CSS is hand-written** — no Tailwind. Use the design tokens in
  `assets/css/tokens.css`; components are BEM with the `ba-` prefix; canvas
  rules in `diagram.css` start with `.bg-`.
- **Every UI string is translated.** Portuguese is the msgid:
  `gettext("Salvar")`. After changing strings run
  `mix gettext.extract --merge` and fill the empty `msgstr` in
  `priv/gettext/<locale>/LC_MESSAGES/default.po` for every locale
  (`en`, `zh`, `ru`, `it`, `ja`, `hi`) — a test fails on missing or fuzzy
  translations. In JavaScript, use `t("…")` and add the key to every
  dictionary in `assets/js/brainagram/locales/`.
- **New command?** Struct in `application/commands/` declaring its handler →
  transition on the aggregate returning `{:ok, aggregate, events}` → event in
  `domain/diagramming/events.ex` → handler → test with the in-memory repository.

## Deployment

Brainagram is a standard Phoenix application. For a release:

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

| Variable | Required | Purpose |
|---|---|---|
| `DATABASE_URL` | yes | `ecto://USER:PASS@HOST/DATABASE` |
| `SECRET_KEY_BASE` | yes | generate with `mix phx.gen.secret` |
| `PHX_HOST` | recommended | public host name (defaults to `example.com`) |
| `PHX_SERVER` | yes (releases) | `true` to start the web server |
| `PORT` | no | defaults to `4000` |
| `POOL_SIZE` | no | database pool, defaults to `10` |
| `ECTO_IPV6` | no | `true` to connect over IPv6 |

Run the migrations before starting a new version (`mix ecto.migrate`, or generate
a release helper with `mix phx.gen.release`).

> **Heads-up:** there are no user accounts yet — every diagram is visible to
> anyone who can reach the instance. Run it on a private network or behind your
> own authentication.

## Contributing

Contributions are very welcome: code, translations, examples, docs and
reviews. Start with the **[contributing guide](CONTRIBUTING.md)**, which covers
the setup, the project rules, the commit convention and how to open a PR. In
short:

1. Run `mix precommit` and make sure it passes.
2. Add tests for behavior changes (the existing suites show the style).
3. Keep the layer rule: the domain never references Ecto, Phoenix or
   infrastructure.

| | |
|---|---|
| [Contributing guide](CONTRIBUTING.md) | setup, rules, translations, commits and PRs |
| [Code of Conduct](CODE_OF_CONDUCT.md) | how we treat each other (Contributor Covenant 2.1) |
| [Security policy](SECURITY.md) | how to report a vulnerability privately |
| [Support](SUPPORT.md) | where to ask questions |
| [Changelog](CHANGELOG.md) | what changed |

New to open source? Look for issues labeled `good first issue`. Reviewing the
translation of a language you speak is a great start too.

Ideas on the roadmap: user accounts, a read-only public page and embeds,
video export, real-time collaboration, payload balloons on architecture arrows.

## License

[MIT](LICENSE) © Lucas Nascimento and Brainagram contributors.
