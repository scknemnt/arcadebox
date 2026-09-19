#!/usr/bin/env python3
"""Repair corrupted KiCad PCB file."""
import re
import sys
from pathlib import Path

PCB = Path(__file__).parent / "avconver.kicad_pcb"


def scan_depth(text):
    depth = 0
    for line in text.splitlines():
        s = re.sub(r'"[^"]*"', '""', line)
        for ch in s:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
    return depth


def main():
    text = PCB.read_text(encoding="utf-8")
    lines = text.splitlines()
    out = []
    i = 0
    removed_orphans = 0
    removed_comments = 0

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Drop invalid ; comments
        if stripped.startswith(";"):
            removed_comments += 1
            i += 1
            continue

        # Orphan segment tail: (layer "F.Cu") without preceding (segment within 5 lines
        if re.match(r'^\t\t\(layer "F\.Cu"\)$', line):
            prev = "\n".join(out[-8:])
            if "(segment" not in prev and "(width" not in prev:
                # consume through closing )
                i += 1
                while i < len(lines) and lines[i].strip() != ")":
                    i += 1
                if i < len(lines):
                    i += 1  # skip )
                removed_orphans += 1
                continue

        out.append(line)
        i += 1

    text = "\n".join(out) + "\n"
    depth = scan_depth(text)
    print(f"Removed comments: {removed_comments}, orphan tails: {removed_orphans}")
    print(f"Depth after repair: {depth} ({text.count('(')} / {text.count(')')})")

    if depth != 0:
        print("ERROR: still unbalanced")
        sys.exit(1)

    PCB.write_text(text, encoding="utf-8")
    print(f"Repaired: {PCB}")


if __name__ == "__main__":
    main()
