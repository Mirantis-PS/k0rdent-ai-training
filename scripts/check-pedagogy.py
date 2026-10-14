#!/usr/bin/env python3
"""Check P2 document contracts and shell syntax; never certify runtime behavior."""
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
index = json.loads((ROOT / "docs/curriculum-v2/p2-index.json").read_text())
errors = []
required = ["Prerequisites and input state", "Objectives and problem", "Concept capsule", "Hypothesis", "Procedure and checkpoints", "Interpretation", "Bounded incident or tradeoff", "Declarative delivery", "Restoration and cleanup", "Evidence and acceptance", "Provenance and instructor route"]
ids = [lab["id"] for lab in index["labs"]]
if len(ids) != 9 or len(set(ids)) != 9:
    errors.append("Expected nine unique lab IDs")
if [row["id"] for row in index["coverage"]] != [f"C{i:02d}" for i in range(1, 41)]:
    errors.append("Coverage must contain C01–C40 exactly once in order")
for lab in index["labs"]:
    target = ROOT / lab["path"]
    text = target.read_text()
    for heading in required:
        if "## " + heading + "\n" not in text:
            errors.append(f"{target}: missing {heading}")
    for code in re.findall(r"```bash\n(.*?)```", text, re.S):
        result = subprocess.run(["bash", "-n"], input=code, text=True, capture_output=True)
        if result.returncode:
            errors.append(f"{target}: {result.stderr}")
for row in index["coverage"]:
    for field in ("introduction", "practice", "revisit"):
        if not (ROOT / row[field].split("#")[0]).is_file():
            errors.append(f"{row['id']}: missing {field}")
for error in errors:
    print(error, file=sys.stderr)
print(f"P2 contracts: {len(ids)} labs, {len(index['lessons'])} lessons, {len(index['coverage'])} coverage rows; {len(errors)} errors. No runtime proof.")
sys.exit(bool(errors))
