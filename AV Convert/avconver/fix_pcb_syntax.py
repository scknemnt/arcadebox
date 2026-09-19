#!/usr/bin/env python3
"""Fix KiCad PCB S-expression syntax errors."""
import re
import sys
from pathlib import Path

PCB = Path(__file__).parent / "avconver.kicad_pcb"


def scan_depth(text):
    issues = []
    depth = 0
    for i, line in enumerate(text.splitlines(), 1):
        s = re.sub(r'"[^"]*"', '""', line)
        for j, ch in enumerate(s):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth < 0:
                    issues.append((i, j, depth, line.strip()[:100]))
    return depth, issues


def main():
    text = PCB.read_text(encoding="utf-8")
    original = text

    # 1) Remove invalid semicolon comment lines
    lines = []
    removed = 0
    for line in text.splitlines():
        if line.strip().startswith(";"):
            removed += 1
            continue
        lines.append(line)
    text = "\n".join(lines) + "\n"

    depth, issues = scan_depth(text)
    print(f"After comment removal: depth={depth}, removed={removed} lines")
    if issues:
        print("First negative depth:")
        for item in issues[:5]:
            print(" ", item)

    # 2) If one extra closing paren at EOF, remove trailing ) before embedded_fonts block
    if depth == -1:
        # Common corruption: duplicate closing paren before final embedded_fonts
        text2 = text.replace(
            "\t(embedded_fonts no)\n)\n",
            "\t(embedded_fonts no)\n",
            1,
        )
        depth2, _ = scan_depth(text2)
        if depth2 == 0:
            text = text2 + ")\n"
            print("Fixed: removed duplicate closing paren before EOF")
        else:
            # Try removing one standalone ) line near end
            tail = text.rstrip().splitlines()
            for idx in range(len(tail) - 1, max(len(tail) - 20, 0), -1):
                if tail[idx].strip() == ")":
                    trial = "\n".join(tail[:idx] + tail[idx + 1 :]) + "\n"
                    d, _ = scan_depth(trial)
                    if d == 0:
                        text = trial
                        print(f"Fixed: removed extra ')' at line {idx + 1}")
                        break

    depth, _ = scan_depth(text)
    print(f"Final depth: {depth}")
    print(f"Parens: {text.count('(')} / {text.count(')')}")

    if depth != 0:
        print("ERROR: still unbalanced — manual repair needed")
        sys.exit(1)

    if text != original:
        PCB.write_text(text, encoding="utf-8")
        print(f"Wrote fixed PCB: {PCB}")
    else:
        print("No changes needed")


if __name__ == "__main__":
    main()
