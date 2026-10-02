#!/usr/bin/env python3
"""Bind acceptance verdicts to current Git contents and verification inputs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


INPUTS = ("ticket.md", "brainstorm.md", "qa.md", "local-testing.md")


def git(workspace, *args):
    return subprocess.check_output(["git", "-C", str(workspace), *args])


def criteria(text):
    """Read list items and prose in Acceptance Criteria sections, retaining continuations."""
    active = False
    level = 0
    result = []
    for line in text.splitlines():
        heading = re.match(r"^(#{1,6})\s+(.+?)\s*#*\s*$", line)
        if heading:
            title = heading[2].strip().strip("*_").lower()
            if title == "acceptance criteria":
                active, level = True, len(heading[1])
            elif active:
                if len(heading[1]) <= level:
                    active = False
                else:
                    # Requirement-bearing subheadings must not disappear from coverage.
                    result.append(heading[2].strip())
            continue
        if not active or not line.strip():
            continue
        item = re.match(r"^\s*(?:[-*+]\s+|\d+[.)]\s+)(?:\[[ xX]\]\s+)?(.+)$", line)
        if item:
            result.append(item[1].strip())
        elif line[:1].isspace() and result:
            result[-1] += " " + line.strip()
        else:
            result.append(line.strip())
    return result


def snapshot(workspace, memory, base):
    workspace, memory = workspace.resolve(), memory.resolve()
    if workspace.is_relative_to(memory):
        raise ValueError("memory cannot contain the source workspace")
    if Path(os.fsdecode(git(workspace, "rev-parse", "--show-toplevel")).strip()).resolve() != workspace:
        raise ValueError("workspace must be the Git toplevel")
    base_sha = git(workspace, "rev-parse", "--verify", "--end-of-options", base + "^{commit}").strip()
    digest = hashlib.sha256()

    def add(label, value):
        # Length framing prevents collisions across filenames and payload boundaries.
        for part in (label, value):
            digest.update(len(part).to_bytes(8, "big"))
            digest.update(part)

    add(b"base", base_sha)
    paths = git(workspace, "ls-files", "-z", "--cached", "--others", "--exclude-standard")
    for raw in sorted(set(paths.split(b"\0")) - {b""}):
        path = workspace / os.fsdecode(raw)
        if path.is_relative_to(memory):
            continue
        if path.is_symlink():
            value = b"link\0" + os.fsencode(os.readlink(path))
        elif path.is_file():
            value = b"file\0" + str(path.stat().st_mode & 0o111).encode() + b"\0" + path.read_bytes()
        elif path.is_dir():
            # Submodules need their own verdict/evidence; do not silently ignore changes.
            raise ValueError("directory/submodule in source snapshot: " + os.fsdecode(raw))
        else:
            value = b"deleted"
        add(b"source/" + raw, value)
    expected = []
    for name in INPUTS:
        path = memory / name
        value = path.read_bytes() if path.exists() else b""
        add(b"memory/" + name.encode(), value)
        if name in ("ticket.md", "brainstorm.md"):
            for number, text in enumerate(criteria(value.decode("utf-8")), 1):
                expected.append({"id": f"{name[:-3]}-{number}", "criterion": text})
    if not criteria((memory / "ticket.md").read_text()):
        raise ValueError("ticket has no Acceptance Criteria; clarify before publication")
    return {"fingerprint": digest.hexdigest(), "criteria": expected}


def check(current, artifact, waiver_fingerprint="", waiver_reason=""):
    blocks = re.findall(r"^```json\s*\n(.*?)^```\s*$", artifact, re.M | re.S)
    if len(blocks) != 1:
        raise ValueError("evaluator.md must contain exactly one JSON result block")
    data = json.loads(blocks[0])
    if not isinstance(data, dict) or type(data.get("schema_version")) is not int or data["schema_version"] != 1:
        raise ValueError("unsupported evaluator schema")
    if data.get("fingerprint") != current["fingerprint"]:
        raise ValueError("stale evaluator verdict; reevaluate current inputs")
    items = data.get("items")
    if not isinstance(items, list) or len(items) != len(current["criteria"]):
        raise ValueError("evaluator must cover every original and refined criterion")
    expected = {item["id"]: item["criterion"] for item in current["criteria"]}
    seen, statuses = set(), []
    for item in items:
        if not isinstance(item, dict):
            raise ValueError("invalid criterion item")
        item_id = item.get("id")
        if not isinstance(item_id, str) or item_id in seen or item_id not in expected:
            raise ValueError("duplicate or unknown criterion ID")
        if item.get("criterion") != expected[item_id]:
            raise ValueError("criterion text was substituted")
        seen.add(item_id)
        status = item.get("verdict")
        if status not in ("PASS", "FAIL", "SKIP"):
            raise ValueError("invalid per-criterion verdict")
        key = "evidence" if status == "PASS" else "reason"
        if not isinstance(item.get(key), str) or not item[key].strip():
            raise ValueError(f"{item_id} requires {key}")
        statuses.append(status)
    verdict = "FAIL" if "FAIL" in statuses else "PASS" if "PASS" in statuses else "SKIP"
    if data.get("verdict") != verdict:
        raise ValueError("overall verdict contradicts per-criterion verdicts")
    waived = (verdict == "FAIL" and waiver_fingerprint == current["fingerprint"]
              and bool(waiver_reason.strip()))
    return {"verdict": verdict, "fingerprint": current["fingerprint"],
            "counts": {status: statuses.count(status) for status in ("PASS", "FAIL", "SKIP")},
            "waived": waived, "waiver_reason": waiver_reason if waived else ""}, (0 if verdict != "FAIL" or waived else 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("snapshot", "check"))
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--memory", required=True, type=Path)
    parser.add_argument("--base", required=True)
    parser.add_argument("--waiver-fingerprint", default="")
    parser.add_argument("--waiver-reason", default="")
    args = parser.parse_args()
    try:
        current = snapshot(args.workspace, args.memory, args.base)
        result, code = (current, 0) if args.command == "snapshot" else check(
            current, (args.memory / "evaluator.md").read_text(),
            args.waiver_fingerprint, args.waiver_reason)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        result, code = {"verdict": "BLOCKED", "error": str(error)}, 2
    print(json.dumps(result, ensure_ascii=True))
    return code


if __name__ == "__main__":
    sys.exit(main())
