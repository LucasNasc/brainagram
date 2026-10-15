# Spec 002 — Modo local no navegador e contas opcionais

| | |
|---|---|
| **Status** | Proposta — não implementada |
| **Escopo** | Onde os dados moram (navegador ou conta), cadastro/login simples, isolamento entre contas, segurança básica |
| **Depende de** | `docs/ARQUITETURA.md` (camadas, CQRS, portas), Spec 001 (o texto é a fonte da verdade) |
| **Fase no roadmap** | "Contas de usuário" (README → *Contributing → roadmap*) |

---

## 1. O problema

Hoje todo diagrama vai para um Postgres compartilhado, **sem dono**. Numa
instância pública (ex.: o deploy no Coolify), qualquer pessoa com o endereço
vê, edita e apaga o trabalho de qualquer outra. A única proteção possível é
pôr a instância inteira atrás de uma senha (basic auth do proxy) — o que
transforma "experimentar o Brainagram" num pedido de credencial.

Queremos as duas coisas ao mesmo tempo:

- **Usar sem conta, sem atrito**: abrir, desenhar, voltar amanhã e o diagrama
  estar lá.
- **Ter conta quando fizer sentido**: guardar no servidor, acessar de outro
  computador, compartilhar link público — com os dados de uma pessoa
  invisíveis para as outras.

## 2. Objetivos

1. **Modo local (padrão, sem conta)**: diagramas e projetos ficam salvos no
   **navegador** (IndexedDB). O servidor continua fazendo parse, layout e
   render, mas **não grava nada** de quem não tem conta.
2. **Contas opcionais**: cadastro e login com e-mail e senha; uma tabela de
   usuários e uma de tokens de sessão. Nada além do necessário.
3. **Isolamento**: com conta, cada diagrama e projeto tem dono; ninguém lê nem
   altera o que não é seu — nem por URL adivinhada, nem por evento de PubSub.
4. **Levar o local para a conta**: ao entrar, oferecer importar os diagramas
   locais para a conta, com um clique.
5. **Segurança básica bem feita** (§8): senhas com hash forte, sessão segura,
   proteção contra enumeração, força bruta, CSRF, XSS, clickjacking e
   vazamento entre contas.

### Não-objetivos (agora)

- Login social (GitHub/Google), SSO, 2FA/passkeys. A modelagem não pode
  impedir (§13), mas não entram nesta spec.
- Times, papéis, edição compartilhada em tempo real.
- Envio de e-mail obrigatório. Confirmação de e-mail e recuperação de senha
  por e-mail ficam opcionais (só se houver SMTP configurado — §6.5).
- Sincronização automática local ↔ conta. A passagem é explícita (importar).
- Painel de administração. A administração mínima é por linha de comando
  (§6.6).

## 3. Decisão central: dois lugares para os dados, escolhidos pela pessoa

| | **Local** (sem conta) | **Conta** |
|---|---|---|
| Onde fica | IndexedDB do navegador | Postgres do servidor |
| Quem vê | só aquele navegador | o dono (+ link público, se o dono quiser) |
| Sobrevive a | fechar a aba, reiniciar | trocar de computador |
| Perde quando | limpar dados do site, aba anônima, trocar de navegador | a pessoa apaga a conta |
| Servidor grava algo? | **não** | sim |
| Link público `/d/:slug` | não (exige conta) | sim |

O servidor continua sendo o "cérebro" (parser, layout, roteador, SVG) nos dois
modos — o que muda é **quem persiste**. No modo local, quem guarda é o
navegador; o LiveView recebe o texto do cliente, calcula a cena e devolve o
texto validado para o cliente gravar.

### Alternativas consideradas

- **Conta anônima automática (cookie → linha no banco).** Rejeitada: o banco
  enche de lixo de quem só experimentou, vira alvo de abuso (armazenamento
  grátis), e "os dados são de quem?" fica ambíguo quando o cookie some.
- **`localStorage` em vez de IndexedDB.** Rejeitado: limite de ~5 MB por
  origem, API síncrona (trava a aba com muitos diagramas), só strings.
  IndexedDB tem cota muito maior, é assíncrono e transacional.
- **`mix phx.gen.auth` como está.** Usado como **referência** de fluxo e de
  boas práticas (tokens hasheados, renovação de sessão, desconexão do
  LiveView no logout), mas não colado: ele gera um contexto que fala com o
  `Repo` direto, o que fere a regra das camadas
  (`test/brainagram/architecture_test.exs`). O código vai para as camadas
  certas (§7).

## 4. Modo local

### 4.1 Armazenamento no navegador

Banco IndexedDB `brainagram`, versão 1, com três *object stores*:

```text
diagrams  { id, title, kind, source, project_id, visibility, created_at, updated_at, schema }
projects  { id, name, color, created_at, updated_at, schema }
meta      { key, value }        # ex.: "schema_version", "last_backup_at"
```

- `id`: `crypto.randomUUID()` — gerado no cliente, nunca reaproveitado.
- `schema`: versão do registro, para migrações futuras no próprio navegador
  (`onupgradeneeded`).
- O formato dos campos é o mesmo do **bundle JSON** que a exportação já usa
  (`Brainagram.Application.Bundle`), então backup, restauração e
  "levar para a conta" reaproveitam o mesmo formato e o mesmo validador.

Módulo novo `assets/js/brainagram/local_store.js` (sem dependência externa):
`list()`, `get(id)`, `put(record)`, `remove(id)`, `exportBundle()`,
`importBundle(json)`, `clear()`. Toda escrita numa transação; erros de cota
(`QuotaExceededError`) viram aviso na interface, nunca perda silenciosa.

Ao gravar o primeiro diagrama, pedir `navigator.storage.persist()` — reduz a
chance de o navegador apagar os dados sob pressão de espaço.

### 4.2 Fluxo com o LiveView

O LiveView não acessa o IndexedDB; um hook (`LocalStore`) faz a ponte:

1. **Painel (`/`)**: o hook lê `list()` e envia `local:list` com os metadados
   (título, tipo, projeto, datas — **sem** o fonte). O painel renderiza a
   lista igual à de hoje.
2. **Editor local (`/l/:id`)**: o hook lê o registro e envia `local:loaded`
   com o fonte. O LiveView valida (`Source.new/1`, limite de
   `Source.max_bytes/0`) e calcula a cena.
3. **Salvar**: o LiveView valida o texto pelo domínio e responde
   `push_event("local:put", %{id, source, title, ...})`; o hook grava. O
   servidor **não** guarda cópia.
4. **Várias abas**: `BroadcastChannel("brainagram")` avisa as outras abas de
   cada escrita; a aba que estiver com o mesmo diagrama aberto recarrega ou
   mostra "alterado em outra aba".

Rotas: `/l/:id` (local), `/d/:slug` (conta ou público), `/new` cria no modo
atual (local sem login, conta com login).

O que o modo local **não** tem: link público, `preview.svg` e
`/d/:slug/download` no servidor (a exportação SVG/PNG/GIF/.brain já é feita no
navegador e continua funcionando).

### 4.3 Avisos honestos

- Banner discreto até o primeiro backup: "Seus diagramas ficam só neste
  navegador. **Exportar backup** · **Criar conta**".
- Em *Configurações*: uso de espaço (`navigator.storage.estimate()`),
  **Exportar tudo**, **Importar backup**, **Apagar dados locais** (com
  confirmação).

## 5. Contas: modelo de dados

### 5.1 Tabelas novas

```text
users
  id               bigserial  PK
  email            citext     NOT NULL UNIQUE      -- comparação sem diferenciar maiúsculas
  hashed_password  text       NOT NULL
  confirmed_at     timestamptz NULL                -- só usado se houver SMTP (§6.5)
  inserted_at, updated_at

users_tokens
  id               bigserial  PK
  user_id          bigint     NOT NULL REFERENCES users ON DELETE CASCADE
  token_hash       bytea      NOT NULL             -- SHA-256 do token; o token em si nunca é gravado
  context          text       NOT NULL             -- "session" | "reset_password" | "confirm"
  authenticated_at timestamptz NULL                -- última vez que a senha foi digitada (modo sudo, §8.3)
  inserted_at
  UNIQUE (context, token_hash)
  INDEX (user_id)
```

Migração habilita `citext` (`execute "CREATE EXTENSION IF NOT EXISTS citext"`).

### 5.2 Dono dos dados existentes

```text
diagrams.owner_id  bigint NULL REFERENCES users ON DELETE CASCADE   + INDEX (owner_id, updated_at)
projects.owner_id  bigint NULL REFERENCES users ON DELETE CASCADE   + INDEX (owner_id)
```

- `owner_id` **nunca** entra em `cast` (campos definidos pelo sistema não vêm do formulário): é definido pelo
  handler a partir do escopo autenticado.
- A importação que hoje "reaproveita projeto com o mesmo nome" passa a
  procurar só entre os projetos **do mesmo dono**.
- Slugs continuam aleatórios e globais (base32, `Slug.generate/0`), mas
  **não** são credencial: acesso é decidido pelo dono/visibilidade (§7.2), não
  por o slug ser difícil de adivinhar.

### 5.3 Dados que já estão no banco (legado)

Linhas com `owner_id IS NULL` são o que existe hoje.

- Continuam **legíveis** em `/d/:slug` se forem públicas; **ninguém edita**.
- Privadas sem dono ficam invisíveis.
- O administrador assume o legado pela linha de comando:
  `bin/brainagram eval 'Brainagram.Release.claim_legacy("voce@exemplo.com")'`
  (atribui todas as linhas sem dono àquela conta, numa transação, e imprime a
  contagem).

## 6. Fluxos

### 6.1 Cadastro

- Campos: e-mail e senha (com "mostrar senha"). Sem confirmação de senha
  repetida — o botão de mostrar resolve o erro de digitação.
- Política de cadastro por variável de ambiente `BRAINAGRAM_SIGNUP`:
  - `open` — qualquer pessoa cria conta;
  - `closed` (**padrão**) — só a linha de comando cria contas (§6.6),
    **exceto** quando não existe nenhum usuário: o primeiro cadastro é
    permitido (é quem instalou).
- Cadastro bem-sucedido já autentica (cria sessão, §6.2).

### 6.2 Login

- `POST /users/log-in` num **controller** (não LiveView), porque precisa
  gravar o cookie de sessão. O formulário pode ser LiveView com
  `phx-trigger-action`, como no `phx.gen.auth`.
- Sucesso: `renew_session` (limpa a sessão antiga e troca o id — evita
  *session fixation*), gera token, grava `user_token` na sessão, redireciona
  para onde a pessoa estava.
- Falha: mensagem única "E-mail ou senha inválidos" (§8.2).
- "Manter conectado": cookie de sessão persiste por até 30 dias; sem marcar,
  expira ao fechar o navegador. Validade **absoluta** no servidor: 30 dias
  desde `inserted_at` do token, independentemente do cookie.

### 6.3 Após entrar com dados locais

Se o IndexedDB tiver diagramas, mostrar uma vez: "Você tem **12 diagramas
neste navegador**. Trazer para a sua conta?" → **Trazer** / **Agora não**.

- O hook gera o bundle (`exportBundle()`) e envia ao servidor; o servidor usa
  o comando existente `ImportDiagrams` **com o escopo do usuário** (mesmas
  validações e limites da importação de arquivos).
- Só depois da confirmação do servidor o cliente oferece **apagar a cópia
  local** (padrão: manter; marcar `meta.imported_to = user_id`).

### 6.4 Sair, trocar senha, apagar conta

- **Sair**: apaga o token no banco, limpa a sessão e transmite
  `disconnect` para os LiveViews daquela sessão (tópico
  `users_sessions:<hash do token>`), como no `phx.gen.auth`.
- **Trocar senha / e-mail / apagar conta**: exigem **modo sudo** (§8.3). Trocar
  a senha **revoga todas as outras sessões**.
- **Apagar conta**: oferece antes **Exportar tudo** (bundle); depois apaga o
  usuário — `ON DELETE CASCADE` leva tokens, diagramas e projetos. Exclusão
  real, não lógica (LGPD: dado que não precisamos não fica).

### 6.5 Recuperar senha e confirmar e-mail (só com SMTP)

Sem SMTP configurado (`BRAINAGRAM_SMTP_*` ausentes), essas telas **não
existem** — e a instância não envia e-mail nenhum. Com SMTP:

- "Esqueci a senha" responde **sempre** "Se houver uma conta com esse e-mail,
  enviamos um link" (§8.2). Token de uso único, válido por 1 hora, gravado
  como hash, apagado ao usar.
- Confirmação de e-mail fica fora do caminho crítico: conta não confirmada
  funciona; a confirmação só é exigida para recuperar senha.

### 6.6 Administração pela linha de comando (release)

Funções em `Brainagram.Release`, chamadas com `bin/brainagram eval` (no
Coolify: *Terminal* do container):

| Comando | Efeito |
|---|---|
| `create_user("email")` | cria a conta e imprime **um link de definição de senha** de uso único, válido por 1 h — nunca uma senha em texto no histórico do shell |
| `reset_password_link("email")` | mesmo link, para recuperar acesso sem SMTP |
| `claim_legacy("email")` | §5.3 |
| `delete_user("email")` | apaga a conta e os dados |

## 7. Onde isso entra na arquitetura

Mesma regra de sempre: `web → application → domain → shared`; infraestrutura
implementa portas e é ligada em `config/config.exs`.

```text
domain/accounts/
  user.ex                 agregado: e-mail, hash, transições (register, change_password…)
  value_objects/email.ex  normaliza (trim, minúsculas p/ comparação) e valida formato/tamanho
  password_policy.ex      regras puras de senha (§8.1) — sem hash aqui
  ports/user_repository.ex, ports/token_repository.ex, ports/password_hasher.ex
application/
  scope.ex                %Scope{user: User.t() | nil, storage: :local | :account}
  commands/  register_user, log_in, log_out, change_password, delete_account, import_local_bundle
  queries/   user_by_session_token
infrastructure/
  accounts/ecto_user_repository.ex, ecto_token_repository.ex
  accounts/pbkdf2_password_hasher.ex
  security/rate_limiter.ex  (ETS, §8.4)
web/
  user_auth.ex            plug fetch_current_scope + on_mount (:mount_current_scope, :require_user)
  controllers/user_session_controller.ex
  live/user_registration_live.ex, user_log_in_live.ex, user_settings_live.ex
```

### 7.1 Escopo em tudo

Todo comando e query de diagrama/projeto passa a receber `scope`:

- `Bus.dispatch(command, scope)` / `Bus.ask(query, scope)`.
- `scope.storage == :local` → comandos de persistência de diagrama **não**
  tocam o repositório (o LiveView devolve `local:put` ao cliente).
- `scope.storage == :account` → os repositórios **sempre** filtram por
  `owner_id = scope.user.id`; não existe função de repositório "sem dono"
  usada pela web (só `claim_legacy`, no release).
- `<Layouts.app flash={@flash} current_scope={@current_scope}>` em todas as
  telas.

### 7.2 Regras de acesso

| Recurso | Dono | Outra conta | Sem login |
|---|---|---|---|
| `/d/:slug` público | edita | **lê** | **lê** |
| `/d/:slug` privado | edita | 404 | 404 |
| `preview.svg`, `/download` | sim | só se público | só se público |
| `/export` (bundle) | só os próprios dados | — | — |
| `/l/:id` | — | — | só o próprio navegador |

Recurso de outra pessoa responde **404, não 403** — não confirmar que o slug
existe.

### 7.3 Eventos

O `PubSubEventBus` hoje publica mudanças de diagrama num tópico global. Passa a
publicar em `owner:<user_id>` (painel e editor do dono) e, para diagramas
públicos, em `diagram:<slug>` apenas com o necessário para leitores
recarregarem. Nenhum evento carrega o fonte de um diagrama privado para um
tópico que outra pessoa possa assinar.

## 8. Segurança

Princípio: o básico, completo e testado — não um sistema de segurança
sofisticado pela metade.

### 8.1 Senhas

- **Hash**: PBKDF2-HMAC-SHA512 com **220 000 iterações** e sal aleatório por
  senha (recomendação atual da OWASP), via `pbkdf2_elixir` — Elixir puro sobre
  `:crypto`, sem NIF: compila igual no Windows, no CI e na imagem Docker. A
  porta `PasswordHasher` permite trocar por Argon2id depois, com
  re-hash transparente no próximo login.
- **Política** (OWASP/NIST, sem segundo fator): mínimo **15** caracteres,
  máximo **128**; **sem regras de composição** (nada de "uma maiúscula e um
  símbolo"); qualquer caractere, inclusive espaço e unicode (normalizado em
  NFC antes do hash). Rejeitar senha igual ao e-mail.
- Nunca logar, devolver ou guardar a senha em claro: `filter_parameters` com
  `password`, `current_password`, `token`; o campo de senha nunca é
  re-renderizado com valor.

### 8.2 Enumeração de contas

- Login: sempre "E-mail ou senha inválidos". Para e-mail inexistente, rodar
  `Pbkdf2.no_user_verify/0` — mesmo tempo de resposta de uma senha errada.
- Recuperação de senha: resposta idêntica exista ou não a conta (§6.5).
- Cadastro com e-mail já usado: com SMTP, responder como sucesso e mandar um
  e-mail avisando o dono; **sem SMTP**, a mensagem "não foi possível criar a
  conta" é inevitavelmente reveladora — risco aceito, mitigado pela política
  `closed` padrão e pelo limite de tentativas (§8.4).

### 8.3 Sessão e cookies

- Token de sessão: 32 bytes de `:crypto.strong_rand_bytes/1`. No banco, só o
  **SHA-256** do token — um vazamento do banco não dá sessões válidas.
- Cookie de sessão: `HttpOnly`, `Secure` em produção, `SameSite=Lax`,
  **assinado e cifrado** (acrescentar `encryption_salt` em
  `@session_options` do endpoint).
- `renew_session` no login e no logout (*session fixation*).
- Validade absoluta de 30 dias (§6.2); tokens vencidos apagados por limpeza
  periódica (tarefa no próprio app, sem dependência).
- **Modo sudo**: trocar senha/e-mail e apagar conta exigem
  `authenticated_at` nos últimos 10 minutos; senão, pedir a senha de novo.
- Trocar senha revoga as demais sessões; "Sair de todos os dispositivos" em
  *Configurações*.

### 8.4 Força bruta e abuso

- **Por conta**: 5 falhas em 15 min → espera crescente (1, 2, 4… até 15 min)
  antes de aceitar nova tentativa para aquele e-mail. Bloqueio temporário,
  nunca permanente (não dá para trancar a conta de alguém de propósito).
- **Por IP**: 30 tentativas de login/cadastro por minuto.
- Implementação: `Infrastructure.Security.RateLimiter` com ETS e janela
  deslizante (sem dependência nova); em memória — reinício zera, aceitável
  para instância única.
- IP real atrás do Caddy/Coolify: `Plug.RewriteOn` com `:x_forwarded_for` e
  `:x_forwarded_proto`, **ligado só com `TRUST_PROXY=true`** — exposto direto,
  o cabeçalho seria forjável.
- **Cotas por conta**: até 1 000 diagramas e 200 projetos (configurável);
  limites existentes continuam (200 KB por fonte, 2 MB por arquivo, 50
  arquivos por importação).

### 8.5 Navegador: XSS, CSRF, clickjacking, transporte

O modo local torna **XSS o risco nº 1**: qualquer script que rode na origem lê
o IndexedDB inteiro.

- Nenhum `raw/1` com conteúdo de usuário; rótulos e títulos sempre escapados
  no HEEx e no `Render.Svg`; o SVG exportado/importado nunca é inserido como
  HTML. Teste de propriedade: rótulos com `<script>`, `"><img onerror=…>`,
  `javascript:` saem escapados no SVG do servidor e do cliente.
- **CSP** via `put_secure_browser_headers`:
  `default-src 'self'; script-src 'self' 'sha256-<script de tema>'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self' wss://<host>; font-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'`.
  O script inline de tema em `root.html.heex` entra pelo hash (calculado em
  tempo de compilação), não por `'unsafe-inline'`.
- CSRF: `protect_from_forgery` já existe; login/logout por POST com token; o
  socket do LiveView já valida o token e o `check_origin` (por isso `PHX_HOST`
  precisa ser o domínio real).
- Clickjacking: `frame-ancestors 'none'` + `x-frame-options: DENY`.
- Transporte: `force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]` em
  produção (o HTTPS termina no Caddy).
- `referrer-policy: strict-origin-when-cross-origin`;
  `permissions-policy` desligando o que não usamos (câmera, microfone,
  geolocalização).

### 8.6 Dados e privacidade

- Guardamos só: e-mail, hash da senha, datas, e os diagramas da pessoa.
  Nenhum IP é persistido (o limitador é em memória).
- Logs identificam por `user_id`, nunca por e-mail.
- Conta local não vaza para conta: dados da conta **não** são cacheados no
  IndexedDB; sair não apaga os dados locais anônimos (são do navegador, não
  da conta), e a tela de saída lembra disso em computador compartilhado.
- Exportar tudo e apagar conta disponíveis para a própria pessoa (LGPD).

### 8.7 Cadeia de dependências

- Uma dependência nova só: `pbkdf2_elixir`.
- CI ganha `mix hex.audit` (pacotes retirados) e o Dependabot já existente
  cobre as atualizações.

### 8.8 Modelo de ameaças (resumo)

| Ameaça | Mitigação |
|---|---|
| Ler/alterar diagrama alheio (IDOR) | escopo obrigatório em todo repositório; 404; testes cruzados (§10) |
| Vazamento por PubSub | tópicos por dono (§7.3) |
| Banco vazado | senhas PBKDF2; tokens só como hash |
| Roubo de cookie | HttpOnly, Secure, SameSite, cifrado; validade absoluta; sair revoga |
| Senha fraca / força bruta | política §8.1; limitador §8.4 |
| Enumeração de e-mails | mensagens genéricas, tempo constante §8.2 |
| XSS → leitura do IndexedDB | escapes + CSP §8.5 |
| CSRF / clickjacking | token CSRF, `check_origin`, `frame-ancestors` |
| IP forjado no limitador | `RewriteOn` só com `TRUST_PROXY` |
| Abuso de armazenamento | cadastro `closed` por padrão; cotas |

## 9. Interface (resumo)

- Topo: no modo local, selo **"Neste navegador"** + botão **Entrar**; com
  conta, menu com o e-mail (Configurações, Sair).
- Telas: Entrar, Criar conta (se a política permitir), Configurações (e-mail,
  senha, sessões, exportar, apagar conta), Dados locais.
- Todos os textos pelos 7 idiomas (`gettext` + `locales/*.js`), como o resto
  do app; mensagens de erro de autenticação via `ErrorMessages`.

## 10. Testes

- **Domínio**: `Email` e `PasswordPolicy` (tamanhos, unicode, NFC, igual ao
  e-mail) com StreamData.
- **Aplicação**: cada comando com repositórios em memória; `scope` ausente ou
  de outra conta → erro.
- **Isolamento (obrigatório)**: para **todo** comando e query de diagrama e
  projeto, o usuário B não lê nem altera nada do usuário A (gerar a lista a
  partir do registro de comandos do `Bus`, para que comando novo sem teste de
  isolamento quebre a suíte).
- **Web**: login com sucesso/falha (mesma mensagem), renovação do id de
  sessão, logout desconecta o LiveView, rotas exigem login, 404 para recurso
  alheio, cabeçalhos de segurança presentes (CSP, HSTS em prod,
  `frame-ancestors`).
- **Limitador**: janela, espera crescente, isolamento por e-mail e por IP.
- **Modo local**: testes de LiveView do protocolo `local:list` / `local:loaded`
  / `local:put` (o servidor não chama o repositório); teste JS do
  `local_store.js` com um IndexedDB em memória (ou verificação no navegador
  real com o script de `docs/tools/`).
- **Arquitetura**: `architecture_test.exs` cobre `domain/accounts` (sem Ecto,
  sem hash, sem Phoenix).

## 11. Entrega em fases

### Fase A — Modo local *(o "sem conta" de verdade)*
IndexedDB, hook `LocalStore`, rotas `/l/:id`, painel lendo do navegador,
backup/restauração, avisos. A partir daqui o servidor não grava nada de
quem não tem conta; o que já está no banco vira legado somente leitura (§5.3).

### Fase B — Contas
Tabelas, `PasswordHasher`, cadastro (política `BRAINAGRAM_SIGNUP`), login,
logout, `Scope`, `UserAuth`, comandos de release (`create_user`,
`reset_password_link`).

### Fase C — Dono e isolamento
`owner_id`, escopo em todos os comandos/queries, regras de acesso (§7.2),
tópicos por dono, `claim_legacy`, importar dados locais para a conta.

### Fase D — Endurecimento
CSP, cabeçalhos, `force_ssl`, limitador, modo sudo, revogação de sessões,
cotas, `mix hex.audit` no CI.

### Fase E — E-mail (opcional)
SMTP, recuperação de senha e confirmação de e-mail.

As fases B–D só vão ao ar juntas numa instância pública: contas sem
isolamento (B sem C) seriam piores que nenhuma conta.

## 12. Riscos

- **Perda de dados locais** (limpeza do navegador, aba anônima): mitigado por
  `storage.persist()`, avisos e backup a um clique — mas é a natureza do modo.
- **Complexidade dupla no LiveView** (dois caminhos de persistência): manter
  a escolha num único ponto (`scope.storage`) e os handlers ignorando de onde
  o texto veio.
- **XSS passa a custar mais caro** (expõe todos os diagramas locais): por isso
  a CSP entra antes de abrir cadastro numa instância pública.
- **Esquecer o escopo num comando novo**: o teste de isolamento gerado a
  partir do registro do `Bus` (§10) existe para isso.

## 13. Questões em aberto

1. Diagrama **local** com link público: exigir conta (proposta) ou permitir
   "publicar" criando uma cópia no servidor sem dono, só leitura?
2. Valor padrão de `BRAINAGRAM_SIGNUP` para quem só quer uso pessoal: `closed`
   (proposta) ou `open`?
3. Entrar com GitHub (OAuth) depois: a tabela `users` aceita uma tabela
   `user_identities` sem mudar o resto — confirmar antes da Fase B.
4. Cotas por conta: os números de §8.4 são palpite; medir após o primeiro mês.

## Referências

- OWASP — [Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- OWASP — [Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
- OWASP — [Session Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)
- Phoenix — [`mix phx.gen.auth`](https://hexdocs.pm/phoenix/mix_phx_gen_auth.html) (referência de fluxo)
- MDN — [IndexedDB API](https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API), [`StorageManager.persist()`](https://developer.mozilla.org/en-US/docs/Web/API/StorageManager/persist)
