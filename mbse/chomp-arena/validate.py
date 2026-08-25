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
    "rationale", "created_date", "last_modified", "author",
]
REQ_ID_RE = re.compile(r"^CHOMP-(STK|SYS)-\d{3}$")

TC_ENUMS = {
    "type": {"UNIT", "INTEGRATION", "SYSTEM", "ACCEPTANCE"},
    "method": {"TEST", "ANALYSIS", "DEMONSTRATION", "INSPECTION"},
    "status": {"NOT_STARTED", "IN_PROGRESS", "PASSED", "FAILED", "BLOCKED"},
    "phase": set(PHASE_ORDER),
}
TC_REQUIRED_FIELDS = [
    "id", "title", "verifies", "type", "method", "preconditions",
    "test_data", "procedure", "expected_result", "pass_criteria",
    "status", "phase",
]
TC_ID_RE = re.compile(r"^CHOMP-TC-\d{3}$")

RISK_ENUMS = {"severity": {"CRITICAL", "HIGH", "MEDIUM", "LOW"}, "status": {"OPEN", "CLOSED"}}
RISK_REQUIRED_FIELDS = ["id", "title", "description", "severity", "status", "detected"]
RISK_ID_RE = re.compile(r"^RISK-CHOMP-\d{3}$")

DECISION_REQUIRED_FIELDS = ["id", "date", "title", "decision"]
DECISION_ID_RE = re.compile(r"^D-CHOMP-\d{3}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

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
    return {d["id"]: d for d in decisions if "id" in d}


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

    by_phase = {}
    for r in requirements.values():
        by_phase[r.get("phase")] = by_phase.get(r.get("phase"), 0) + 1
    report.note(f"{len(requirements)} requirements ({', '.join(f'{k}: {v}' for k, v in sorted(by_phase.items()))})")
    report.note(f"{len(test_cases)} test cases, {len(risks)} risks, {len(decisions)} decisions")

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
