#!/usr/bin/env python3
"""Complete single-layer F.Cu routing for AV converter PCB."""
import math
import re
import uuid
from pathlib import Path

PCB = Path(__file__).parent / "avconver.kicad_pcb"
MARKER = "\t(zone\n\t\t(uuid \"00000000-0000-0000-0000-000000000001\")"


def uid():
    return str(uuid.uuid4())


def rot(x, y, deg):
    r = math.radians(deg)
    return (x * math.cos(r) - y * math.sin(r), x * math.sin(r) + y * math.cos(r))


def abs_pad(fp_x, fp_y, fp_rot, pad_x, pad_y, pad_rot=0):
    rx, ry = rot(pad_x, pad_y, fp_rot + pad_rot)
    return (round(fp_x + rx, 3), round(fp_y + ry, 3))


def parse_pcb(text):
    nets = {int(m.group(1)): m.group(2) for m in re.finditer(r'\(net (\d+) "([^"]+)"\)', text)}
    name_to_net = {v: k for k, v in nets.items()}
    pads = {}
    for chunk in text.split("\t(footprint ")[1:]:
        ref_m = re.search(r'\(property "Reference" "([^"]+)"', chunk)
        at_m = re.search(r'\(at ([\d.-]+) ([\d.-]+)(?: ([\d.-]+))?\)', chunk)
        if not ref_m or not at_m:
            continue
        ref = ref_m.group(1)
        fp_x, fp_y = float(at_m.group(1)), float(at_m.group(2))
        fp_rot = float(at_m.group(3) or 0)
        pads[ref] = []
        for pm in re.finditer(
            r'\(pad "([^"]+)"[^\n]*\n(?:[^\n]*\n)*?\s*\(at ([\d.-]+) ([\d.-]+)(?: ([\d.-]+))?\)[^\n]*\n(?:[^\n]*\n)*?\s*\(net (\d+) "([^"]+)"',
            chunk,
        ):
            ax, ay = abs_pad(fp_x, fp_y, fp_rot, float(pm.group(2)), float(pm.group(3)), float(pm.group(4) or 0))
            pads[ref].append({"num": pm.group(1), "x": ax, "y": ay, "net": int(pm.group(5))})
    return pads, name_to_net


def seg(x1, y1, x2, y2, net, w=0.35):
    if abs(x1 - x2) < 0.001 and abs(y1 - y2) < 0.001:
        return ""
    return f"""\t(segment
\t\t(start {x1} {y1})
\t\t(end {x2} {y2})
\t\t(width {w})
\t\t(layer "F.Cu")
\t\t(net {net})
\t\t(uuid "{uid()}")
\t)
"""


def route_l(points, net, w=0.35):
    out = []
    for a, b in zip(points, points[1:]):
        s = seg(a[0], a[1], b[0], b[1], net, w)
        if s:
            out.append(s)
    return out


def route_manhattan(a, b, net, w=0.35, prefer="h"):
    """L-route between two points."""
    if prefer == "h":
        mid = (b[0], a[1])
    else:
        mid = (a[0], b[1])
    return route_l([a, mid, b], net, w)


def pad(pads, ref, num):
    for p in pads[ref]:
        if p["num"] == str(num):
            return (p["x"], p["y"])
    raise KeyError(f"{ref} pad {num}")


def chain_route(points, net, w=0.35):
    """Connect pads in order through a horizontal bus at median Y."""
    if len(points) < 2:
        return []
    ys = [p[1] for p in points]
    bus_y = round(sum(ys) / len(ys), 3)
    routes = []
    xs = sorted(p[0] for p in points)
    bus = [(xs[0], bus_y)]
    for x in xs:
        bus.append((x, bus_y))
    routes += route_l(bus, net, w)
    for p in points:
        routes += route_l([p, (p[0], bus_y)], net, w)
    return routes


def main():
    text = PCB.read_text(encoding="utf-8")
    if MARKER.strip() in text:
        print("Already routed by route_complete.py — skipping.")
        return

    # Remove zero-length segments
    text = re.sub(
        r'\t\(segment\n\t\t\(start ([\d.-]+) ([\d.-]+)\)\n\t\t\(end \1 \2\)[^\)]*\)\n',
        "",
        text,
    )

    pads, names = parse_pcb(text)
    routes = []
    gnd = names["GND"]

    def n(name):
        return names[name]

    def connect(name, refs_pads, w=0.35, bus=None):
        """refs_pads: list of (ref, padnum) tuples."""
        try:
            pts = [pad(pads, r, p) for r, p in refs_pads]
        except KeyError as e:
            print(f"skip {name}: {e}")
            return
        net = n(name)
        if bus == "chain":
            routes.extend(chain_route(pts, net, w))
        elif len(pts) == 2:
            routes.extend(route_manhattan(pts[0], pts[1], net, w))
        else:
            routes.extend(chain_route(pts, net, w))

    # --- LM2577 boost ---
    connect("Net-(IC1-COMP)", [("IC1", "1"), ("R7", "2")], 0.35)
    connect("Net-(C1-Pad1)", [("C1", "1"), ("R7", "1")], 0.35)
    connect(
        "Net-(IC1-FEEDBACK)",
        [("IC1", "2"), ("R3", "1"), ("R4", "2")],
        0.35,
        "chain",
    )
    connect("Net-(R4-Pad1)", [("R4", "1"), ("R6", "1")], 0.35)
    connect("Net-(R3-Pad2)", [("R3", "2"), ("R5", "2")], 0.35)

    # 12V output rail
    connect(
        "Net-(D1-K)",
        [("D1", "1"), ("R16", "1"), ("R2", "1"), ("R5", "1")],
        0.5,
        "chain",
    )
    connect("Net-(D2-A)", [("R2", "2"), ("D2", "2")], 0.35)

    # 5V distribution (star from IC1 VIN)
    connect(
        "Net-(IC1-VIN)",
        [
            ("IC1", "5"),
            ("C2", "1"),
            ("J1", "9"),
            ("IC2", "14"),
            ("R8", "1"),
            ("R10", "1"),
            ("L1", "2"),
            ("Q2", "3"),
        ],
        0.45,
        "chain",
    )

    # 74HC86 sync inputs
    connect(
        "Net-(IC2-1B)",
        [("IC2", "2"), ("R14", "1"), ("C3", "1")],
        0.35,
        "chain",
    )
    connect(
        "Net-(IC2-2B)",
        [("IC2", "5"), ("R15", "1"), ("C4", "1")],
        0.35,
        "chain",
    )

    # IC2 internal XOR chains (short)
    connect("Net-(IC2-1Y)", [("IC2", "3"), ("IC2", "13")], 0.3)
    connect("Net-(IC2-2Y)", [("IC2", "6"), ("IC2", "12")], 0.3)
    connect("Net-(IC2-3B)", [("IC2", "10"), ("IC2", "11")], 0.3)

    # Sync output path: IC2 -> R1 -> Q1 base network
    connect("Net-(IC2-3Y)", [("IC2", "8"), ("R1", "2")], 0.35)
    connect(
        "Net-(Q1-B)",
        [("R1", "1"), ("Q1", "1"), ("R9", "1")],
        0.35,
        "chain",
    )
    connect(
        "Net-(Q1-C)",
        [("Q1", "3"), ("R10", "2"), ("Q2", "1")],
        0.35,
        "chain",
    )
    connect("Net-(Q2-E)", [("Q2", "2"), ("R11", "1")], 0.35)

    # Blanking resistor network -> J2 pin 16
    connect(
        "Net-(R11-Pad2)",
        [("R11", "2"), ("R12", "1"), ("R13", "1")],
        0.35,
        "chain",
    )
    connect("Net-(J2-Pad16)", [("R8", "2"), ("J2", "16")], 0.35)

    # Sync to SCART pin 20 via R13
    # R13-2 already on Net-(J2-Pad20) — connect R13 pads
    try:
        r13_1 = pad(pads, "R13", "1")
        r13_2 = pad(pads, "R13", "2")
        routes += route_manhattan(r13_1, r13_2, n("Net-(J2-Pad20)"), 0.35)
    except KeyError:
        pass

    # GND: top bus y=36 + drops for all GND pads
    gnd_top = 36.0
    gnd_pads = [(p["x"], p["y"]) for ref in pads for p in pads[ref] if p["net"] == gnd]
    if gnd_pads:
        xs = sorted({round(x, 2) for x, _ in gnd_pads})
        spine = [(xs[0], gnd_top)]
        for x in xs:
            spine.append((x, gnd_top))
        routes += route_l(spine, gnd, 0.6)
        for x, y in gnd_pads:
            if y > gnd_top + 0.5:
                routes += route_l([(x, y), (x, gnd_top)], gnd, 0.45)

    # Insert routes immediately before the document-level embedded_fonts (last occurrence).
    eof_marker = "\t(embedded_fonts no)\n)"
    idx = text.rfind(eof_marker)
    if idx == -1:
        raise SystemExit("PCB EOF marker not found")
    marker_insert = "".join(routes) + "\n"
    text = text[:idx] + marker_insert + text[idx:]
    PCB.write_text(text, encoding="utf-8")
    print(f"Added {len(routes)} route segments (complete pass).")


if __name__ == "__main__":
    main()
