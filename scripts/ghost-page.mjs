#!/usr/bin/env node
// scripts/ghost-page.mjs — read/back up/replace the HTML of a Ghost page.
//
// Credentials come ONLY from environment variables (never args, never files
// in the repo):
//   GHOST_ADMIN_API_KEY   id:secret from Ghost Admin > Settings > Integrations
//   GHOST_ADMIN_URL       e.g. https://quantumrx.ghost.io (default)
//
// Usage:
//   node scripts/ghost-page.mjs get  <slug>                 # print page meta, save backup
//   node scripts/ghost-page.mjs put  <slug> <html-file>     # back up, then replace content
//   node scripts/ghost-page.mjs redirects-get               # download current redirects.yaml
//   node scripts/ghost-page.mjs redirects-put <yaml-file>   # upload (REPLACES all redirects)
//
// Backups land in ghost-current/backups/<slug>-<timestamp>.json (gitignored
// convention: ghost-current/ is kept out of git).

import { createHmac } from "node:crypto";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const ADMIN_URL = (process.env.GHOST_ADMIN_URL || "https://quantumrx.ghost.io").replace(/\/$/, "");
const KEY = process.env.GHOST_ADMIN_API_KEY;
if (!KEY || !KEY.includes(":")) {
  console.error("GHOST_ADMIN_API_KEY (id:secret) must be set in the environment");
  process.exit(2);
}

function b64url(input) {
  return Buffer.from(input).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function token() {
  const [id, secret] = KEY.split(":");
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "HS256", typ: "JWT", kid: id }));
  const payload = b64url(JSON.stringify({ iat: now, exp: now + 300, aud: "/admin/" }));
  const sig = createHmac("sha256", Buffer.from(secret, "hex")).update(`${header}.${payload}`).digest("base64url");
  return `${header}.${payload}.${sig}`;
}
async function api(path, init = {}) {
  const res = await fetch(`${ADMIN_URL}/ghost/api/admin${path}`, {
    ...init,
    headers: { Authorization: `Ghost ${token()}`, "Accept-Version": "v5.0", ...(init.headers || {}) },
  });
  const text = await res.text();
  let body; try { body = JSON.parse(text); } catch { body = text; }
  if (!res.ok) throw new Error(`${init.method || "GET"} ${path} -> ${res.status}: ${typeof body === "string" ? body.slice(0, 300) : JSON.stringify(body).slice(0, 600)}`);
  return body;
}
function stamp() { return new Date().toISOString().replace(/[:.]/g, "-"); }
function backup(slug, page) {
  const dir = resolve(ROOT, "ghost-current", "backups");
  mkdirSync(dir, { recursive: true });
  const file = resolve(dir, `${slug}-${stamp()}.json`);
  writeFileSync(file, JSON.stringify(page, null, 2));
  return file;
}

async function getPage(slug) {
  const data = await api(`/pages/slug/${encodeURIComponent(slug)}/?formats=html,lexical`);
  const page = data.pages?.[0];
  if (!page) throw new Error(`No page with slug '${slug}'`);
  return page;
}

const [cmd, a, b] = process.argv.slice(2);
try {
  if (cmd === "get") {
    const page = await getPage(a);
    const file = backup(a, page);
    console.log(JSON.stringify({ id: page.id, slug: page.slug, title: page.title, status: page.status, url: page.url, updated_at: page.updated_at, html_chars: (page.html || "").length, backup: file }, null, 2));
  } else if (cmd === "put") {
    const html = readFileSync(resolve(b), "utf8");
    const page = await getPage(a);
    const file = backup(a, page);
    console.log(`backed up ${a} (${(page.html || "").length} chars) -> ${file}`);
    // Send a Lexical document containing ONE html card. Do NOT use
    // ?source=html: Ghost's HTML->Lexical converter silently drops <style>
    // and <script>, leaving an empty page (learned the hard way 2026-09-18).
    // updated_at is Ghost's collision check — must match the current value.
    const existingCard = (() => { try { return JSON.parse(page.lexical).root.children.find((c) => c.type === "html"); } catch { return null; } })();
    const card = { type: "html", version: 1, html };
    if (existingCard?.visibility) card.visibility = existingCard.visibility;
    const lexical = JSON.stringify({ root: { children: [card], direction: null, format: "", indent: 0, type: "root", version: 1 } });
    const data = await api(`/pages/${page.id}/?formats=html,lexical`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ pages: [{ lexical, updated_at: page.updated_at }] }),
    });
    const p = data.pages?.[0];
    console.log(JSON.stringify({ id: p.id, slug: p.slug, status: p.status, url: p.url, updated_at: p.updated_at, html_chars: (p.html || "").length }, null, 2));
  } else if (cmd === "canonical") {
    // canonical <slug> <absolute-url> — point a retired page at its successor
    const page = await getPage(a);
    backup(a, page);
    const data = await api(`/pages/${page.id}/`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ pages: [{ canonical_url: b, updated_at: page.updated_at }] }),
    });
    console.log(JSON.stringify({ slug: a, canonical_url: data.pages?.[0]?.canonical_url }, null, 2));
  } else if (cmd === "redirects-get") {
    const res = await fetch(`${ADMIN_URL}/ghost/api/admin/redirects/download/`, { headers: { Authorization: `Ghost ${token()}`, "Accept-Version": "v5.0" } });
    const text = await res.text();
    if (!res.ok) throw new Error(`redirects/download -> ${res.status}: ${text.slice(0, 300)}`);
    process.stdout.write(text.endsWith("\n") ? text : text + "\n");
  } else if (cmd === "redirects-put") {
    const yaml = readFileSync(resolve(a), "utf8");
    const form = new FormData();
    form.append("redirects", new Blob([yaml], { type: "application/x-yaml" }), "redirects.yaml");
    const res = await fetch(`${ADMIN_URL}/ghost/api/admin/redirects/upload/`, { method: "POST", headers: { Authorization: `Ghost ${token()}`, "Accept-Version": "v5.0" }, body: form });
    const text = await res.text();
    if (!res.ok) throw new Error(`redirects/upload -> ${res.status}: ${text.slice(0, 300)}`);
    console.log("redirects uploaded");
  } else {
    console.error("usage: get <slug> | put <slug> <html-file> | redirects-get | redirects-put <yaml-file>");
    process.exit(2);
  }
} catch (err) {
  console.error(err.message);
  process.exit(1);
}
