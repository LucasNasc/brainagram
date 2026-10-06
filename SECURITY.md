# Security Policy

[English](#english) · [Português (Brasil)](#português-brasil)

## English

### Supported versions

Brainagram has no tagged releases yet. Security fixes land on the `main`
branch. Please make sure you can reproduce the problem on the latest `main`.

| Version | Supported |
|---|---|
| `main` (latest) | ✅ |
| anything older | ❌ |

### Reporting a vulnerability

**Please do not open a public issue, discussion or pull request for security
problems.**

Report it privately through GitHub:
**Security** tab → **Report a vulnerability**
([how private reporting works](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)).

Please include:

- what an attacker can do, and the affected component (DSL parser, SVG
  rendering, import/upload, export endpoints…)
- step-by-step instructions to reproduce, ideally a minimal `.brain` file or
  request
- the commit you tested and your environment
- any idea you have for a fix

### What to expect

- An acknowledgment within **7 days**.
- An assessment, and a plan or a request for more details, within **14 days**.
- A fix as fast as severity allows, with a GitHub security advisory published
  once it is out. You'll be credited unless you'd rather stay anonymous.

We ask that you give us reasonable time to fix the issue before disclosing it
publicly, and that you only test against instances you own.

### Scope notes

- **No authentication is a known limitation, not a vulnerability.** There are
  no user accounts yet, and every diagram is visible to anyone who can reach
  the instance (see *Deployment* in the README). Reports about missing access
  control aren't in scope until accounts exist.
- In scope, for example: script injection through diagram text in the editor,
  the rendered or exported SVG, or the GIF/PNG pipeline. Also crafted DSL,
  Mermaid, PlantUML or `.brain`/`.json` files that crash the server or use
  unbounded CPU or memory, and path traversal through import or export.

---

## Português (Brasil)

### Versões com suporte

O Brainagram ainda não tem versões publicadas. As correções de segurança entram
na branch `main`, então confira se o problema acontece na `main` mais recente.

| Versão | Suporte |
|---|---|
| `main` (mais recente) | ✅ |
| qualquer outra | ❌ |

### Como relatar uma vulnerabilidade

**Por favor, não abra issue, discussão ou pull request público sobre falhas de
segurança.**

Relate em particular pelo GitHub:
aba **Security** → **Report a vulnerability**
([como funciona o relato privado](https://docs.github.com/pt/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)).

Inclua, se puder:

- o que um atacante consegue fazer, e o componente afetado (parser da DSL,
  render do SVG, importação/upload, endpoints de exportação…)
- o passo a passo para reproduzir, de preferência com um `.brain` ou uma
  requisição mínima
- o commit testado e o seu ambiente
- qualquer ideia de correção

### O que esperar

- Confirmação de recebimento em até **7 dias**.
- Uma avaliação, com um plano ou um pedido de mais detalhes, em até **14 dias**.
- A correção, tão rápido quanto a gravidade pedir, e um *security advisory* no
  GitHub depois que ela sair. Você recebe o crédito, a menos que prefira ficar
  anônimo.

Pedimos um prazo razoável para corrigir antes de qualquer divulgação pública, e
que os testes sejam feitos só em instâncias suas.

### Observações sobre o escopo

- **Não ter autenticação é uma limitação conhecida, não uma vulnerabilidade.**
  Ainda não existem contas, e todo diagrama fica visível para quem acessa a
  instância (veja *Deploy* no README). Relatos sobre falta de controle de
  acesso ficam fora do escopo até as contas existirem.
- Dentro do escopo, por exemplo: injeção de script pelo texto do diagrama no
  editor, no SVG renderizado ou exportado, ou no GIF/PNG. Também arquivos de
  DSL, Mermaid, PlantUML ou `.brain`/`.json` montados para derrubar o servidor
  ou consumir CPU ou memória sem limite, e *path traversal* pela importação ou
  exportação.
