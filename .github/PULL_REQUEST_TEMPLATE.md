<!--
Thanks for contributing! · Obrigado por contribuir!
The PR title becomes the commit message (squash merge), so use Conventional Commits,
e.g. `fix(layout): keep return arrows inside the activation bar`.
O título do PR vira a mensagem do commit, então use Conventional Commits.
-->

## What and why · O quê e por quê

<!-- What does this change, and why is it needed? · O que muda e por que é preciso? -->

Closes #

## How to test · Como testar

<!-- Steps for the reviewer, ideally with a `.brain` source. · Passos para a revisão, de preferência com um fonte `.brain`. -->

1.

## Screenshots · Capturas

<!-- Before/after for visual changes (the editor can export a GIF). Delete this section if it doesn't apply. · Antes/depois para mudanças visuais. Apague a seção se não se aplica. -->

## Checklist

- [ ] `mix precommit` passes · `mix precommit` passa
- [ ] Tests added or updated for behavior changes · Testes criados ou atualizados para mudanças de comportamento
- [ ] Layer rule respected: the domain doesn't reference Ecto, Phoenix or infrastructure · Regra das camadas respeitada
- [ ] New UI text goes through `gettext`/`t()` and is translated in **all** locales · Textos novos traduzidos em **todos** os idiomas
- [ ] CSS uses design tokens only (no hard-coded colors, no frameworks) · CSS só com tokens
- [ ] Docs and `CHANGELOG.md` (*Unreleased*) updated if behavior changed · Docs e `CHANGELOG.md` atualizados se o comportamento mudou
- [ ] No new dependency, or it was discussed in an issue first · Sem dependência nova, ou ela foi discutida antes numa issue
