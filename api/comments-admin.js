// api/comments-admin.js
// Admin moderation for member comments. Protected by x-cron-secret (same
// shared secret as every refresh endpoint — one credential to manage).
//   GET  ?view=held            -> comments awaiting review (default)
//   GET  ?view=recent&limit=50 -> newest comments, any status
//   GET  ?view=story&storyId=  -> full thread incl. held
//   POST {action:"delete"|"approve"|"hold", id}
//
// Quick delete from PowerShell:
//   Invoke-RestMethod -Method Post -Uri "https://forge.quantumrx.eu/api/comments-admin" `
//     -Headers @{ "x-cron-secret" = $env:CRON_SECRET } -ContentType "application/json" `
//     -Body '{"action":"delete","id":"<comment id>"}'

import { kv } from "@vercel/kv";
import { logRequest, blockThreat } from "./_lib/sentinel.js";
import { storyKey, loadThread } from "./comments.js";

async function getComment(id) {
  const raw = await kv.get(`comment:${id}`);
  if (!raw) return null;
  return typeof raw === "string" ? JSON.parse(raw) : raw;
}

async function listByIds(ids) {
  if (!ids.length) return [];
  const rows = await kv.mget(...ids.map((id) => `comment:${id}`));
  return rows.filter(Boolean).map((r) => (typeof r === "string" ? JSON.parse(r) : r));
}

export default async function handler(req, res) {
  await logRequest(req, "comments-admin");
  const expected = process.env.CRON_SECRET;
  if (!expected || req.headers["x-cron-secret"] !== expected) {
    await blockThreat(req, "comments-admin", "missing-or-invalid-cron-secret");
    return res.status(401).json({ error: "Unauthorized" });
  }
  res.setHeader("Cache-Control", "no-store");

  if (req.method === "GET") {
    const view = String(req.query?.view || "held");
    const limit = Math.min(parseInt(req.query?.limit, 10) || 50, 200);
    if (view === "held") {
      const ids = (await kv.lrange("comments:held", 0, limit - 1)) || [];
      const rows = (await listByIds(ids)).filter((c) => c.status === "held");
      return res.status(200).json({ view, count: rows.length, comments: rows });
    }
    if (view === "recent") {
      const ids = (await kv.lrange("comments:recent", 0, limit - 1)) || [];
      return res.status(200).json({ view, comments: await listByIds(ids) });
    }
    if (view === "story") {
      const storyId = req.query?.storyId;
      if (!storyId) return res.status(400).json({ error: "storyId required" });
      return res.status(200).json({ view, comments: await loadThread(storyId, { includeHeld: true }) });
    }
    return res.status(400).json({ error: "Unknown view" });
  }

  if (req.method === "POST") {
    let body = req.body;
    if (typeof body === "string") { try { body = JSON.parse(body); } catch { body = {}; } }
    const { action, id } = body || {};
    if (!id || !["delete", "approve", "hold"].includes(action)) {
      return res.status(400).json({ error: "action (delete|approve|hold) and id required" });
    }
    const comment = await getComment(id);
    if (!comment) return res.status(404).json({ error: "Comment not found" });

    if (action === "delete") {
      await kv.del(`comment:${id}`);
      await kv.lrem(storyKey(comment.storyId), 0, id);
      await kv.lrem("comments:recent", 0, id);
      await kv.lrem("comments:held", 0, id);
      return res.status(200).json({ ok: true, action, id });
    }

    comment.status = action === "approve" ? "approved" : "held";
    comment.moderation = { ...(comment.moderation || {}), checked: true, reason: `admin:${action}`, at: Date.now() };
    await kv.set(`comment:${id}`, JSON.stringify(comment));
    if (action === "approve") await kv.lrem("comments:held", 0, id);
    else { await kv.lrem("comments:held", 0, id); await kv.lpush("comments:held", id); }
    return res.status(200).json({ ok: true, action, id, status: comment.status });
  }

  res.setHeader("Allow", "GET, POST");
  return res.status(405).json({ error: "Method not allowed" });
}
