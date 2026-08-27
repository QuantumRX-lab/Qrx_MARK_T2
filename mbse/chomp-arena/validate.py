#!/usr/bin/env python3
"""
Chomp Arena MBSE validator.

Same principle as mbse/infrastructure/validate.py (D-INFRA-009): store facts
once, calculate every count, never trust a handwritten rollup. It recomputes
counts and cross-references from the atomic records and fails loudly on any
mismatch, broken reference, schema violation or duplicate ID.

Three checks are specific to this tree, because its failure modes differ from
an infrastructure tree's:

  * `allocated_to` is a Roblox DataModel path, not a repo file path — the
    artefact is a .rbxl place file on a laptop, not files in this repo. Checked
    against the real Roblox service list rather than the filesystem.
  * Phase ordering: a requirement may not derive from a parent scheduled in a
    later phase, and must be verified by at least one test case scheduled no
    later than itself. A v1 requirement whose only test arrives in v3 is not
    verified during v1, it is just claimed.
  * Method agreement: a requirement's verification_method must actually appear
    among the methods of the test cases that verify it.

Usage:
    python validate.py            # full report, exit 1 on any failure
    python validate.py --quiet    # errors only
"""

import argparse
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(2)

HERE = Path(__file__).resolve().parent

REQUIREMENTS_FILE = HERE / "02_requirements" / "requirements.yaml"
TEST_CASES_FILE = HERE / "04_verification" / "test_cases.yaml"
RISK_REGISTER_FILE = HERE / "05_risks" / "risk_register.yaml"
DECISION_LOG_FILE = HERE / "06_decisions" / "decision_log.yaml"
DASHBOARD_FILE = HERE / "08_status" / "dashboard.yaml"
WORKSTREAMS_DIR = HERE / "workstreams"

PHASE_ORDER = {"v1": 1, "v2": 2, "v3": 3}

REQ_ENUMS = {
    "level": {"L1_stakeholder", "L2_system"},
    "status": {"DRAFT", "APPROVED", "DEFERRED", "DELETED"},
    "priority": {"CRITICAL", "HIGH", "MEDIUM", "LOW"},
    "verification_status": {"NOT_STARTED", "IN_PROGRESS", "PASSED", "FAILED", "DEFERRED", "N/A"},
    "verification_method": {"TEST", "ANALYSIS", "DEMONSTRATION", "INSPECTION"},
    "phase": set(PHASE_ORDER),
}
REQ_REQUIRED_FIELDS = [
    "id", "title", "shall_statement", "level", "status", "priority",
    "verification_status", "verification_method", "phase", "allocated_to",
    "rationale", "chain", "created_date", "last_modified", "author",
]
REQ_ID_RE = re.compile(r"^CHOMP-(STK|SYS)-\d{3}$")

TC_ENUMS = {
    "type": {"UNIT", "INTEGRATION", "SYSTEM", "ACCEPTANCE"},
    "method": {"TEST", "ANALYSIS", "DEMONSTRATION", "INSPECTION"},
    "status": {"NOT_STARTED", "IN_PROGRESS", "PASSED", "FAILED", "BLOCKED"},
    "phase": set(PHASE_ORDER),
    "automation": {"AUTOMATED", "HYBRID", "MANUAL"},
}
TC_REQUIRED_FIELDS = [
    "id", "title", "verifies", "type", "method", "preconditions",
    "test_data", "procedure", "expected_result", "pass_criteria",
    "status", "automation", "phase",
]
TC_ID_RE = re.compile(r"^CHOMP-TC-\d{3}$")

DECISION_STATUSES = {"ACTIVE", "PARTIAL", "SUPERSEDED", "VOID"}
RISK_ENUMS = {"severity": {"CRITICAL", "HIGH", "MEDIUM", "LOW"}, "status": {"OPEN", "CLOSED"}}
RISK_REQUIRED_FIELDS = ["id", "title", "description", "severity", "status", "detected"]
RISK_ID_RE = re.compile(r"^RISK-CHOMP-\d{3}$")

DECISION_REQUIRED_FIELDS = ["id", "date", "title", "decision"]
DECISION_ID_RE = re.compile(r"^D-CHOMP-\d{3}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# Decomposition chains. Every requirement belongs to exactly one, and every
# chain must have a workstreams/<chain>/log.yaml the agents working it append to.
CHAINS = {
    "CHAIN-VEHICLE", "CHAIN-COMBAT", "CHAIN-ECONOMY", "CHAIN-GHOSTS",
    "CHAIN-GATES", "CHAIN-MAZE", "CHAIN-MATCH", "CHAIN-UI",
    "CHAIN-PLATFORM", "CHAIN-KIT",
}
LOG_ENTRY_ACTIONS = {
    "CLAIMED", "DELIVERED", "ACCEPTED", "REJECTED", "BLOCKED", "DECIDED",
    "ESTABLISHED", "NOTE",
}
LOG_ENTRY_REQUIRED = ["date", "agent", "action", "requirements", "summary", "status"]
LOG_STATUSES = {"OPEN", "DONE", "BLOCKED"}

# Roblox service roots an allocated_to path may start from.
ROBLOX_SERVICES = {
    "Workspace", "Players", "ReplicatedStorage", "ReplicatedFirst",
    "ServerScriptService", "ServerStorage", "StarterGui", "StarterPlayer",
    "StarterPack", "Lighting", "SoundService", "TextChatService",
    "CollectionService", "TweenService", "RunService", "DataStoreService",
}


class Report:
    def __init__(self):
        self.errors, self.warnings, self.info = [], [], []

    def error(self, m): self.errors.append(m)
    def warn(self, m): self.warnings.append(m)
    def note(self, m): self.info.append(m)

    @property
    def ok(self): return not self.errors


def check_duplicate_keys(path, report):
    """PyYAML keeps the LAST of two identical keys and says nothing.

    A bad edit to dashboard.yaml today produced two next_actions blocks; the
    file parsed, every count still reconciled, and validate.py passed while
    reading the stale copy. A checker that can be fooled by a duplicated key is
    a checker that certifies the wrong file (D-CHOMP-067).
    """
    seen, dupes = set(), []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line[0].isspace() or line.lstrip().startswith("#") or ":" not in line:
            continue
        key = line.split(":", 1)[0]
        if key in seen:
            dupes.append(key)
        seen.add(key)
    for key in dupes:
        report.error(f"{path.name}: duplicate top-level key {key!r} - PyYAML silently keeps the last")


def load_yaml(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def check_required_fields(record, required, rid, kind, report):
    for field in required:
        if field not in record or record[field] in (None, ""):
            report.error(f"{kind} {rid}: missing required field '{field}'")


def check_enums(record, enums, rid, kind, report):
    for field, allowed in enums.items():
        if record.get(field) is not None and record[field] not in allowed:
            report.error(f"{kind} {rid}: field '{field}' = {record[field]!r} not in {sorted(allowed)}")


def check_date(record, field, rid, kind, report):
    v = record.get(field)
    if v is not None and not DATE_RE.match(str(v)):
        report.error(f"{kind} {rid}: field '{field}' = {v!r} is not YYYY-MM-DD")


def validate_requirements(report):
    reqs = load_yaml(REQUIREMENTS_FILE).get("requirements", [])
    seen = set()
    for r in reqs:
        rid = r.get("id", "<no id>")
        check_required_fields(r, REQ_REQUIRED_FIELDS, rid, "Requirement", report)
        check_enums(r, REQ_ENUMS, rid, "Requirement", report)
        check_date(r, "created_date", rid, "Requirement", report)
        check_date(r, "last_modified", rid, "Requirement", report)
        if not REQ_ID_RE.match(rid):
            report.error(f"Requirement {rid}: ID doesn't match CHOMP-(STK|SYS)-NNN")
        if rid in seen:
            report.error(f"Requirement {rid}: duplicate ID")
        seen.add(rid)
        if r.get("chain") and r["chain"] not in CHAINS:
            report.error(f"Requirement {rid}: chain {r['chain']!r} is not a known chain")
        if r.get("level") == "L2_system" and not r.get("derives_from"):
            report.warn(f"Requirement {rid}: L2 system requirement derives from nothing")
    return {r["id"]: r for r in reqs if "id" in r}


def validate_test_cases(report):
    tcs = load_yaml(TEST_CASES_FILE).get("test_cases", [])
    seen = set()
    for tc in tcs:
        tid = tc.get("id", "<no id>")
        check_required_fields(tc, TC_REQUIRED_FIELDS, tid, "Test case", report)
        check_enums(tc, TC_ENUMS, tid, "Test case", report)
        if not TC_ID_RE.match(tid):
            report.error(f"Test case {tid}: ID doesn't match CHOMP-TC-NNN")
        if tid in seen:
            report.error(f"Test case {tid}: duplicate ID")
        seen.add(tid)
    return {tc["id"]: tc for tc in tcs if "id" in tc}


def validate_risks(report):
    data = load_yaml(RISK_REGISTER_FILE)
    risks = data.get("risks", [])
    seen = set()
    for risk in risks:
        rid = risk.get("id", "<no id>")
        check_required_fields(risk, RISK_REQUIRED_FIELDS, rid, "Risk", report)
        check_enums(risk, RISK_ENUMS, rid, "Risk", report)
        check_date(risk, "detected", rid, "Risk", report)
        if not RISK_ID_RE.match(rid):
            report.error(f"Risk {rid}: ID doesn't match RISK-CHOMP-NNN")
        if rid in seen:
            report.error(f"Risk {rid}: duplicate ID")
        seen.add(rid)
        if risk.get("status") == "OPEN" and not risk.get("mitigation"):
            report.error(f"Risk {rid}: OPEN with no mitigation recorded")

    computed_open = sum(1 for r in risks if r.get("status") == "OPEN")
    computed_closed = sum(1 for r in risks if r.get("status") == "CLOSED")
    if data.get("open_count") != computed_open:
        report.error(f"risk_register.yaml states open_count {data.get('open_count')}, records say {computed_open}")
    if data.get("closed_count") != computed_closed:
        report.error(f"risk_register.yaml states closed_count {data.get('closed_count')}, records say {computed_closed}")
    if data.get("open_count") == computed_open and data.get("closed_count") == computed_closed:
        report.note(f"risk counts verified: {computed_open} open, {computed_closed} closed")
    return {r["id"]: r for r in risks if "id" in r}


def validate_decisions(report):
    decisions = load_yaml(DECISION_LOG_FILE).get("decisions", [])
    seen = set()
    for d in decisions:
        did = d.get("id", "<no id>")
        check_required_fields(d, DECISION_REQUIRED_FIELDS, did, "Decision", report)
        check_date(d, "date", did, "Decision", report)
        if not DECISION_ID_RE.match(did):
            report.error(f"Decision {did}: ID doesn't match D-CHOMP-NNN")
        if did in seen:
            report.error(f"Decision {did}: duplicate ID")
        seen.add(did)
        if d.get("status") and d["status"] not in DECISION_STATUSES:
            report.error(f"Decision {did}: status {d['status']!r} not in {sorted(DECISION_STATUSES)}")

    by_id = {d["id"]: d for d in decisions if "id" in d}

    # ── Supersession, as data rather than prose (D-CHOMP-067) ───────────
    # Eight supersessions lived only in sentences like "supersedes the
    # electrified half of D-CHOMP-059", so the only way to know the current
    # ruling on anything was to read all 1,800 lines and apply partial
    # overrides in your head. An agent that read D-CHOMP-033 and stopped
    # implemented the wrong controls; control_scheme.md proves it happened.
    for did, d in by_id.items():
        for ref in d.get("supersedes") or []:
            other = ref.get("id") if isinstance(ref, dict) else ref
            if other not in by_id:
                report.error(f"Decision {did}: supersedes unknown {other}")
            elif not any((r.get("id") if isinstance(r, dict) else r) == did
                         for r in by_id[other].get("superseded_by") or []):
                report.error(
                    f"Decision {did}: says it supersedes {other}, but {other} "
                    f"does not list {did} in superseded_by"
                )
        for ref in d.get("superseded_by") or []:
            other = ref.get("id") if isinstance(ref, dict) else ref
            if other not in by_id:
                report.error(f"Decision {did}: superseded_by unknown {other}")
            elif not any((r.get("id") if isinstance(r, dict) else r) == did
                         for r in by_id[other].get("supersedes") or []):
                report.error(
                    f"Decision {did}: claims {other} supersedes it, but {other} "
                    f"does not list {did} in supersedes"
                )
        if d.get("superseded_by") and d.get("status") == "ACTIVE":
            report.error(f"Decision {did}: marked ACTIVE while something supersedes it")

    # ── No silent holes in the sequence ─────────────────────────────────
    # D-CHOMP-057 simply did not exist, and nobody could say whether a record
    # had been deleted or the counter misread. A VOID tombstone answers it; an
    # unexplained gap sends the next reader hunting for a record that is not
    # there.
    numbers = sorted(int(i.rsplit("-", 1)[1]) for i in by_id if DECISION_ID_RE.match(i))
    if numbers:
        for n in range(1, max(numbers) + 1):
            did = f"D-CHOMP-{n:03d}"
            if n not in numbers:
                report.error(
                    f"Decision sequence: {did} is missing. Add a tombstone entry "
                    f"with status VOID if the number was skipped"
                )
    return by_id


def check_reciprocity(requirements, test_cases, risks, report):
    for rid, req in requirements.items():
        for tid in req.get("verified_by") or []:
            if tid not in test_cases:
                report.error(f"Requirement {rid}: verified_by references non-existent test case {tid}")
            elif rid not in (test_cases[tid].get("verifies") or []):
                report.error(f"Requirement {rid} lists {tid} in verified_by, but {tid} does not verify it back")
    for tid, tc in test_cases.items():
        for rid in tc.get("verifies") or []:
            if rid not in requirements:
                report.error(f"Test case {tid}: verifies non-existent requirement {rid}")
            elif tid not in (requirements[rid].get("verified_by") or []):
                report.error(f"Test case {tid} verifies {rid}, but {rid} does not list it back")
    for rid, req in requirements.items():
        for parent in req.get("derives_from") or []:
            if parent not in requirements:
                report.error(f"Requirement {rid}: derives_from non-existent requirement {parent}")
    for risk_id, risk in risks.items():
        for rid in risk.get("linked_requirements") or []:
            if rid not in requirements:
                report.error(f"Risk {risk_id}: linked_requirements references non-existent requirement {rid}")


def check_coverage_and_phasing(requirements, test_cases, report):
    for rid, req in requirements.items():
        tids = req.get("verified_by") or []
        if not tids:
            report.error(f"Requirement {rid}: nothing verifies it")
            continue
        tcs = [test_cases[t] for t in tids if t in test_cases]
        if not tcs:
            continue

        if req["verification_method"] not in {t["method"] for t in tcs}:
            report.error(
                f"Requirement {rid}: verification_method {req['verification_method']} is not the "
                f"method of any test that verifies it ({[(t['id'], t['method']) for t in tcs]})"
            )

        req_phase = PHASE_ORDER.get(req.get("phase"), 99)
        if not any(PHASE_ORDER.get(t.get("phase"), 99) <= req_phase for t in tcs):
            report.error(
                f"Requirement {rid} ({req.get('phase')}): no test case scheduled at or before its own "
                f"phase — it would ship unverified ({[(t['id'], t['phase']) for t in tcs]})"
            )

        for parent in req.get("derives_from") or []:
            if parent in requirements:
                if PHASE_ORDER.get(requirements[parent].get("phase"), 99) > req_phase:
                    report.error(
                        f"Requirement {rid} ({req.get('phase')}) derives from {parent} "
                        f"({requirements[parent].get('phase')}), which ships later"
                    )

        if req.get("verification_status") == "PASSED":
            statuses = [t["status"] for t in tcs]
            if "PASSED" not in statuses:
                report.error(
                    f"Requirement {rid} claims PASSED but no test that verifies it has passed ({statuses})"
                )


def check_automation_coverage(requirements, test_cases, report):
    """The owner's rule: every high-risk requirement gets a test that runs
    during development. A CRITICAL or HIGH requirement must be covered by at
    least one AUTOMATED or HYBRID test case, unless it carries an explicit
    automation_exempt_reason saying why a machine cannot judge it."""
    for rid, req in requirements.items():
        if req.get("priority") not in ("CRITICAL", "HIGH"):
            continue
        tcs = [test_cases[t] for t in (req.get("verified_by") or []) if t in test_cases]
        automated = [t for t in tcs if t.get("automation") in ("AUTOMATED", "HYBRID")]
        if automated:
            if req.get("automation_exempt_reason"):
                report.warn(
                    f"Requirement {rid}: carries automation_exempt_reason but is already covered "
                    f"by automated tests {[t['id'] for t in automated]} — the exemption is stale"
                )
            continue
        if not req.get("automation_exempt_reason"):
            report.error(
                f"Requirement {rid} ({req['priority']}): no AUTOMATED or HYBRID test case and no "
                f"automation_exempt_reason (has {[(t['id'], t.get('automation')) for t in tcs]})"
            )


def check_workstream_logs(requirements, report):
    """Each chain has an append-only log the agents working it write to. The
    log states which requirements it covers; that claim is checked against the
    requirements tree rather than trusted, the same way every other rollup is."""
    chains_in_use = {}
    for rid, req in requirements.items():
        chains_in_use.setdefault(req.get("chain"), set()).add(rid)

    for chain, ids in sorted(chains_in_use.items()):
        log_path = WORKSTREAMS_DIR / str(chain) / "log.yaml"
        if not log_path.exists():
            report.error(f"Chain {chain}: no collaboration log at {log_path.relative_to(HERE)}")
            continue
        raw = log_path.read_text(encoding="utf-8")
        # An entry that ALIASES the header list is an entry that silently
        # changes when the header changes. That is exactly what "append-only,
        # never rewrite an existing entry" forbids, and it had already rewritten
        # the oldest entry of two chains before anyone noticed - by hand nobody
        # broke the rule; the YAML serialiser did (D-CHOMP-067).
        if "*id" in raw or "&id" in raw:
            report.error(
                f"Chain {chain}: log uses a YAML anchor/alias. Every entry must "
                f"carry its own literal requirements list, frozen at write time"
            )
        log = load_yaml(log_path)
        if log.get("chain") != chain:
            report.error(f"{log_path.name} in {chain}/: declares chain {log.get('chain')!r}")
        stated = log.get("requirement_count")
        if stated != len(ids):
            report.error(
                f"Chain {chain}: log states requirement_count {stated}, tree says {len(ids)}"
            )
        listed = set(log.get("requirements") or [])
        if listed != ids:
            missing, extra = sorted(ids - listed), sorted(listed - ids)
            report.error(
                f"Chain {chain}: log's requirement list disagrees with the tree "
                f"(missing {missing}, unknown {extra})"
            )
        for n, entry in enumerate(log.get("entries") or [], 1):
            where = f"Chain {chain} entry {n}"
            for field in LOG_ENTRY_REQUIRED:
                if not entry.get(field):
                    report.error(f"{where}: missing required field '{field}'")
            if entry.get("action") and entry["action"] not in LOG_ENTRY_ACTIONS:
                report.error(f"{where}: action {entry['action']!r} not in {sorted(LOG_ENTRY_ACTIONS)}")
            if entry.get("status") and entry["status"] not in LOG_STATUSES:
                report.error(f"{where}: status {entry['status']!r} not in {sorted(LOG_STATUSES)}")
            check_date(entry, "date", f"entry {n}", f"Chain {chain}", report)
            for rid in entry.get("requirements") or []:
                if rid not in requirements:
                    report.error(f"{where}: cites non-existent requirement {rid}")
                elif requirements[rid].get("chain") != chain:
                    report.error(
                        f"{where}: cites {rid}, which belongs to "
                        f"{requirements[rid].get('chain')}, not this chain"
                    )
        if not log.get("entries"):
            report.error(f"Chain {chain}: log has no entries")


def check_delivery_claims(requirements, report):
    """A requirement a chain log calls DELIVERED, still sitting at
    verification_status NOT_STARTED.

    The trace is bidirectional and validated, and it still could not see this:
    every check here asks whether the records agree with EACH OTHER, and none
    asks whether they agree with the game. Thirty-odd commits of shipped
    gameplay went in while all 69 requirements read NOT_STARTED, which is the
    tree quietly ceasing to describe anything (D-CHOMP-067).

    A warning, not an error. Delivered is not verified, and pretending
    otherwise would trade one lie for a shorter one - but the gap should be
    visible on every run rather than discovered by reading YAML for an hour.
    """
    delivered = {}
    for chain_dir in sorted(WORKSTREAMS_DIR.iterdir()):
        log_path = chain_dir / "log.yaml"
        if not log_path.is_file():
            continue
        for entry in load_yaml(log_path).get("entries") or []:
            if entry.get("action") == "DELIVERED":
                for rid in entry.get("requirements") or []:
                    delivered.setdefault(rid, entry.get("date"))

    stale = sorted(rid for rid, _ in delivered.items()
                   if rid in requirements
                   and requirements[rid].get("verification_status") == "NOT_STARTED")
    if stale:
        report.warn(
            f"{len(stale)} requirement(s) are DELIVERED in a chain log but still "
            f"read verification_status NOT_STARTED: {', '.join(stale[:8])}"
            + (" ..." if len(stale) > 8 else "")
        )


def check_freshness(decisions, report):
    """The dashboard's as_of against the newest record anywhere.

    Its own header calls it a rollup "checked against the records on every
    validate run", and the counts were - the DATE never was. It sat at
    2026-08-25 through two days of shipping, next to next_actions telling the
    reader to drive a map that no longer exists (D-CHOMP-067).
    """
    newest, source = None, None
    for d in decisions.values():
        if d.get("date") and (newest is None or str(d["date"]) > newest):
            newest, source = str(d["date"]), d.get("id")
    for chain_dir in sorted(WORKSTREAMS_DIR.iterdir()):
        log_path = chain_dir / "log.yaml"
        if not log_path.is_file():
            continue
        for entry in load_yaml(log_path).get("entries") or []:
            if entry.get("date") and (newest is None or str(entry["date"]) > newest):
                newest, source = str(entry["date"]), chain_dir.name
    if newest is None:
        return
    as_of = str(load_yaml(DASHBOARD_FILE).get("as_of") or "")
    if as_of < newest:
        report.error(
            f"dashboard: as_of {as_of or 'unset'} is older than the newest record "
            f"({newest}, from {source}). Update the dashboard with the work, not after it"
        )


# Topics, assigned by keyword against the title. Nine buckets cover all 66.
DECISION_TOPICS = [
    ("controls",  ("steer", "control", "drive", "driving", "input", "touch", "stick", "thumb")),
    ("camera",    ("camera", "occlusion", "readout")),
    ("vehicle",   ("chassis", "vehicle", "kart", "wheel", "model", "mount", "avatar")),
    ("map",       ("maze", "map", "level", "ring", "wall", "arena", "garage", "sanctuar")),
    ("ghosts",    ("ghost", "wave", "guardian")),
    ("items",     ("item", "weapon", "cannon", "bomb", "shield", "belt", "jet")),
    ("economy",   ("bank", "dollar", "shop", "price", "purchase", "upgrade", "charge", "pellet", "robux", "profile")),
    ("hud",       ("hud", "readable", "icon", "label", "display", "screen")),
]


def write_decision_index(decisions, report):
    """Generate 06_decisions/INDEX.md from the records.

    GENERATED, like verified_by, and for the same reason: a handwritten index
    of 66 decisions is a number that drifts, and README.md proved it by
    claiming 11 (D-CHOMP-067). An agent reads this plus the ACTIVE entries for
    its topic - about five - instead of 1,800 lines of interleaved design
    decisions and bug post-mortems.
    """
    buckets = {}
    for d in sorted(decisions.values(), key=lambda x: x["id"]):
        title = str(d.get("title", "")).lower()
        topic = next((name for name, words in DECISION_TOPICS
                      if any(w in title for w in words)), "process")
        buckets.setdefault(topic, []).append(d)

    lines = [
        "# Decision index",
        "",
        "**Generated by `validate.py`. Do not edit.**",
        "",
        "Status is `ACTIVE` unless something supersedes it: `PARTIAL` means a",
        "named half was replaced and the rest still rules, `SUPERSEDED` means all",
        "of it was, `VOID` means the number was never used. Read the ACTIVE",
        "entries for your topic before writing code that touches it.",
        "",
        f"{len(decisions)} decisions.",
        "",
    ]
    for topic in sorted(buckets):
        lines.append(f"## {topic}")
        lines.append("")
        for d in buckets[topic]:
            status = d.get("status", "ACTIVE")
            mark = f"**{d['id']}**" if status == "ACTIVE" else d["id"]
            note = ""
            if d.get("superseded_by"):
                by = ", ".join((r.get("id") if isinstance(r, dict) else r)
                               for r in d["superseded_by"])
                note = f" — superseded by {by}"
            lines.append(f"- {mark} `{status}` {d.get('date')} — {d.get('title')}{note}")
        lines.append("")

    text = chr(10).join(lines)
    path = HERE / "06_decisions" / "INDEX.md"
    existing = path.read_text(encoding="utf-8") if path.exists() else None
    if existing != text:
        path.write_text(text, encoding="utf-8", newline=chr(10))
        report.note(f"regenerated {path.relative_to(HERE)} ({len(decisions)} decisions)")


def check_dashboard(requirements, test_cases, risks, decisions, report):
    """Never trust a handwritten total."""
    if not DASHBOARD_FILE.exists():
        report.error(f"Missing {DASHBOARD_FILE.relative_to(HERE)}")
        return
    d = load_yaml(DASHBOARD_FILE)

    def tally(items, key):
        out = {}
        for i in items:
            out[i.get(key)] = out.get(i.get(key), 0) + 1
        return out

    def compare(label, stated, computed):
        if stated is None:
            report.error(f"dashboard: {label} missing")
        elif stated != computed:
            report.error(f"dashboard: {label} states {stated}, records say {computed}")

    req_d = d.get("requirements") or {}
    compare("requirements.total", req_d.get("total"), len(requirements))
    compare("requirements.by_level", req_d.get("by_level"), tally(requirements.values(), "level"))
    compare("requirements.by_phase", req_d.get("by_phase"), tally(requirements.values(), "phase"))
    compare("requirements.by_priority", req_d.get("by_priority"), tally(requirements.values(), "priority"))
    compare("requirements.by_chain", req_d.get("by_chain"), tally(requirements.values(), "chain"))
    compare("requirements.automation_exempt", req_d.get("automation_exempt"),
            sum(1 for r in requirements.values() if r.get("automation_exempt_reason")))

    tc_d = d.get("test_cases") or {}
    compare("test_cases.total", tc_d.get("total"), len(test_cases))
    compare("test_cases.by_automation", tc_d.get("by_automation"), tally(test_cases.values(), "automation"))
    compare("test_cases.by_phase", tc_d.get("by_phase"), tally(test_cases.values(), "phase"))

    risk_d = d.get("risks") or {}
    compare("risks.total", risk_d.get("total"), len(risks))
    compare("risks.open", risk_d.get("open"), sum(1 for r in risks.values() if r.get("status") == "OPEN"))
    compare("risks.closed", risk_d.get("closed"), sum(1 for r in risks.values() if r.get("status") == "CLOSED"))
    compare("risks.by_severity", risk_d.get("by_severity"), tally(risks.values(), "severity"))

    compare("decisions.total", (d.get("decisions") or {}).get("total"), len(decisions))


def check_allocations(requirements, report):
    for rid, req in requirements.items():
        target = req.get("allocated_to")
        if not target:
            continue
        root = str(target).split("/")[0]
        if root not in ROBLOX_SERVICES:
            report.error(
                f"Requirement {rid}: allocated_to '{target}' does not start from a Roblox service "
                f"(got '{root}')"
            )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    report = Report()

    for f in [REQUIREMENTS_FILE, TEST_CASES_FILE, RISK_REGISTER_FILE, DECISION_LOG_FILE]:
        if not f.exists():
            report.error(f"Missing expected file: {f}")
    if not report.ok:
        _print(report, args.quiet)
        sys.exit(1)

    requirements = validate_requirements(report)
    test_cases = validate_test_cases(report)
    risks = validate_risks(report)
    decisions = validate_decisions(report)

    check_reciprocity(requirements, test_cases, risks, report)
    check_coverage_and_phasing(requirements, test_cases, report)
    check_allocations(requirements, report)
    check_automation_coverage(requirements, test_cases, report)
    check_workstream_logs(requirements, report)
    for f in [REQUIREMENTS_FILE, TEST_CASES_FILE, RISK_REGISTER_FILE,
              DECISION_LOG_FILE, DASHBOARD_FILE]:
        check_duplicate_keys(f, report)
    write_decision_index(decisions, report)
    check_delivery_claims(requirements, report)
    check_freshness(decisions, report)
    check_dashboard(requirements, test_cases, risks, decisions, report)

    by_phase = {}
    for r in requirements.values():
        by_phase[r.get("phase")] = by_phase.get(r.get("phase"), 0) + 1
    report.note(f"{len(requirements)} requirements ({', '.join(f'{k}: {v}' for k, v in sorted(by_phase.items()))})")
    auto = sum(1 for t in test_cases.values() if t.get("automation") in ("AUTOMATED", "HYBRID"))
    report.note(f"{len(test_cases)} test cases ({auto} automated or hybrid), "
                f"{len(risks)} risks, {len(decisions)} decisions")
    high = [r for r in requirements.values() if r.get("priority") in ("CRITICAL", "HIGH")]
    exempt = [r["id"] for r in high if r.get("automation_exempt_reason")]
    report.note(f"{len(high) - len(exempt)} of {len(high)} high/critical requirements carry an "
                f"automated test; {len(exempt)} exempt with a recorded reason ({', '.join(exempt)})")

    _print(report, args.quiet)
    sys.exit(0 if report.ok else 1)


def _print(report, quiet):
    if not quiet:
        for m in report.info:
            print(f"  ok: {m}")
        for m in report.warnings:
            print(f"WARN: {m}")
    for m in report.errors:
        print(f"FAIL: {m}")
    print()
    print(f"{'PASS' if report.ok else 'FAIL'} — {len(report.errors)} errors, {len(report.warnings)} warnings")


if __name__ == "__main__":
    main()
