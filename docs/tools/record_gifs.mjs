// Grava os GIFs de demonstração do README.
//
// Abre o editor no tema escuro num Chrome/Edge sem janela, carrega cada
// exemplo de docs/examples e aciona Exportar → GIF — o mesmo exportador que a
// pessoa usa no app, então o GIF sai igual ao da tela. Precisa de Node 22+ e do
// servidor rodando (`mix phx.server`).
//
//   node docs/tools/record_gifs.mjs            # usa a porta 4000
//   PORT=4001 BROWSER=/caminho/do/chrome node docs/tools/record_gifs.mjs
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const port = process.env.PORT || "4000";
const outDir = path.join(root, "docs/images");
const EXAMPLES = ["checkout.en", "checkout.pt-BR", "platform.en", "platform.pt-BR"];

const BROWSERS = {
  win32: [
    "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
    "C:/Program Files/Google/Chrome/Application/chrome.exe",
  ],
  darwin: [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  ],
  linux: ["/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/microsoft-edge"],
};
const executable = process.env.BROWSER || (BROWSERS[process.platform] || BROWSERS.linux).find((p) => fs.existsSync(p));
if (!executable) throw new Error("Chrome/Edge não encontrado: defina BROWSER=/caminho/do/navegador");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Perfil e downloads numa pasta temporária própria, apagada no fim.
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "brainagram-gifs-"));
const profile = path.join(scratch, "profile");
const downloads = path.join(scratch, "downloads");
fs.mkdirSync(downloads, { recursive: true });

// Porta 0: o navegador escolhe uma livre e a anota em DevToolsActivePort —
// duas execuções seguidas nunca falam com o navegador errado.
const browserProcess = spawn(
  executable,
  [
    "--headless=new",
    "--remote-debugging-port=0",
    `--user-data-dir=${profile}`,
    "--window-size=1600,1000",
    "--no-first-run",
    "--disable-gpu",
    "about:blank",
  ],
  { stdio: "ignore" },
);
let exited = false;
browserProcess.once("exit", () => (exited = true));

async function devtoolsEndpoint() {
  const file = path.join(profile, "DevToolsActivePort");
  for (let i = 0; i < 100; i++) {
    if (fs.existsSync(file)) {
      const [debugPort, wsPath] = fs.readFileSync(file, "utf8").trim().split("\n");
      if (debugPort && wsPath) return { debugPort, wsPath };
    }
    await sleep(100);
  }
  throw new Error("o navegador não abriu a porta de depuração");
}

function client(wsUrl) {
  const ws = new WebSocket(wsUrl);
  let id = 0;
  const pending = new Map();
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result);
    }
  };
  const ready = new Promise((r) => (ws.onopen = r));
  const send = async (method, params = {}) => {
    await ready;
    return new Promise((resolve, reject) => {
      const n = ++id;
      pending.set(n, { resolve, reject });
      ws.send(JSON.stringify({ id: n, method, params }));
    });
  };
  return { send, close: () => ws.close() };
}

async function evaluate(page, expression) {
  const r = await page.send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails));
  return r.result.value;
}

async function waitFor(page, expression, timeout = 45000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    if (await evaluate(page, expression).catch(() => false)) return;
    await sleep(250);
  }
  throw new Error("tempo esgotado esperando: " + expression);
}

async function record(page, base, example) {
  const text = fs.readFileSync(path.join(root, "docs/examples", `${example}.brain`), "utf8");
  const title = text.match(/^diagram \w+ "([^"]+)"/m)[1];

  await page.send("Page.navigate", { url: `${base}/new` });
  await waitFor(page, "document.documentElement.dataset.theme === 'dark' && !!document.querySelector('.phx-connected')");
  await waitFor(page, "!!document.getElementById('source')");

  await evaluate(
    page,
    `(() => {
      const ta = document.getElementById('source');
      ta.value = ${JSON.stringify(text)};
      ta.dispatchEvent(new Event('input', { bubbles: true }));
      return true;
    })()`,
  );
  await waitFor(page, `document.title.startsWith(${JSON.stringify(title)})`);
  await sleep(1500); // o canvas aplica a cena nova logo depois do patch

  const before = new Set(fs.readdirSync(downloads));
  await evaluate(page, `document.querySelector('[data-bg-control="export-gif"]').click(); true`);

  let file = null;
  for (let i = 0; i < 600 && !file; i++) {
    await sleep(500);
    file = fs.readdirSync(downloads).find((f) => !before.has(f) && f.endsWith(".gif"));
  }
  if (!file) throw new Error(`o GIF de ${example} não foi gerado`);
  await sleep(300);

  const target = path.join(outDir, `${example}.gif`);
  fs.copyFileSync(path.join(downloads, file), target);
  console.log(`${path.relative(root, target)}  ${(fs.statSync(target).size / 1024).toFixed(0)} KB`);
}

let browser = null;
try {
  const { debugPort, wsPath } = await devtoolsEndpoint();
  browser = client(`ws://127.0.0.1:${debugPort}${wsPath}`);
  await browser.send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: downloads });

  const targets = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
  const page = client(targets.find((t) => t.type === "page").webSocketDebuggerUrl);
  await page.send("Page.enable");
  await page.send("Runtime.enable");

  const base = `http://localhost:${port}`;
  await page.send("Page.navigate", { url: `${base}/new` });
  await waitFor(page, "document.readyState === 'complete'");
  await evaluate(page, "localStorage.setItem('phx:theme', 'dark'); true");

  for (const example of EXAMPLES) await record(page, base, example);
  page.close();
} catch (e) {
  console.error(e);
  process.exitCode = 1;
} finally {
  // Fecha pelo protocolo (no Windows, matar o processo deixa o navegador
  // vivo); só se ele não responder é que o processo é encerrado à força.
  await browser?.send("Browser.close").catch(() => {});
  for (let i = 0; i < 50 && !exited; i++) await sleep(100);
  if (!exited) browserProcess.kill("SIGKILL");
  browser?.close();
  await sleep(300);
  fs.rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
}
