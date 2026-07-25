#!/usr/bin/env node
// Smoke test du contrat des modules « Sora », indépendant de l'app iOS.
//
// Recrée les globals que l'app injecte (fetchv2, fetch, console, atob/btoa,
// URL, Buffer, setTimeout), charge le .js d'un module et appelle les 4 fonctions
// pour vérifier que le contrat tient (chaînes JSON, formes attendues) et que les
// polyfills couvrent les usages réels.
//
// Usage :
//   node app/tools/smoke.mjs <dossier-module> [mot-clé]
//   node app/tools/smoke.mjs nakios "one piece"
//   node app/tools/smoke.mjs --all           # teste les 8 modules (recherche only)

import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..", "..");

/// Résout un dossier de module : chemin explicite, ou nom relatif à la racine.
/// Les modules vivent désormais dans un dépôt séparé (git.luna-app.eu), donc on
/// accepte n'importe quel chemin local.
function resolveModuleDir(arg) {
  const candidates = [path.resolve(arg), path.join(REPO_ROOT, arg)];
  return candidates.find((p) => fs.existsSync(p)) ?? candidates[0];
}

/// Liste les sous-dossiers contenant une paire <nom>.json + <nom>.js.
function discoverModules(root) {
  if (!fs.existsSync(root)) return [];
  return fs
    .readdirSync(root, { withFileTypes: true })
    .filter((e) => e.isDirectory() && !e.name.startsWith("."))
    .map((e) => path.join(root, e.name))
    .filter((dir) => fs.existsSync(path.join(dir, `${path.basename(dir)}.js`)));
}

function buildSandbox(moduleName) {
  const logs = [];
  const fetchLog = [];

  async function fetchNative(url, headers = {}, method = "GET", body = null) {
    const started = Date.now();
    try {
      const res = await fetch(url, {
        method,
        headers,
        body: body && method !== "GET" ? body : undefined,
        redirect: "follow",
      });
      const text = await res.text();
      fetchLog.push(`${res.status} ${method} ${url} (${Date.now() - started}ms)`);
      return {
        status: res.status,
        ok: res.ok,
        url: res.url,
        headers: Object.fromEntries(res.headers.entries()),
        text: () => Promise.resolve(text),
        json: () => Promise.resolve(JSON.parse(text)),
      };
    } catch (e) {
      fetchLog.push(`ERR ${method} ${url} — ${e.message}`);
      throw e;
    }
  }

  const sandbox = {
    console: {
      log: (...a) => logs.push(a.join(" ")),
      warn: (...a) => logs.push("WARN " + a.join(" ")),
      error: (...a) => logs.push("ERROR " + a.join(" ")),
      info: (...a) => logs.push(a.join(" ")),
      debug: () => {},
    },
    fetchv2: (url, headers, method, body) => fetchNative(url, headers, method, body),
    fetch: (url, opts = {}) => fetchNative(url, opts.headers, opts.method, opts.body),
    atob: (s) => Buffer.from(s, "base64").toString("binary"),
    btoa: (s) => Buffer.from(s, "binary").toString("base64"),
    URL,
    URLSearchParams,
    Buffer,
    setTimeout,
    clearTimeout,
    encodeURIComponent,
    decodeURIComponent,
    JSON,
    Promise,
    Date,
    Math,
    parseInt,
    parseFloat,
    isNaN,
    RegExp,
  };
  sandbox.globalThis = sandbox;
  return { sandbox, logs, fetchLog };
}

function checkArrayOfKeys(label, raw, requiredKeys) {
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    return { ok: false, msg: `${label}: retour non-JSON (${e.message})` };
  }
  if (!Array.isArray(parsed)) {
    return { ok: false, msg: `${label}: attendu un tableau, reçu ${typeof parsed}` };
  }
  if (parsed.length === 0) return { ok: true, msg: `${label}: tableau vide (0)`, empty: true };
  const first = parsed[0];
  const missing = requiredKeys.filter((k) => !(k in first));
  if (missing.length) {
    return { ok: false, msg: `${label}: clés manquantes ${missing.join(", ")}` };
  }
  return { ok: true, msg: `${label}: ${parsed.length} élément(s) OK`, parsed };
}

async function testModule(dir, keyword) {
  const folder = path.basename(dir);
  const jsPath = path.join(dir, `${folder}.js`);
  const jsonPath = path.join(dir, `${folder}.json`);
  if (!fs.existsSync(jsPath)) {
    console.log(`❌ ${folder}: ${folder}.js introuvable (${jsPath})`);
    return false;
  }

  const manifest = fs.existsSync(jsonPath)
    ? JSON.parse(fs.readFileSync(jsonPath, "utf-8"))
    : { sourceName: folder, version: "?" };
  const script = fs.readFileSync(jsPath, "utf-8");
  const { sandbox, logs, fetchLog } = buildSandbox(folder);

  const context = vm.createContext(sandbox);
  try {
    vm.runInContext(script, context, { filename: `${folder}.js` });
  } catch (e) {
    console.log(`❌ ${folder}: erreur d'évaluation — ${e.message}`);
    return false;
  }

  const fns = ["searchResults", "extractDetails", "extractEpisodes", "extractStreamUrl"];
  const missingFns = fns.filter((f) => typeof sandbox[f] !== "function");
  console.log(`\n=== ${manifest.sourceName} (${folder}) v${manifest.version} ===`);
  if (missingFns.length) {
    console.log(`❌ fonctions absentes : ${missingFns.join(", ")}`);
    return false;
  }
  console.log(`✅ 4 fonctions présentes`);

  let allOk = true;
  try {
    const searchRaw = await sandbox.searchResults(keyword);
    const sr = checkArrayOfKeys("searchResults", searchRaw, ["title", "image", "href"]);
    console.log(sr.ok ? `✅ ${sr.msg}` : `❌ ${sr.msg}`);
    allOk = allOk && sr.ok;

    if (sr.parsed && sr.parsed.length) {
      const href = sr.parsed[0].href;

      const detailsRaw = await sandbox.extractDetails(href);
      const dr = checkArrayOfKeys("extractDetails", detailsRaw, ["description", "aliases", "airdate"]);
      console.log(dr.ok ? `✅ ${dr.msg}` : `❌ ${dr.msg}`);
      allOk = allOk && dr.ok;

      const epsRaw = await sandbox.extractEpisodes(href);
      const er = checkArrayOfKeys("extractEpisodes", epsRaw, ["href", "number"]);
      console.log(er.ok ? `✅ ${er.msg}` : `❌ ${er.msg}`);
      allOk = allOk && er.ok;

      if (er.parsed && er.parsed.length) {
        const epHref = er.parsed[0].href;
        const streamRaw = await sandbox.extractStreamUrl(epHref);
        try {
          const parsed = JSON.parse(streamRaw);
          const nStreams = Array.isArray(parsed?.streams) ? parsed.streams.length
            : (parsed?.stream ? 1 : 0);
          console.log(nStreams > 0
            ? `✅ extractStreamUrl: ${nStreams} flux`
            : `⚠️  extractStreamUrl: 0 flux (peut être normal hors ligne)`);
        } catch {
          const isURL = typeof streamRaw === "string" && /^https?:\/\//.test(streamRaw.trim());
          console.log(isURL ? `✅ extractStreamUrl: URL brute` : `❌ extractStreamUrl: retour inattendu`);
          allOk = allOk && isURL;
        }
      }
    }
  } catch (e) {
    console.log(`❌ exception d'exécution : ${e.message}`);
    allOk = false;
  }

  if (fetchLog.length) console.log(`   réseau : ${fetchLog.length} requête(s)`);
  return allOk;
}

function usage() {
  console.log("Usage :");
  console.log("  node app/tools/smoke.mjs <dossier-du-module> [mot-clé]");
  console.log("  node app/tools/smoke.mjs --all <dossier-des-sources> [mot-clé]");
  console.log("");
  console.log("Les modules vivent dans un dépôt séparé (git.luna-app.eu/MXFia19/sources) :");
  console.log("  git clone https://git.luna-app.eu/MXFia19/sources /tmp/sources");
  console.log("  node app/tools/smoke.mjs /tmp/sources/movix \"interstellar\"");
  console.log("  node app/tools/smoke.mjs --all /tmp/sources \"one piece\"");
}

async function main() {
  const args = process.argv.slice(2);
  if (!args.length) { usage(); process.exit(2); }

  if (args[0] === "--all") {
    const root = resolveModuleDir(args[1] ?? ".");
    const keyword = args[2] || "one piece";
    const dirs = discoverModules(root);
    if (!dirs.length) {
      console.log(`❌ Aucun module trouvé dans ${root}`);
      usage();
      process.exit(2);
    }
    let ok = true;
    for (const dir of dirs) ok = (await testModule(dir, keyword)) && ok;
    process.exit(ok ? 0 : 1);
  }

  const dir = resolveModuleDir(args[0]);
  const keyword = args[1] || "one piece";
  const ok = await testModule(dir, keyword);
  process.exit(ok ? 0 : 1);
}

main();
