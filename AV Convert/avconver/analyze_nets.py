#!/usr/bin/env python3
import math
import re
from pathlib import Path

PCB = Path(__file__).parent / "avconver.kicad_pcb"


def rot(x, y, deg):
    r = math.radians(deg)
    return (x * math.cos(r) - y * math.sin(r), x * math.sin(r) + y * math.cos(r))


def abs_pad(fx, fy, fr, px, py, pr=0):
    rx, ry = rot(px, py, fr + pr)
    return (round(fx + rx, 2), round(fy + ry, 2))


text = PCB.read_text(encoding="utf-8")
by_net = {}
refs_at = {}
for chunk in text.split("\t(footprint ")[1:]:
    rm = re.search(r'"Reference" "([^"]+)"', chunk)
    am = re.search(r"\(at ([\d.-]+) ([\d.-]+)(?: ([\d.-]+))?", chunk)
    if not rm or not am:
        continue
    ref = rm.group(1)
    fx, fy = float(am.group(1)), float(am.group(2))
    fr = float(am.group(3) or 0)
    refs_at[ref] = (fx, fy, fr)
    for pm in re.finditer(
        r'\(pad "([^"]+)"[^\n]*\n(?:[^\n]*\n)*?\s*\(at ([\d.-]+) ([\d.-]+)(?: ([\d.-]+))?\)[^\n]*\n(?:[^\n]*\n)*?\s*\(net (\d+) "([^"]+)"',
        chunk,
    ):
        ax, ay = abs_pad(fx, fy, fr, float(pm.group(2)), float(pm.group(3)), float(pm.group(4) or 0))
        name = pm.group(6)
        by_net.setdefault(name, []).append((ref, pm.group(1), ax, ay))

print("=== Component positions ===")
for ref in sorted(refs_at):
    print(f"{ref}: {refs_at[ref]}")

print("\n=== Nets (non-unconnected) ===")
for name in sorted(by_net):
    if name.startswith("unconnected") or name == "":
        continue
    pts = by_net[name]
    print(f"\n{name} ({len(pts)} pads):")
    for p in pts:
        print(f"  {p[0]}-{p[1]} @ ({p[2]}, {p[3]})")
