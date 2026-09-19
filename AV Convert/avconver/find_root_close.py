#!/usr/bin/env python3
import re
from pathlib import Path

text = Path(__file__).parent.joinpath("avconver.kicad_pcb").read_text(encoding="utf-8")
depth = 0
for i, line in enumerate(text.splitlines(), 1):
    s = re.sub(r'"[^"]*"', '""', line)
    before = depth
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
    if before > 0 and depth == 0 and i < len(text.splitlines()):
        print(f"ROOT CLOSED at line {i}: {line.strip()[:80]}")
        # show context
        lines = text.splitlines()
        for j in range(max(0, i - 5), min(len(lines), i + 3)):
            print(f"  {j+1}: {lines[j][:90]}")
        print("---")
