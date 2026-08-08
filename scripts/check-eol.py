#!/usr/bin/env python3
"""Assert that pinned platform versions are still vendor-supported.

WHY THIS EXISTS, AND WHY IT IS NOT ONE OF THE OTHER SCANNERS
------------------------------------------------------------
Every other scanner in these pipelines answers the same question in a different
place: "does this artefact contain a known vulnerability?" Trivy asks it of the
image, Trivy fs of the dependency tree, Checkov of the Terraform.

None of them answers a different and equally important question: "will this
artefact ever receive another fix?"

Those come apart. A component can be past end-of-life with zero known CVEs — a
clean bill of health from every vulnerability scanner, and no vendor left to
issue an advisory when something is found tomorrow. End-of-life is a LIFECYCLE
fact, sourced from a lifecycle dataset, not from a vulnerability feed.

It matters concretely here. The MongoDB in this environment is installed by a
startup script onto a GCE VM. Nothing else in these pipelines looks at that VM:
the image scan covers the application container, the SBOM stops at the
container's edge, and Checkov reads Terraform for MISCONFIGURATION — no rule
knows that mongo_version = "5.0" means unsupported. So the datastore was
invisible to the entire pipeline until this check existed.

WHAT THIS STILL DOES NOT DO
---------------------------
It checks what is DECLARED, not what is INSTALLED. It reads the pins out of
source, so it cannot see a package a startup script pulled in transitively, or
drift between the pin and the running host. Closing that needs an SBOM of the
VM itself — agentless disk scanning — which is the honest next step and is
named as such on the closing slide.

Usage:
    check-eol.py             # report; exit 0 even on findings (lab default)
    check-eol.py --strict    # exit 1 if anything is past end-of-life
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path

API = "https://endoflife.date/api/{product}.json"
ROOT = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class Pin:
    """A version pinned in source, and where to look it up."""

    name: str  # human label
    source: str  # file the pin is read from
    pattern: str  # regex with one capture group holding the version
    product: str  # endoflife.date product id
    cycle_of: "callable" = staticmethod(lambda v: v)  # version -> release cycle


PINS = [
    Pin(
        name="MongoDB (VM)",
        source="terraform/variables.tf",
        pattern=r'variable\s+"mongo_version".*?default\s*=\s*"([^"]+)"',
        product="mongodb",
    ),
    Pin(
        name="Ubuntu (Mongo VM image)",
        source="terraform/variables.tf",
        pattern=r'variable\s+"mongo_image".*?default\s*=\s*"[^"]*ubuntu-(\d{4})-',
        product="ubuntu",
        # "2004" -> "20.04"
        cycle_of=lambda v: f"{v[:2]}.{v[2:]}",
    ),
    Pin(
        name="Node.js (app base image)",
        source="app/Dockerfile",
        pattern=r"^FROM\s+node:(\d+)",
        product="nodejs",
    ),
]


def read_pin(pin: Pin) -> str | None:
    path = ROOT / pin.source
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8")
    m = re.search(pin.pattern, text, re.S | re.M)
    return pin.cycle_of(m.group(1)) if m else None


def lifecycle(product: str) -> list[dict]:
    with urllib.request.urlopen(API.format(product=product), timeout=20) as r:
        return json.load(r)


def eol_for(cycles: list[dict], cycle: str) -> tuple[str | None, bool | None]:
    """Return (eol_value, is_past_eol) for a release cycle."""
    for c in cycles:
        if str(c.get("cycle")) == cycle:
            eol = c.get("eol")
            if isinstance(eol, bool):  # some products use true/false
                return (str(eol), eol)
            if isinstance(eol, str):
                return (eol, dt.date.fromisoformat(eol) < dt.date.today())
            return (str(eol), None)
    return (None, None)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--strict",
        action="store_true",
        help="exit non-zero when a pin is past end-of-life",
    )
    args = ap.parse_args()

    rows, findings = [], 0
    for pin in PINS:
        cycle = read_pin(pin)
        if cycle is None:
            rows.append((pin.name, "?", "pin not found", "⚠️"))
            continue
        try:
            eol, past = eol_for(lifecycle(pin.product), cycle)
        except Exception as exc:  # network or unknown product
            rows.append((pin.name, cycle, f"lookup failed: {exc}", "⚠️"))
            continue

        if eol is None:
            rows.append((pin.name, cycle, "cycle not in dataset", "⚠️"))
        elif past:
            findings += 1
            rows.append((pin.name, cycle, f"END OF LIFE since {eol}", "🔴"))
        else:
            rows.append((pin.name, cycle, f"supported until {eol}", "✅"))

    width = max(len(r[0]) for r in rows)
    print("\nPinned platform versions — vendor support status\n")
    for name, cycle, status, mark in rows:
        print(f"  {mark}  {name:<{width}}  {cycle:<8} {status}")
    print(
        f"\n{findings} pin(s) past end of life."
        if findings
        else "\nAll pins are within vendor support."
    )

    # GitHub Actions surfaces
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write("### Platform lifecycle (end-of-life) check\n\n")
            fh.write("| | Component | Pinned | Vendor support |\n|---|---|---|---|\n")
            for name, cycle, status, mark in rows:
                fh.write(f"| {mark} | {name} | `{cycle}` | {status} |\n")
            fh.write(
                "\nEnd-of-life is a *lifecycle* fact, not a CVE: a component can be "
                "past EOL with no known vulnerabilities and no vendor left to fix "
                "the next one. Source: endoflife.date.\n"
            )
    for name, cycle, status, mark in rows:
        if mark == "🔴":
            print(f"::warning title=End of life::{name} {cycle} — {status}")

    return 1 if (args.strict and findings) else 0


if __name__ == "__main__":
    sys.exit(main())
