#!/usr/bin/env python3
"""
Infrastructure MBSE dashboard crawler.

Automates the manual "stack status check" this project has been doing by
hand every few days: page availability, feed freshness, cron trigger health,
VPS service/disk status, and outstanding Q-Sentinel blocks. Writes a
human-readable report to stdout and a machine-readable snapshot to
08_status/dashboard.yaml.

Deliberately stdlib-only (urllib, subprocess, ssl) — no pip install needed to
run this anywhere Python 3.8+ already is.

CREDENTIALS — read from environment variables, never hardcoded here (this
file is committed to the repo):
    GITHUB_TOKEN        — GitHub PAT with actions:read on QuantumRX-lab/Qrx_MARK_T2.
                           Skips the GitHub Actions check if unset.
    UPSTASH_KV_URL       — Upstash REST URL (e.g. https://xxx.upstash.io).
    UPSTASH_KV_TOKEN     — Upstash REST token.
                           Skips the Sentinel block check if either is unset.
    VPS_HOST             — SSH target for the RSI VPS, default "root@91.99.127.39".
                           Skips the VPS check entirely if `ssh` isn't on PATH
                           or the connection fails (e.g. no key configured here).

Usage:
    python crawler.py                  # full check, human report + dashboard.yaml
    python crawler.py --quiet          # dashboard.yaml only, no stdout report
    python crawler.py --skip-vps       # skip the SSH-dependent VPS check
"""

import argparse
import json
import os
import ssl
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
DASHBOARD_PATH = HERE / "08_status" / "dashboard.yaml"

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

FORGE_PAGES = [
    "/", "/ai-labs.html", "/the-strip.html", "/the-meme.html",
    "/break-the-sentinel.html", "/podcasts.html", "/products.html",
    "/this-week-in-tech.html", "/nft-forge-tv.html", "/lotm-forge-tv.html",
    "/exploit-watch.html",
]
GHOST_PAGES = [
    "https://www.quantumrx.eu/",
    "https://www.quantumrx.eu/signals/",
    "https://www.quantumrx.eu/the-draw/",
    "https://www.quantumrx.eu/this-week-in-tech/",
    "https://www.quantumrx.eu/mainstream/",
    "https://www.quantumrx.eu/products/",
]
COUK_PAGES = [
    "https://quantumrx.co.uk/",
    "https://quantumrx.co.uk/order.html",
    "https://quantumrx.co.uk/status.html",
]

# NOTE: cert verification relaxed to work around a Windows Python trust-store
# quirk observed on this machine (same one worked around with `curl
# --ssl-no-revoke` throughout this project's manual status checks) — not a
# statement that these endpoints don't need TLS. If you run this from a
# machine without that quirk, ssl.create_default_context() alone is fine.
_ctx = ssl.create_default_context()
_ctx.check_hostname = False
_ctx.verify_mode = ssl.CERT_NONE


def _get(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, context=_ctx, timeout=timeout) as resp:
        return resp.status, resp.read().decode("utf-8", errors="replace")


def check_pages(urls, base=""):
    results = []
    for p in urls:
        url = (base + p) if base else p
        try:
            status, _ = _get(url)
            results.append({"url": url, "status": status, "ok": status == 200})
        except urllib.error.HTTPError as e:
            results.append({"url": url, "status": e.code, "ok": False})
        except Exception as e:  # noqa: BLE001 — report any failure, don't crash the crawl
            results.append({"url": url, "status": None, "ok": False, "error": str(e)})
    return results


def check_feed_freshness():
    feeds = {}
    now = datetime.now(timezone.utc)
    checks = {
        "cartoon": "https://forge.quantumrx.eu/api/cartoon",
        "meme": "https://forge.quantumrx.eu/api/meme",
        "news-feed": "https://forge.quantumrx.eu/api/news-feed",
        "draw-feed": "https://forge.quantumrx.eu/api/draw-feed",
        "mainstream-feed": "https://forge.quantumrx.eu/api/mainstream-feed",
        "weekly-feed": "https://forge.quantumrx.eu/api/weekly-feed",
        "podcast-feed": "https://forge.quantumrx.eu/api/podcast-feed",
    }
    for name, url in checks.items():
        cache_busted = f"{url}?_={int(now.timestamp())}"
        try:
            _, body = _get(cache_busted)
            data = json.loads(body)
            date = data.get("date")
            updated = data.get("updated")
            if name == "weekly-feed":
                updated = (data.get("current") or {}).get("updatedAt")
            if isinstance(updated, (int, float)):
                updated = datetime.fromtimestamp(updated / 1000, tz=timezone.utc).isoformat()
            feeds[name] = {"date": date, "updated": updated, "issueNumber": data.get("issueNumber")}
        except Exception as e:  # noqa: BLE001
            feeds[name] = {"error": str(e)}
    return feeds


def check_github_actions():
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        return {"skipped": "GITHUB_TOKEN not set"}
    url = "https://api.github.com/repos/QuantumRX-lab/Qrx_MARK_T2/actions/workflows/refresh.yml/runs?per_page=5"
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": UA,
    })
    try:
        with urllib.request.urlopen(req, context=_ctx, timeout=20) as resp:
            data = json.loads(resp.read().decode())
        runs = [
            {"created_at": r["created_at"], "status": r["status"], "conclusion": r["conclusion"], "event": r["event"]}
            for r in data.get("workflow_runs", [])
        ]
        scheduled_since_disable = [r for r in runs if r["event"] == "schedule" and r["created_at"] > "2026-07-13T11:31:02Z"]
        return {
            "recent_runs": runs,
            "schedule_disable_holding": len(scheduled_since_disable) == 0,
        }
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)}


def check_sentinel_blocks():
    kv_url = os.environ.get("UPSTASH_KV_URL")
    kv_token = os.environ.get("UPSTASH_KV_TOKEN")
    if not kv_url or not kv_token:
        return {"skipped": "UPSTASH_KV_URL / UPSTASH_KV_TOKEN not set"}
    req = urllib.request.Request(
        f"{kv_url}/keys/threat_action:*",
        headers={"Authorization": f"Bearer {kv_token}"},
    )
    try:
        with urllib.request.urlopen(req, context=_ctx, timeout=15) as resp:
            data = json.loads(resp.read().decode())
        keys = data.get("result") or []
        return {"active_blocks": len(keys), "ips": [k.split(":", 1)[1] for k in keys]}
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)}


def check_vps(host):
    if not host:
        return {"skipped": "no VPS_HOST"}
    cmd = [
        "ssh", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes", host,
        "df -h / | tail -1 | awk '{print $5}'; "
        "for s in mip-api mip-worker nginx; do systemctl is-active $s; done; "
        "cd /opt/mip && git status --short | wc -l && git log -1 --format=%h:%ad --date=short",
    ]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if out.returncode != 0:
            return {"error": out.stderr.strip() or "ssh command failed"}
        lines = [l for l in out.stdout.strip().splitlines() if l]
        disk_pct, mip_api, mip_worker, nginx, uncommitted, last_commit = (lines + [None] * 6)[:6]
        return {
            "disk_used_pct": disk_pct,
            "mip_api": mip_api,
            "mip_worker": mip_worker,
            "nginx": nginx,
            "uncommitted_files": uncommitted,
            "last_commit": last_commit,
        }
    except Exception as e:  # noqa: BLE001
        return {"error": str(e)}


def to_yaml(d, indent=0):
    """Minimal, dependency-free YAML emitter for the flat/nested dicts and
    lists this script produces. Not a general-purpose YAML writer — quotes
    every string to sidestep colon/special-character ambiguity."""
    pad = "  " * indent
    lines = []
    if isinstance(d, dict):
        if not d:
            return pad + "{}\n"
        for k, v in d.items():
            if isinstance(v, (dict, list)) and v:
                lines.append(f"{pad}{k}:")
                lines.append(to_yaml(v, indent + 1))
            elif isinstance(v, (dict, list)):
                lines.append(f"{pad}{k}: {'{}' if isinstance(v, dict) else '[]'}")
            else:
                lines.append(f"{pad}{k}: {_scalar(v)}")
    elif isinstance(d, list):
        if not d:
            return pad + "[]\n"
        for item in d:
            if isinstance(item, dict):
                lines.append(f"{pad}-")
                lines.append(to_yaml(item, indent + 1))
            else:
                lines.append(f"{pad}- {_scalar(item)}")
    return "\n".join(lines) + ("\n" if lines else "")


def _scalar(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    s = str(v).replace('"', '\\"')
    return f'"{s}"'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--quiet", action="store_true", help="Skip the stdout report, only write dashboard.yaml")
    parser.add_argument("--skip-vps", action="store_true", help="Skip the SSH-dependent VPS check")
    args = parser.parse_args()

    now = datetime.now(timezone.utc)
    report = {
        "generated_at": now.isoformat(),
        "generated_by": "crawler.py",
        "forge_quantumrx_eu_pages": check_pages(FORGE_PAGES, base="https://forge.quantumrx.eu"),
        "quantumrx_eu_ghost_pages": check_pages(GHOST_PAGES),
        "quantumrx_co_uk_pages": check_pages(COUK_PAGES),
        "feed_freshness": check_feed_freshness(),
        "github_actions": check_github_actions(),
        "sentinel_blocks": check_sentinel_blocks(),
        "vps": ({"skipped": "--skip-vps"} if args.skip_vps
                else check_vps(os.environ.get("VPS_HOST", "root@91.99.127.39"))),
    }

    DASHBOARD_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(DASHBOARD_PATH, "w", encoding="utf-8") as f:
        f.write("# Infrastructure status dashboard — written by crawler.py, do not hand-edit.\n")
        f.write(to_yaml(report))

    if not args.quiet:
        _print_report(report)

    all_pages_ok = all(
        r["ok"] for r in
        report["forge_quantumrx_eu_pages"] + report["quantumrx_eu_ghost_pages"] + report["quantumrx_co_uk_pages"]
    )
    if not all_pages_ok:
        sys.exit(1)


def _print_report(report):
    print(f"== Infrastructure status — {report['generated_at']} ==\n")

    for label, key in [
        ("forge.quantumrx.eu", "forge_quantumrx_eu_pages"),
        ("quantumrx.eu (Ghost)", "quantumrx_eu_ghost_pages"),
        ("quantumrx.co.uk", "quantumrx_co_uk_pages"),
    ]:
        pages = report[key]
        bad = [p for p in pages if not p["ok"]]
        status = "OK" if not bad else f"{len(bad)} FAILING"
        print(f"[{status}] {label} — {len(pages)} pages checked")
        for p in bad:
            print(f"    FAIL: {p['url']} -> {p.get('status')} {p.get('error', '')}")

    print("\n-- Feed freshness --")
    for name, info in report["feed_freshness"].items():
        if "error" in info:
            print(f"  {name}: ERROR {info['error']}")
        else:
            print(f"  {name}: date={info.get('date')} updated={info.get('updated')} issue={info.get('issueNumber')}")

    print("\n-- GitHub Actions --")
    gha = report["github_actions"]
    if "skipped" in gha:
        print(f"  skipped: {gha['skipped']}")
    elif "error" in gha:
        print(f"  ERROR: {gha['error']}")
    else:
        print(f"  schedule disable holding: {gha['schedule_disable_holding']}")
        for r in gha["recent_runs"][:3]:
            print(f"    {r['created_at']} {r['status']} {r['conclusion']} ({r['event']})")

    print("\n-- Sentinel blocks --")
    sb = report["sentinel_blocks"]
    if "skipped" in sb:
        print(f"  skipped: {sb['skipped']}")
    elif "error" in sb:
        print(f"  ERROR: {sb['error']}")
    else:
        print(f"  {sb['active_blocks']} active block(s): {', '.join(sb['ips']) or '(none)'}")

    print("\n-- VPS (quantumrx.co.uk backend) --")
    vps = report["vps"]
    if "skipped" in vps:
        print(f"  skipped: {vps['skipped']}")
    elif "error" in vps:
        print(f"  ERROR: {vps['error']}")
    else:
        print(f"  disk used: {vps['disk_used_pct']}  mip-api: {vps['mip_api']}  mip-worker: {vps['mip_worker']}  nginx: {vps['nginx']}")
        print(f"  uncommitted files: {vps['uncommitted_files']}  last commit: {vps['last_commit']}")

    print(f"\nWrote {DASHBOARD_PATH}")


if __name__ == "__main__":
    main()
