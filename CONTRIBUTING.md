<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.svg">
    <img src="docs/images/logo-light.svg" alt="Brainagram" width="220">
  </picture>
</p>

# Contributing to Brainagram

**English** · [Português (Brasil)](CONTRIBUTING.pt-BR.md)

Thanks for taking the time to help! Brainagram is a small project, so every
issue, translation, review and pull request makes a real difference. This guide
explains how to get set up and what a contribution needs in order to be merged
quickly.

By taking part you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Table of contents

- [Ways to contribute](#ways-to-contribute)
- [Asking questions](#asking-questions)
- [Reporting bugs](#reporting-bugs)
- [Suggesting features](#suggesting-features)
- [Your first code contribution](#your-first-code-contribution)
- [Development setup](#development-setup)
- [Where things live](#where-things-live)
- [Project rules](#project-rules)
- [Translations](#translations)
- [Commit messages](#commit-messages)
- [Pull requests](#pull-requests)
- [Security issues](#security-issues)
- [AI-assisted contributions](#ai-assisted-contributions)

## Ways to contribute

You don't have to write Elixir to help:

- **Report a bug** or a diagram that renders badly (the `.brain` source is the
  perfect reproduction).
- **Improve a translation.** The UI speaks seven languages, and the non-English
  ones were bootstrapped by machine translation, so native speakers are very
  welcome to review them.
- **Share examples**: diagrams of real-world flows make great test cases and
  catalog entries.
- **Improve the docs** (the READMEs, this guide, `docs/`).
- **Review pull requests** and try them out locally.
- **Write code**: fixes, layout improvements, importers, new DSL features.

## Asking questions

Please don't use issues for questions. See [SUPPORT.md](SUPPORT.md) for where
to ask.

## Reporting bugs

1. Check that you're on the latest `main` and search the
   [existing issues](../../issues?q=is%3Aissue) first, including closed ones.
2. Open a new issue with the **Bug report** template and fill in every field.
   The most useful thing you can attach is the **smallest DSL source that
   reproduces the problem**. Use *Export → .brain file* in the editor, or
   paste the text.
3. Add screenshots, the browser and OS you used, and any error from the browser
   console or the server log.

Never report security vulnerabilities in a public issue. See
[Security issues](#security-issues).

## Suggesting features

Open an issue with the **Feature request** template. Describe the *problem*
before the solution. "I can't show that a call is retried" is easier to
discuss than "add a `retry` keyword". For larger changes, such as a new
diagram type, a DSL change or a new dependency, **please wait for a
maintainer's go-ahead before writing the code**, so no work is wasted.

## Your first code contribution

Look for issues labeled
[`good first issue`](../../labels/good%20first%20issue) or
[`help wanted`](../../labels/help%20wanted). Comment on the issue to say you're
working on it, so two people don't do the same work. If you get stuck, ask in
the issue. Unfinished pull requests are welcome too; open them as **drafts**.

## Development setup

**Requirements:** Elixir 1.15+ and Erlang/OTP 25+ (CI runs Elixir 1.18 / OTP 27 and 1.20 / OTP 29, the production image),
and PostgreSQL (CI uses 16).

```bash
# fork https://github.com/LucasNasc/brainagram on GitHub first, then:
git clone https://github.com/<your-user>/brainagram.git
cd brainagram
git remote add upstream https://github.com/LucasNasc/brainagram.git

# Postgres for development (skip if you already have one on localhost:5432)
docker run -d --name brainagram-pg -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:16

mix setup          # deps, database, migrations, example diagrams, assets
mix phx.server     # http://localhost:4000
```

Day to day:

```bash
mix test                          # the whole suite (most of it doesn't touch the database)
mix test test/path/to_test.exs    # one file
mix test --failed                 # only what failed last time
mix precommit                     # what CI checks: warnings as errors, unused deps, format, tests
```

After changing CSS or JS without the dev server running, `mix assets.build`
rebuilds the bundles.

## Where things live

```
lib/brainagram/
├── shared/                 no business rules
├── domain/diagramming/     pure rules: DSL parser/printer, layout, routing, rendering
├── application/            commands, queries and their handlers (CQRS)
└── infrastructure/         Ecto repositories/readers, PubSub, example catalog
lib/brainagram_web/         LiveViews, controllers, components, locale
assets/css/                 hand-written CSS with design tokens
assets/js/                  canvas, timeline, hooks, i18n dictionaries
priv/gettext/               translations
test/                       mirrors lib/; test/support has in-memory adapters
```

The full picture is in the README section
[How it works](README.md#how-it-works) and in
[`docs/ARQUITETURA.md`](docs/ARQUITETURA.md).

Common recipes:

- **New command or query**: struct in `application/commands/` (or `queries/`)
  declaring its handler → transition on the aggregate returning
  `{:ok, aggregate, events}` → event in `domain/diagramming/events.ex` → handler
  → test using the in-memory repository.
- **New DSL syntax**: parser in `domain/diagramming/dsl/`, the matching printer
  (sources must round-trip), a parser test, and the README *DSL* section.
- **Layout change**: add a case to the layout tests. The quality tests
  (`layout/quality_test.exs`) count crossings and overlaps, so make sure the
  numbers don't get worse.
- **Visual change?** Regenerate the README demo GIFs (dark mode, recorded by
  the app's own GIF exporter) with the server running:
  `node docs/tools/record_gifs.mjs` (`PORT=` and `BROWSER=` if needed; Node 22+
  and Chrome or Edge).

## Project rules

These are checked in review, and most of them by tests as well. The complete
list for humans and coding agents is in [`AGENTS.md`](AGENTS.md).

- **Layer rule.** The domain never references Ecto, Phoenix or
  `Brainagram.Infrastructure`. New infrastructure goes behind a port and is
  wired in `config/config.exs`. `test/brainagram/architecture_test.exs`
  enforces this.
- **Text is the source of truth.** Canvas gestures become surgical edits to the
  DSL text. Don't keep diagram state that can't be written back as text.
- **Plain CSS, no frameworks.** Use the tokens in `assets/css/tokens.css` and
  never hard-code colors. Components are BEM with the `ba-` prefix, and state
  goes in attributes (`aria-pressed`, `data-state`). Canvas rules in
  `diagram.css` start with `.bg-`.
- **No new dependencies** without discussing it in an issue first.
- **Tests for behavior changes.** Domain logic gets unit or property tests
  (StreamData). UI gets LiveView tests that use the element IDs from the
  templates.
- **The docs are tested too.** `test/brainagram/project_docs_test.exs` checks
  that the README badges (version, test count, languages, Elixir/Phoenix
  versions) match the code, and that links between the docs work. If it fails
  after you added tests or bumped a version, update the badge in both READMEs.

## Translations

Brainagram speaks Brazilian Portuguese (the default, and the source language),
English, Simplified Chinese, Russian, Italian, Japanese and Hindi.

- **Elixir/HEEx**: every user-facing string goes through
  `gettext("Texto em português")`. The Portuguese text *is* the message id.
- After adding or changing strings, run `mix gettext.extract --merge`, then fill
  the empty `msgstr` in `priv/gettext/<locale>/LC_MESSAGES/default.po` for
  **every** locale. Plural forms differ: Chinese and Japanese have one form,
  and Russian has three. `test/brainagram_web/locale_test.exs` fails on any
  missing or `fuzzy` entry.
- **JavaScript**: `t("Texto em português", {vars})`, adding the key to every
  dictionary in `assets/js/brainagram/locales/`.
- Don't speak Portuguese? Write the string in English in your PR and say so.
  A maintainer will help with the Portuguese msgid.
- **Reviewing a language** is a great first contribution. Open an issue with
  the **Translation** template, or send a PR that edits only the `.po` and
  `locales/*.js` files of that language.

To add a new language, see the checklist in [`AGENTS.md`](AGENTS.md#internationalization-pt-br-en-zh-ru-it-ja-hi).

## Commit messages

We follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>(<optional scope>): <short summary in the imperative>

<optional body: what and why, not how>
```

Common types: `feat`, `fix`, `docs`, `i18n`, `refactor`, `perf`, `test`,
`build`, `ci`, `chore`. Mark breaking changes with `!`
(`feat(dsl)!: rename the payload keyword`). Example:

```
fix(layout): keep return arrows inside the activation bar
```

## Pull requests

1. Fork the repository and create a branch from `main`
   (`fix/payload-overflow`, `feat/plantuml-notes`…).
2. Keep the PR focused: one fix or one feature. Unrelated cleanups go in their
   own PR.
3. Run **`mix precommit`** and make sure it passes.
4. Update the docs and [`CHANGELOG.md`](CHANGELOG.md) (under *Unreleased*) when
   behavior changes.
5. Open the PR and fill in the template. For visual changes, include
   before/after screenshots or a GIF (the editor can export one).
6. CI must be green. A maintainer will review, usually within a week. Feel free
   to ping the PR if it has been quiet longer than that.

Changes are merged with *squash and merge*, so the PR title becomes the commit
message. Please write it in the Conventional Commits format.

By submitting a contribution you agree that it is licensed under the project's
[MIT License](LICENSE).

## Security issues

Please **don't** open a public issue. Follow [SECURITY.md](SECURITY.md).

## AI-assisted contributions

Using AI tools is fine. [`AGENTS.md`](AGENTS.md) exists so that coding agents
follow the project's conventions. You are still the author: read and understand
every line you submit, make sure the tests are meaningful, and be ready to
explain your changes in review.

---

Thank you for contributing! 💜
