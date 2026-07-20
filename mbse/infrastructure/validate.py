#!/usr/bin/env python3
"""
Infrastructure MBSE validator.

Built in response to a review finding that this tree's model (and its older
sibling, Medha/MBSE/tools/RSI/) risks the same failure mode: atomic YAML
records are trustworthy, but handwritten rollup numbers (dashboard totals,
risk open/closed counts, trace summaries) drift from them silently and
nothing catches it. That review independently verified real discrepancies in
the RSI tree (e.g. a dashboard claiming risks.open: 0 against a risk
register with 8 real OPEN entries) purely by reading the files by hand.

This script is that check, automated, for THIS tree. Principle: store facts
once, calculate every count. It never trusts a handwritten total — it
recomputes every count from the individual records and fails loudly on any
mismatch, broken reference, schema violation, or duplicate ID.

Requires PyYAML (`pip install pyyaml`) — unlike crawler.py, this is a
dev-time linter, not something that needs to run dependency-free on an
arbitrary remote machine.

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
REPO_ROOT = HERE.parent.parent  # C:\Qrx_MARK_T2

REQUIREMENTS_FILE = HERE / "02_requirements" / "requirements.yaml"
TEST_CASES_FILE = HERE / "04_verification" / "test_cases.yaml"
RISK_REGISTER_FILE = HERE / "05_risks" / "risk_register.yaml"
DECISION_LOG_FILE = HERE / "06_decisions" / "decision_log.yaml"

# ── Schema constraints (mirrors Medha MBSE _framework/schemas/*.yaml) ──────

REQ_ENUMS = {
    "level": {"L1_stakeholder", "L2_system"},
    "status": {"DRAFT", "APPROVED", "DEFERRED", "DELETED"},
    "priority": {"CRITICAL", "HIGH", "MEDIUM", "LOW"},
    "verification_status": {"NOT_STARTED", "IN_PROGRESS", "PASSED", "FAILED", "DEFERRED", "N/A"},
    "verification_method": {"TEST", "ANALYSIS", "DEMONSTRATION", "INSPECTION"},
    "phase": {"v1", "v2", "v3"},
}
REQ_REQUIRED_FIELDS = [
    "id", "title", "shall_statement", "level", "status", "priority",
    "verification_status", "verification_method", "phase",
    "created_date", "last_modified", "author",
]
REQ_ID_RE = re.compile(r"^INFRA-(STK|SYS)-\d{3}$")

TC_ENUMS = {
    "type": {"UNIT", "INTEGRATION", "SYSTEM", "ACCEPTANCE"},
    "method": {"TEST", "ANALYSIS", "DEMONSTRATION", "INSPECTION"},
    "status": {"NOT_STARTED", "IN_PROGRESS", "PASSED", "FAILED", "BLOCKED"},
    "phase": {"v1", "v2", "v3"},
}
TC_REQUIRED_FIELDS = [
    "id", "title", "verifies", "type", "method", "preconditions",
    "test_data", "procedure", "expected_result", "pass_criteria",
    "status", "phase",
]
TC_ID_RE = re.compile(r"^INFRA-TC-\d{3}$")

RISK_ENUMS = {
    "severity": {"CRITICAL", "HIGH", "MEDIUM", "LOW"},
    "status": {"OPEN", "CLOSED"},
}
RISK_REQUIRED_FIELDS = ["id", "title", "description", "severity", "status", "detected"]
RISK_ID_RE = re.compile(r"^RISK-INFRA-\d{3}$")

DECISION_REQUIRED_FIELDS = ["id", "date", "title", "decision"]
DECISION_ID_RE = re.compile(r"^D-INFRA-\d{3}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# Non-path prose values seen in satisfied_by that shouldn't be checked as files
SATISFIED_BY_SKIP_PATTERNS = [
    "vercel project env vars", "manual", "systemd unit files", "hetzner cx22",
    "upstash rest", "railway", "external process",
]


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.info = []

    def error(self, msg):
        self.errors.append(msg)

    def warn(self, msg):
        self.warnings.append(msg)

    def note(self, msg):
        self.info.append(msg)

    @property
    def ok(self):
        return not self.errors


def load_yaml(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def check_required_fields(record, required, rid, kind, report):
    for field in required:
        if field not in record or record[field] in (None, ""):
            report.error(f"{kind} {rid}: missing required field '{field}'")


def check_enums(record, enums, rid, kind, report):
    for field, allowed in enums.items():
        if field in record and record[field] is not None and record[field] not in allowed:
            report.error(f"{kind} {rid}: field '{field}' = {record[field]!r} not in allowed set {sorted(allowed)}")


def check_date(record, field, rid, kind, report):
    v = record.get(field)
    if v is None:
        return
    v = str(v)
    if not DATE_RE.match(v):
        report.error(f"{kind} {rid}: field '{field}' = {v!r} is not YYYY-MM-DD")


def validate_requirements(report):
    data = load_yaml(REQUIREMENTS_FILE)
    reqs = data.get("requirements", [])
    seen_ids = {}
    for r in reqs:
        rid = r.get("id", "<no id>")
        check_required_fields(r, REQ_REQUIRED_FIELDS, rid, "Requirement", report)
        check_enums(r, REQ_ENUMS, rid, "Requirement", report)
        check_date(r, "created_date", rid, "Requirement", report)
        check_date(r, "last_modified", rid, "Requirement", report)
        if not REQ_ID_RE.match(rid):
            report.error(f"Requirement {rid}: ID doesn't match INFRA-(STK|SYS)-NNN")
        if rid in seen_ids:
            report.error(f"Requirement {rid}: duplicate ID (also used by another entry)")
        seen_ids[rid] = r
    return {r["id"]: r for r in reqs if "id" in r}


def validate_test_cases(report):
    data = load_yaml(TEST_CASES_FILE)
    tcs = data.get("test_cases", [])
    seen_ids = {}
    for tc in tcs:
        tid = tc.get("id", "<no id>")
        check_required_fields(tc, TC_REQUIRED_FIELDS, tid, "Test case", report)
        check_enums(tc, TC_ENUMS, tid, "Test case", report)
        if not TC_ID_RE.match(tid):
            report.error(f"Test case {tid}: ID doesn't match INFRA-TC-NNN")
        if tid in seen_ids:
            report.error(f"Test case {tid}: duplicate ID")
        seen_ids[tid] = tc
    return {tc["id"]: tc for tc in tcs if "id" in tc}


def validate_risks(report):
    data = load_yaml(RISK_REGISTER_FILE)
    risks = data.get("risks", [])
    seen_ids = {}
    for risk in risks:
        rid = risk.get("id", "<no id>")
        check_required_fields(risk, RISK_REQUIRED_FIELDS, rid, "Risk", report)
        check_enums(risk, RISK_ENUMS, rid, "Risk", report)
        check_date(risk, "detected", rid, "Risk", report)
        if not RISK_ID_RE.match(rid):
            report.error(f"Risk {rid}: ID doesn't match RISK-INFRA-NNN")
        if rid in seen_ids:
            report.error(f"Risk {rid}: duplicate ID")
        seen_ids[rid] = risk

    # The core finding from the review: don't trust the handwritten totals.
    computed_open = sum(1 for r in risks if r.get("status") == "OPEN")
    computed_closed = sum(1 for r in risks if r.get("status") == "CLOSED")
    stated_open = data.get("open_count")
    stated_closed = data.get("closed_count")
    if stated_open != computed_open:
        report.error(
            f"risk_register.yaml's stated open_count ({stated_open}) does not match "
            f"the computed count of risks with status: OPEN ({computed_open})"
        )
    if stated_closed != computed_closed:
        report.error(
            f"risk_register.yaml's stated closed_count ({stated_closed}) does not match "
            f"the computed count of risks with status: CLOSED ({computed_closed})"
        )
    if stated_open == computed_open and stated_closed == computed_closed:
        report.note(f"risk_register.yaml counts verified correct: {computed_open} open, {computed_closed} closed")

    return {r["id"]: r for r in risks if "id" in r}, computed_open, computed_closed


def validate_decisions(report):
    data = load_yaml(DECISION_LOG_FILE)
    decisions = data.get("decisions", [])
    seen_ids = {}
    for d in decisions:
        did = d.get("id", "<no id>")
        check_required_fields(d, DECISION_REQUIRED_FIELDS, did, "Decision", report)
        check_date(d, "date", did, "Decision", report)
        if not DECISION_ID_RE.match(did):
            report.error(f"Decision {did}: ID doesn't match D-INFRA-NNN")
        if did in seen_ids:
            report.error(f"Decision {did}: duplicate ID")
        seen_ids[did] = d
    return {d["id"]: d for d in decisions if "id" in d}


def check_reciprocity(requirements, test_cases, risks, report):
    # Requirement.verified_by -> must exist as a test case, AND that test
    # case's own `verifies` list must point back (bidirectional, not just
    # one direction — the review specifically flagged this asymmetry).
    for rid, req in requirements.items():
        for tid in req.get("verified_by", []) or []:
            if tid not in test_cases:
                report.error(f"Requirement {rid}: verified_by references non-existent test case {tid}")
            elif rid not in (test_cases[tid].get("verifies") or []):
                report.error(
                    f"Requirement {rid} lists {tid} in verified_by, but {tid}'s own "
                    f"verifies list does not include {rid} back — one-directional trace"
                )

    # Test case.verifies -> must exist as a requirement, AND that requirement's
    # verified_by must list this test case back.
    for tid, tc in test_cases.items():
        for rid in tc.get("verifies", []) or []:
            if rid not in requirements:
                report.error(f"Test case {tid}: verifies references non-existent requirement {rid}")
            elif tid not in (requirements[rid].get("verified_by") or []):
                report.error(
                    f"Test case {tid} lists {rid} in verifies, but {rid}'s own "
                    f"verified_by list does not include {tid} back — one-directional trace"
                )

    # Requirement.derives_from -> must exist as another requirement
    for rid, req in requirements.items():
        for parent in req.get("derives_from", []) or []:
            if parent not in requirements:
                report.error(f"Requirement {rid}: derives_from references non-existent requirement {parent}")

    # Risk.linked_requirements -> must exist
    for risk_id, risk in risks.items():
        for rid in risk.get("linked_requirements", []) or []:
            if rid not in requirements:
                report.error(f"Risk {risk_id}: linked_requirements references non-existent requirement {rid}")


def check_satisfied_by_paths(requirements, report):
    for rid, req in requirements.items():
        for entry in req.get("satisfied_by", []) or []:
            low = entry.lower()
            if any(p in low for p in SATISFIED_BY_SKIP_PATTERNS):
                continue
            # Only check things that look like real repo-relative file/dir paths
            if not re.search(r"[./]", entry):
                continue
            candidate = (REPO_ROOT / entry).resolve()
            if not candidate.exists():
                report.error(f"Requirement {rid}: satisfied_by path does not exist on disk: {entry}")


def check_test_case_status_vs_requirement_status(requirements, test_cases, report):
    """A requirement claiming verification_status: PASSED should have at
    least one linked test case that's actually PASSED — not just linked."""
    for rid, req in requirements.items():
        if req.get("verification_status") != "PASSED":
            continue
        tc_ids = req.get("verified_by") or []
        if not tc_ids:
            continue
        statuses = [test_cases[t]["status"] for t in tc_ids if t in test_cases]
        if statuses and "PASSED" not in statuses:
            report.error(
                f"Requirement {rid} claims verification_status: PASSED but none of its "
                f"linked test cases ({tc_ids}) are themselves status: PASSED (found: {statuses})"
            )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--quiet", action="store_true", help="Only print errors, suppress info/warnings")
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
    risks, computed_open, computed_closed = validate_risks(report)
    decisions = validate_decisions(report)

    check_reciprocity(requirements, test_cases, risks, report)
    check_satisfied_by_paths(requirements, report)
    check_test_case_status_vs_requirement_status(requirements, test_cases, report)

    report.note(f"{len(requirements)} requirements, {len(test_cases)} test cases, {len(risks)} risks, {len(decisions)} decisions loaded")

    _print(report, args.quiet)
    sys.exit(0 if report.ok else 1)


def _print(report, quiet):
    if not quiet:
        for msg in report.info:
            print(f"  ok: {msg}")
        for msg in report.warnings:
            print(f"WARN: {msg}")
    for msg in report.errors:
        print(f"FAIL: {msg}")

    print()
    if report.ok:
        print(f"PASS — 0 errors, {len(report.warnings)} warnings")
    else:
        print(f"FAIL — {len(report.errors)} errors, {len(report.warnings)} warnings")


if __name__ == "__main__":
    main()
