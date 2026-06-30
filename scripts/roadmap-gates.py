#!/usr/bin/env python3
"""Validate QSOE roadmap issue metadata and print component gate checklists."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_REPO = "dmytro-yemelianov/qsoe-os-rust-handover"
ROADMAP_LABEL = "roadmap"
META_RE = re.compile(r"<!--\s*qsoe-roadmap:v1\s*(.*?)\s*-->", re.S)
VALID_KINDS = {"component", "phase", "backlog", "tooling"}
STATUS_LABELS = {
    "complete": "status:complete",
    "complete-for-current-scope": "status:complete",
    "deferred": "status:deferred",
    "future": "status:future",
    "in-progress": "status:in-progress",
    "rc": "status:rc",
    "retired": "status:retired",
    "rust-default-rc": "status:rc",
    "rust-opt-in": "status:rust-opt-in",
    "started": "status:in-progress",
}
COMMAND_PREFIXES = (
    "./scripts/",
    "bash ",
    "cargo ",
    "make ",
    "python ",
    "scripts/",
    "QSOE_",
)


@dataclass
class RoadmapItem:
    issue: dict[str, Any]
    metadata: dict[str, Any]

    @property
    def number(self) -> int:
        return int(self.issue["number"])

    @property
    def labels(self) -> set[str]:
        return label_names(self.issue)

    @property
    def kind(self) -> str:
        return str(self.metadata.get("kind", ""))

    @property
    def status(self) -> str:
        return str(self.metadata.get("status", ""))

    @property
    def name(self) -> str:
        return str(self.metadata.get("name", ""))

    @property
    def ident(self) -> str:
        return str(self.metadata.get("id", ""))


def die(message: str) -> None:
    print(f"roadmap-gates.py: {message}", file=sys.stderr)
    sys.exit(1)


def detect_repo() -> str:
    env_repo = os.environ.get("GITHUB_REPOSITORY")
    if env_repo:
        return env_repo

    try:
        remote = subprocess.check_output(
            ["git", "remote", "get-url", "origin"],
            cwd=ROOT,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return DEFAULT_REPO

    match = re.search(r"github\.com[:/]([^/]+)/([^/.]+)(?:\.git)?$", remote)
    if match:
        return f"{match.group(1)}/{match.group(2)}"
    return DEFAULT_REPO


def read_issues(path: str) -> list[dict[str, Any]]:
    if path == "-":
        return json.load(sys.stdin)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def fetch_issues(repo: str) -> list[dict[str, Any]]:
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    issues: list[dict[str, Any]] = []

    for page in range(1, 50):
        params = urllib.parse.urlencode(
            {
                "state": "all",
                "labels": ROADMAP_LABEL,
                "per_page": "100",
                "page": str(page),
            }
        )
        url = f"https://api.github.com/repos/{repo}/issues?{params}"
        request = urllib.request.Request(
            url,
            headers={
                "Accept": "application/vnd.github+json",
                "User-Agent": "qsoe-roadmap-gates",
                **({"Authorization": f"Bearer {token}"} if token else {}),
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                page_items = json.load(response)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            die(f"GitHub Issues API returned {error.code}: {detail}")
        except urllib.error.URLError as error:
            die(f"GitHub Issues API request failed: {error}")

        if not page_items:
            break
        issues.extend(page_items)
        if len(page_items) < 100:
            break
    else:
        die("GitHub Issues API pagination exceeded 49 pages")

    return issues


def label_names(issue: dict[str, Any]) -> set[str]:
    names = set()
    for label in issue.get("labels", []):
        if isinstance(label, dict):
            names.add(str(label.get("name", "")))
        else:
            names.add(str(label))
    return {name for name in names if name}


def parse_items(issues: list[dict[str, Any]]) -> tuple[list[RoadmapItem], list[str]]:
    items: list[RoadmapItem] = []
    errors: list[str] = []

    for issue in issues:
        if issue.get("pull_request"):
            continue

        number = issue.get("number", "?")
        body = str(issue.get("body") or "")
        labels = label_names(issue)
        matches = META_RE.findall(body)

        if ROADMAP_LABEL in labels and not matches:
            errors.append(f"#{number}: has `{ROADMAP_LABEL}` label but no qsoe-roadmap:v1 block")
            continue
        if not matches:
            continue
        if len(matches) > 1:
            errors.append(f"#{number}: has multiple qsoe-roadmap:v1 blocks")
            continue

        try:
            metadata = json.loads(matches[0])
        except json.JSONDecodeError as error:
            errors.append(f"#{number}: invalid qsoe-roadmap:v1 JSON: {error}")
            continue
        if not isinstance(metadata, dict):
            errors.append(f"#{number}: qsoe-roadmap:v1 block must be a JSON object")
            continue

        items.append(RoadmapItem(issue=issue, metadata=metadata))

    return items, errors


def validate_items(items: list[RoadmapItem]) -> list[str]:
    errors: list[str] = []
    seen_ids: dict[str, int] = {}

    for item in items:
        prefix = f"#{item.number}"
        labels = item.labels
        metadata = item.metadata

        if metadata.get("schemaVersion") != 1:
            errors.append(f"{prefix}: schemaVersion must be 1")

        require_string(errors, prefix, metadata, "id")
        require_string(errors, prefix, metadata, "name")
        require_string(errors, prefix, metadata, "kind")
        require_string(errors, prefix, metadata, "status")

        if item.ident:
            other = seen_ids.get(item.ident)
            if other is not None:
                errors.append(f"{prefix}: duplicate metadata id `{item.ident}` also used by #{other}")
            seen_ids[item.ident] = item.number

        if ROADMAP_LABEL not in labels:
            errors.append(f"{prefix}: missing `{ROADMAP_LABEL}` label")
        if "rust-migration" not in labels:
            errors.append(f"{prefix}: missing `rust-migration` label")

        if item.kind not in VALID_KINDS:
            errors.append(f"{prefix}: unsupported kind `{item.kind}`")
        else:
            expected_kind_label = f"roadmap:{item.kind}"
            if expected_kind_label not in labels:
                errors.append(f"{prefix}: missing `{expected_kind_label}` label")

        expected_status_label = STATUS_LABELS.get(item.status)
        status_labels = sorted(label for label in labels if label.startswith("status:"))
        if expected_status_label is None:
            errors.append(f"{prefix}: unsupported status `{item.status}`")
        elif expected_status_label not in status_labels:
            errors.append(
                f"{prefix}: status `{item.status}` requires `{expected_status_label}` label; "
                f"found {status_labels or 'none'}"
            )
        if len(status_labels) > 1:
            errors.append(f"{prefix}: has multiple status labels: {', '.join(status_labels)}")

        if item.kind == "component":
            validate_component(errors, prefix, metadata)
        elif item.kind == "phase":
            validate_optional_list(errors, prefix, metadata, "deliverables")
        elif item.kind == "backlog":
            validate_optional_list(errors, prefix, metadata, "files")
        elif item.kind == "tooling":
            require_string(errors, prefix, metadata, "priority")
            validate_optional_list(errors, prefix, metadata, "tools", required=True)
            validate_optional_list(errors, prefix, metadata, "acceptance", required=True)

    return errors


def validate_component(errors: list[str], prefix: str, metadata: dict[str, Any]) -> None:
    require_string(errors, prefix, metadata, "currentState")
    for key in ("cDefault", "rustDefault", "retired"):
        if key in metadata and not isinstance(metadata[key], bool):
            errors.append(f"{prefix}: `{key}` must be boolean when present")
    for key in ("cRollback", "evidence", "rustArtifacts", "selectors"):
        validate_optional_list_or_string(errors, prefix, metadata, key)

    if metadata.get("retired") is True and normalize_list(metadata.get("cRollback")):
        errors.append(f"{prefix}: retired components must not keep cRollback entries")


def require_string(
    errors: list[str],
    prefix: str,
    metadata: dict[str, Any],
    key: str,
) -> None:
    value = metadata.get(key)
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{prefix}: `{key}` must be a non-empty string")


def validate_optional_list(
    errors: list[str],
    prefix: str,
    metadata: dict[str, Any],
    key: str,
    *,
    required: bool = False,
) -> None:
    value = metadata.get(key)
    if value is None:
        if required:
            errors.append(f"{prefix}: `{key}` must be a non-empty list")
        return
    if not isinstance(value, list) or not all(isinstance(item, str) and item.strip() for item in value):
        errors.append(f"{prefix}: `{key}` must be a list of non-empty strings")
    elif required and not value:
        errors.append(f"{prefix}: `{key}` must be non-empty")


def validate_optional_list_or_string(
    errors: list[str],
    prefix: str,
    metadata: dict[str, Any],
    key: str,
) -> None:
    value = metadata.get(key)
    if value is None:
        return
    if isinstance(value, str):
        if not value.strip():
            errors.append(f"{prefix}: `{key}` string must not be empty")
        return
    if isinstance(value, list) and all(isinstance(item, str) and item.strip() for item in value):
        return
    errors.append(f"{prefix}: `{key}` must be a string or list of non-empty strings")


def normalize_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [str(item) for item in value if str(item)]
    return [str(value)]


def command_like(value: str) -> bool:
    return value.startswith(COMMAND_PREFIXES)


def dedupe(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        if value not in seen:
            seen.add(value)
            out.append(value)
    return out


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def find_component(items: list[RoadmapItem], selector: str) -> RoadmapItem:
    components = [item for item in items if item.kind == "component"]
    needle = selector.strip().lstrip("#")
    if not needle:
        die("component selector is empty")

    exact = [item for item in components if str(item.number) == needle or item.ident == needle]
    if len(exact) == 1:
        return exact[0]

    needle_slug = slug(needle)
    fuzzy = [
        item
        for item in components
        if needle_slug
        and (
            needle_slug == slug(item.ident)
            or needle_slug == slug(item.name)
            or needle_slug in slug(item.ident)
            or needle_slug in slug(item.name)
            or needle_slug in slug(str(item.issue.get("title", "")))
        )
    ]
    if len(fuzzy) == 1:
        return fuzzy[0]
    if not fuzzy:
        choices = ", ".join(f"#{item.number} {item.ident}" for item in components)
        die(f"no component matched `{selector}`; choices: {choices}")
    choices = ", ".join(f"#{item.number} {item.ident}" for item in fuzzy)
    die(f"component selector `{selector}` is ambiguous: {choices}")


def print_validation(items: list[RoadmapItem], issues: list[dict[str, Any]]) -> None:
    counts: dict[str, int] = {}
    for item in items:
        counts[item.kind] = counts.get(item.kind, 0) + 1

    print("roadmap-gates.py: roadmap metadata ok")
    print(f"  source issues: {len([issue for issue in issues if not issue.get('pull_request')])}")
    print(f"  metadata items: {len(items)}")
    for kind in sorted(counts):
        print(f"  {kind}: {counts[kind]}")


def print_component_gate(item: RoadmapItem) -> None:
    metadata = item.metadata
    evidence = normalize_list(metadata.get("evidence"))
    selectors = normalize_list(metadata.get("selectors"))
    rollback_files = normalize_list(metadata.get("cRollback"))
    commands = dedupe([entry for entry in selectors + evidence if command_like(entry)])
    evidence_commands = [cmd for cmd in commands if "evidence" in cmd or "check-" in cmd]
    runtime_commands = [
        cmd
        for cmd in commands
        if ("runtime-smoke" in cmd or "boot-smoke" in cmd or "data-smoke" in cmd or "live-smoke" in cmd)
    ]
    rc_commands = [cmd for cmd in commands if "rc-smoke" in cmd and "rollback" not in cmd]
    rollback_commands = [
        cmd
        for cmd in commands
        if "rollback" in cmd or re.search(r"\bQSOE_[A-Z0-9_]+=0\b", cmd)
    ]

    print(f"Roadmap component gate: {metadata.get('name', item.ident)}")
    print(f"Issue: #{item.number} {item.issue.get('html_url') or item.issue.get('url', '')}")
    print(f"ID: {item.ident}")
    print(f"Status: {metadata.get('status')} / currentState={metadata.get('currentState')}")
    print(f"Expected labels: roadmap, roadmap:component, {STATUS_LABELS.get(item.status, 'status:?')}")
    print(f"Next gate: {metadata.get('nextGate', '(not recorded)')}")
    print()

    print_section("Selectors", selectors)
    print_section("Evidence commands", evidence_commands)
    print_section("Runtime / boot smoke commands", runtime_commands)
    print_section("Rust-default RC commands", rc_commands)

    if rollback_files or rollback_commands:
        print("C rollback")
        print_list("files", rollback_files)
        print_list("commands", rollback_commands)
        print()
    else:
        print("C rollback")
        print("  - No C rollback entries are recorded; confirm this is retired or document the gap.")
        print()

    print("Issue update checklist")
    print("  [ ] Update qsoe-roadmap:v1 metadata in the issue body.")
    print("  [ ] Keep labels aligned with kind/status.")
    print("  [ ] Append new host, evidence, runtime, RC, and rollback commands/results to `evidence`.")
    print("  [ ] Record rcPr, mainCommit, mainCiRun, and nextGate after PR and main CI complete.")
    print("  [ ] Run `make roadmap-validate` after editing issue metadata.")
    print()

    print("PR checklist")
    print("  [ ] Include the unsafe-review line or state that no unsafe/FFI boundary changed.")
    print("  [ ] Update migration docs and release-candidate/retirement notes when selector state changes.")
    print("  [ ] Run the commands above that match the requested transition before merging.")


def print_section(title: str, values: list[str]) -> None:
    print(title)
    if not values:
        print("  - None recorded in issue metadata.")
    else:
        for value in values:
            print(f"  [ ] {value}")
    print()


def print_list(label: str, values: list[str]) -> None:
    print(f"  {label}:")
    if not values:
        print("    - None recorded.")
    else:
        for value in values:
            print(f"    - {value}")


def load_items(args: argparse.Namespace) -> tuple[list[dict[str, Any]], list[RoadmapItem]]:
    issues = read_issues(args.issues_json) if args.issues_json else fetch_issues(args.repo)
    items, parse_errors = parse_items(issues)
    validation_errors = validate_items(items)
    errors = parse_errors + validation_errors
    if errors:
        print("roadmap-gates.py: roadmap metadata validation failed", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        sys.exit(1)
    if not items:
        die("no qsoe-roadmap:v1 metadata items found")
    return issues, items


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=detect_repo(), help="GitHub repo, default: detected from origin")
    parser.add_argument("--issues-json", help="read issues JSON from this file or '-' instead of GitHub")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("validate", help="validate every qsoe-roadmap:v1 issue block")

    component = subparsers.add_parser("component", help="print a selected component gate checklist")
    component.add_argument("selector", help="component id, issue number, or unambiguous name fragment")

    args = parser.parse_args()
    issues, items = load_items(args)

    if args.command == "validate":
        print_validation(items, issues)
    elif args.command == "component":
        print_component_gate(find_component(items, args.selector))
    else:
        die(f"unsupported command {args.command}")


if __name__ == "__main__":
    main()
