#!/usr/bin/env python3
"""Validate and fix common KiCad PCB S-expression issues."""
import re
from pathlib import Path

import sys

PCB = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "avconver.kicad_pcb"


def balance_check(text):
    depth = 0
    line_no = 0
    for i, line in enumerate(text.splitlines(), 1):
        # strip strings roughly
        s = re.sub(r'"[^"]*"', '""', line)
        for ch in s:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth < 0:
                    return False, i, depth
    return depth == 0, len(text.splitlines()), depth


text = PCB.read_text(encoding="utf-8")
ok, loc, depth = balance_check(text)
print(f"Balance OK: {ok}, line/ref: {loc}, final depth: {depth}")
print(f"Open/close counts: {text.count('(')} / {text.count(')')}")

# Invalid constructs
if re.search(r"^\s*;", text, re.M):
    print("WARNING: semicolon comments found (invalid in KiCad S-expr)")
    for i, line in enumerate(text.splitlines(), 1):
        if line.strip().startswith(";"):
            print(f"  line {i}: {line.strip()[:80]}")

# Check for segments before closing or outside root
if "(embedded_fonts no)" in text:
    print(f"embedded_fonts count: {text.count('(embedded_fonts no)')}")
