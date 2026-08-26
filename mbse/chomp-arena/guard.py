#!/usr/bin/env python3
"""
Chomp Arena static load-order guard.

Two faults have now cost four playtests between them, and both are structural
rather than behavioural — a machine could have caught either in under a second.

  * D-CHOMP-021: nothing created the RemoteEvents any more, so a client waiting
    on them waited forever. Because InputController waited at the top of its
    file, ALL steering silently died. It surfaced as an unrelated `Infinite
    yield` warning rather than as "the controls do not work", which is exactly
    why it survived a playtest.
  * D-CHOMP-024: the fix declared a folder named `Remotes` while
    src/ReplicatedStorage/Remotes.lua already syncs as a ModuleScript of the
    same name. Two children of ReplicatedStorage, one name, and WaitForChild is
    free to return either. It returned the module, which has no children, so the
    lookup below it timed out. Same disguise, three more playtests.

The shared shape: a thing that does not exist does not announce itself as
missing. It announces itself as some unrelated feature quietly not working. So
this runs at BUILD time, against the built place rather than against the source,
because the built place is what the game actually loads.

  Check 1  No two children of one parent share a name.
  Check 2  Every WaitForChild target that can be resolved statically exists in
           the built tree.
  Check 3  Every chassis spec, once scaled by ChompConfig, still fits inside
           Budgets.VehicleBounds.
  Check 4  No local function is called before the line that defines it.

What it deliberately does NOT do: catch runtime behaviour. D-CHOMP-025 — the
physics solver reverting per-frame CFrame writes — was invisible to any static
check, and D-CHOMP-026 was a design mistake. This removes one category of wasted
playtest; it does not remove playtesting.

Usage:
    python guard.py               # builds the place first, then checks it
    python guard.py --no-build    # check the existing build/ChompArena.rbxlx
    python guard.py --quiet       # errors only
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLACE = HERE / "build" / "ChompArena.rbxlx"
SRC = HERE / "src"

# Instances the engine creates per-player at runtime. They are never in the
# built place and waiting on them is correct, so a receiver that resolves to one
# of these is skipped rather than reported.
ENGINE_PROVIDED = {
    "PlayerScripts", "PlayerGui", "Backpack", "PlayerModule", "Character",
    "Humanoid", "HumanoidRootPart", "Animate", "Head", "Torso", "UpperTorso",
}


class Report:
    def __init__(self):
        self.info, self.warnings, self.errors = [], [], []

    def note(self, m):
        self.info.append(m)

    def warn(self, m):
        self.warnings.append(m)

    def fail(self, m):
        self.errors.append(m)

    @property
    def ok(self):
        return not self.errors


# ── The built place ─────────────────────────────────────────────────────

def _name_of(item):
    for prop in item.findall("./Properties/*"):
        if prop.get("name") == "Name":
            return prop.text or ""
    return ""


def load_place(path):
    """Returns {path_tuple: (name, class)} for every instance in the place."""
    root = ET.parse(path).getroot()
    tree = {}

    def walk(item, prefix):
        name = _name_of(item) or item.get("class", "?")
        here = prefix + (name,)
        tree[here] = (name, item.get("class", "?"))
        for child in item.findall("./Item"):
            walk(child, here)

    for item in root.findall("./Item"):
        walk(item, ())
    return tree


def check_duplicate_names(place_path, report):
    """Check 1 — no two children of one parent share a name. This is D-CHOMP-024."""
    root = ET.parse(place_path).getroot()
    collisions = 0

    def walk(item, path):
        nonlocal collisions
        seen = {}
        for child in item.findall("./Item"):
            name = _name_of(child) or "?"
            seen.setdefault(name, []).append(child.get("class", "?"))
        for name, classes in seen.items():
            if len(classes) > 1:
                collisions += 1
                where = ".".join(path) if path else "(DataModel)"
                report.fail(
                    f"duplicate child name: {where}.{name} exists {len(classes)} times "
                    f"as {', '.join(classes)}. WaitForChild(\"{name}\") may return either "
                    f"— this is the D-CHOMP-024 fault"
                )
        for child in item.findall("./Item"):
            walk(child, path + ((_name_of(child) or "?"),))

    for item in root.findall("./Item"):
        walk(item, ((_name_of(item) or item.get("class", "?")),))

    if not collisions:
        report.note("no duplicate child names anywhere in the built place")


# ── The source ──────────────────────────────────────────────────────────

SERVICE_LOCAL = re.compile(r'^\s*local\s+(\w+)\s*=\s*game:GetService\(\s*"([^"]+)"\s*\)')
STRING_LIST = re.compile(r'^\s*local\s+(\w+)\s*=\s*\{\s*((?:"[^"]*"\s*,?\s*)+)\}')
IPAIRS_LOOP = re.compile(r'for\s+[\w_]+\s*,\s*(\w+)\s+in\s+ipairs\(\s*(\w+)\s*\)')
# `local X = <expr>` where expr is a WaitForChild chain we may be able to resolve
ALIAS = re.compile(r'^\s*local\s+(\w+)\s*=\s*(\w+)((?::WaitForChild\([^)]*\))+)')
WFC_CALL = re.compile(r'(\w+)((?::WaitForChild\(\s*(?:"[^"]*"|\'[^\']*\'|\w+)\s*(?:,[^)]*)?\))+)')
WFC_ARG = re.compile(r':WaitForChild\(\s*(?:"([^"]*)"|\'([^\']*)\'|(\w+))\s*(?:,[^)]*)?\)')


def scan_file(path, place, report):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    rel = path.relative_to(HERE)

    services, aliases, lists, loopvars = {}, {}, {}, {}

    for line in lines:
        m = SERVICE_LOCAL.match(line)
        if m:
            services[m.group(1)] = (m.group(2),)
        m = STRING_LIST.match(line)
        if m:
            lists[m.group(1)] = re.findall(r'"([^"]*)"', m.group(2))
    # `workspace` is a global alias for the Workspace service
    services.setdefault("workspace", ("Workspace",))

    for line in lines:
        for var, table in IPAIRS_LOOP.findall(line):
            if table in lists:
                loopvars[var] = lists[table]

    def resolve_receiver(name):
        if name in services:
            return services[name]
        if name in aliases:
            return aliases[name]
        return None

    def chain_targets(chain):
        """Yields the literal names in a WaitForChild chain, or None if dynamic."""
        for lit_d, lit_s, ident in WFC_ARG.findall(chain):
            if lit_d or lit_s:
                yield [lit_d or lit_s]
            elif ident in loopvars:
                yield loopvars[ident]          # the D-CHOMP-021 pattern
            else:
                yield None                     # genuinely dynamic

    checked = unresolved = 0

    for lineno, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("--"):
            continue

        # learn aliases as we go, so `local f = RS:WaitForChild("X")` then
        # `f:WaitForChild("Y")` resolves to RS.X.Y
        am = ALIAS.match(line)

        for recv, chain in WFC_CALL.findall(line):
            base = resolve_receiver(recv)
            if base is None:
                unresolved += 1
                continue

            path = base
            for step in chain_targets(chain):
                if step is None:
                    unresolved += 1
                    path = None
                    break
                # a step may be several candidate names (a loop over a list)
                nxt = None
                for candidate in step:
                    probe = path + (candidate,)
                    if probe in place:
                        nxt = probe if len(step) == 1 else path
                    else:
                        parent = ".".join(path)
                        scope = "module scope" if not line[:1].isspace() else f"line {lineno}"
                        report.fail(
                            f"{rel}:{lineno} ({scope}): WaitForChild(\"{candidate}\") on "
                            f"{parent} - no such child in the built place. This yields "
                            f"forever and takes the rest of the file with it"
                        )
                if len(step) == 1 and nxt:
                    path = nxt
                checked += 1

            if am and path:
                aliases[am.group(1)] = path

    return checked, unresolved


def check_waitforchild(place, report):
    """Check 2 — every statically resolvable WaitForChild target exists."""
    total = unresolved = 0
    for path in sorted(SRC.rglob("*.lua")):
        c, u = scan_file(path, place, report)
        total += c
        unresolved += u
    report.note(f"{total} WaitForChild target(s) resolved against the built place")
    if unresolved:
        report.note(
            f"{unresolved} not statically resolvable (engine-provided instances such as "
            f"{', '.join(sorted(list(ENGINE_PROVIDED)[:4]))}, or a computed name) - "
            f"these are not checked and are not claimed to be safe"
        )


# ── Entry point ─────────────────────────────────────────────────────────

# ── The vehicle ─────────────────────────────────────────────────────────

VEC3 = re.compile(r'Vector3\.new\(([^)]*)\)')
NUMBER = re.compile(r'([A-Za-z]\w*)\s*=\s*([0-9.]+)')


def _config_numbers(text, table):
    """Pull `Name = number` pairs out of one ChompConfig.<table> block."""
    start = text.find(f"ChompConfig.{table} = {{")
    if start < 0:
        return {}
    end = text.find(chr(10) + "}", start)
    return {k: float(v) for k, v in NUMBER.findall(text[start:end])}


def check_vehicle_bounds(report):
    """Check 3 — a scaled chassis must still fit the contract.

    This exists because it already happened. Wheels were scaled on all three
    axes, which widened the kart past Budgets.VehicleBounds; VehicleFactory
    correctly refused to build it, and the vehicle simply stopped appearing with
    only a warn in the log to say why (D-CHOMP-052). The arithmetic is cheap and
    the failure is silent, which is exactly the trade this guard exists to make.
    """
    config_path = SRC / "ReplicatedStorage" / "ChompConfig.lua"
    specs_dir = SRC / "ServerStorage" / "ChompTools" / "VehicleSpecs"
    if not config_path.exists() or not specs_dir.exists():
        return

    config = config_path.read_text(encoding="utf-8")
    vehicle = _config_numbers(config, "Vehicle")
    scale = vehicle.get("Scale", 1.0)
    wheel_scale = vehicle.get("WheelScale", 1.0)

    bounds_match = re.search(r'VehicleBounds\s*=\s*Vector3\.new\(([^)]*)\)', config)
    if not bounds_match:
        report.warn("Budgets.VehicleBounds not found; vehicle bounds not checked")
        return
    limit = [float(v) for v in bounds_match.group(1).split(",")]

    entry = re.compile(
        r'name\s*=\s*"([^"]+)".*?size\s*=\s*Vector3\.new\(([^)]*)\)'
        r'.*?offset\s*=\s*Vector3\.new\(([^)]*)\)', re.S)

    checked = 0
    for spec_path in sorted(specs_dir.glob("*.lua")):
        text = spec_path.read_text(encoding="utf-8")
        parts = entry.findall(text)
        if not parts:
            continue
        lo = [9e9] * 3
        hi = [-9e9] * 3
        for name, size, offset in parts:
            s_ = [float(v) * scale for v in size.split(",")]
            o_ = [float(v) * scale for v in offset.split(",")]
            if "Wheel" in name or "Hub" in name:
                # diameter only: X is the tyre's width
                s_ = [s_[0], s_[1] * wheel_scale, s_[2] * wheel_scale]
            for i in range(3):
                lo[i] = min(lo[i], o_[i] - s_[i] / 2)
                hi[i] = max(hi[i], o_[i] + s_[i] / 2)
        extent = [hi[i] - lo[i] for i in range(3)]
        checked += 1
        for i, axis in enumerate("XYZ"):
            if extent[i] > limit[i] + 1e-6:
                report.fail(
                    f"{spec_path.name} scaled by {scale} (wheels x{wheel_scale}) is "
                    f"{extent[i]:.2f} on {axis}, over Budgets.VehicleBounds {limit[i]}. "
                    f"VehicleFactory will refuse to build it and the kart will not appear"
                )
    if checked:
        report.note(f"{checked} chassis spec(s) fit VehicleBounds at scale {scale}")


# ── Use before definition ───────────────────────────────────────────────

LOCAL_FUNCTION = re.compile(r'^local function (\w+)', re.M)
FORWARD_DECL = re.compile(r'^local (\w+)\s*(?::[^=]+)?$', re.M)


def check_use_before_define(report):
    """Check 4 - a local function called above its own definition.

    In Luau `local function f` is only in scope from its own line onward, so a
    call above it silently resolves to a nil global and fails at RUN time, not
    load time. Editing a large file by replacing a span is exactly how this
    happens: a block moves, the calls do not, and nothing complains until
    someone plays the game and one feature quietly does nothing.

    That is precisely what happened to the bomb and the lock-on, so it becomes a
    check rather than a lesson.
    """
    offenders = 0
    scanned = 0
    for path in sorted(SRC.rglob("*.lua")):
        text = path.read_text(encoding="utf-8")
        scanned += 1
        forward = {m.group(1) for m in FORWARD_DECL.finditer(text)}
        for match in LOCAL_FUNCTION.finditer(text):
            name = match.group(1)
            if name in forward:
                continue  # forward-declared, so a call above it is legitimate
            before = text[: match.start()]
            call = re.search(r'(?<![\w.:])' + re.escape(name) + r'\s*\(', before)
            if not call:
                continue
            line = before.count(chr(10), 0, call.start()) + 1
            stripped = before.splitlines()[line - 1].strip()
            if stripped.startswith("--"):
                continue
            offenders += 1
            report.fail(
                f"{path.relative_to(HERE)}:{line}: calls {name}() above the "
                f"'local function {name}' that defines it. In Luau that resolves "
                f"to a nil global and fails at runtime"
            )
    if not offenders:
        report.note(f"no local function is used before its definition ({scanned} files)")


def build_place(report):
    rojo = shutil.which("rojo")
    if not rojo:
        guess = Path(os.environ.get("LOCALAPPDATA", "")) / (
            "Microsoft/WinGet/Packages/Rojo.Rojo_Microsoft.Winget.Source_8wekyb3d8bbwe/rojo.exe")
        rojo = str(guess) if guess.exists() else None
    if not rojo:
        report.warn("rojo not found on PATH; checking the existing build instead of a fresh one")
        return
    r = subprocess.run([rojo, "build", "--output", str(PLACE)],
                       cwd=HERE, capture_output=True, text=True)
    if r.returncode != 0:
        report.fail(f"rojo build failed: {(r.stderr or r.stdout).strip()}")
    else:
        report.note("built the place from source before checking it")


def main():
    ap = argparse.ArgumentParser(description="Static load-order guard for Chomp Arena.")
    ap.add_argument("--no-build", action="store_true", help="check the existing place file")
    ap.add_argument("--quiet", action="store_true", help="errors only")
    args = ap.parse_args()

    report = Report()

    if not args.no_build:
        build_place(report)

    if not PLACE.exists():
        report.fail(f"no place file at {PLACE.relative_to(HERE)} — run rojo build first")
        _print(report, args.quiet)
        sys.exit(1)

    check_duplicate_names(PLACE, report)
    check_vehicle_bounds(report)
    check_use_before_define(report)
    place = load_place(PLACE)
    report.note(f"{len(place)} instances in the built place")
    check_waitforchild(place, report)

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
    print(f"{'PASS' if report.ok else 'FAIL'} - {len(report.errors)} errors, "
          f"{len(report.warnings)} warnings")


if __name__ == "__main__":
    main()
