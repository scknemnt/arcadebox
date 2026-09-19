#!/usr/bin/env python3
import re
from pathlib import Path

PCB = Path(__file__).parent / "avconver.kicad_pcb"
text = PCB.read_text(encoding="utf-8")
depth = 0
history = []
for i, line in enumerate(text.splitlines(), 1):
    s = re.sub(r'"[^"]*"', '""', line)
    before = depth
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
    delta = depth - before
    if delta != 0:
        history.append((i, before, depth, delta, line.strip()[:90]))

# Show last 30 depth-changing lines
for row in history[-40:]:
    print(row)
