#!/usr/bin/env python3
"""Append single-layer F.Cu routes for remaining AV converter nets."""
import math
import re
import uuid
from pathlib import Path

PCB = Path(__file__).parent / "avconver.kicad_pcb"


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

    chunks = text.split("\t(footprint ")
    for chunk in chunks[1:]:
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
            num = pm.group(1)
            px, py = float(pm.group(2)), float(pm.group(3))
            prot = float(pm.group(4) or 0)
            net = int(pm.group(5))
            ax, ay = abs_pad(fp_x, fp_y, fp_rot, px, py, prot)
            pads[ref].append({"num": num, "x": ax, "y": ay, "net": net})
    return pads, name_to_net


def seg(x1, y1, x2, y2, net, w=0.35):
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
        out.append(seg(a[0], a[1], b[0], b[1], net, w))
    return out


def pad(pads, ref, num):
    for p in pads[ref]:
        if p["num"] == str(num):
            return (p["x"], p["y"])
    raise KeyError(f"{ref} pad {num}")


def main():
    text = PCB.read_text(encoding="utf-8")
    pads, names = parse_pcb(text)
    routes = []

    gnd = names["GND"]

    # HSYNC / VSYNC: J1 -> IC2
    for j1p, ic2p, nname in [("13", "1", "Net-(IC2-1A)"), ("14", "4", "Net-(IC2-2A)")]:
        try:
            n = names[nname]
            a = pad(pads, "J1", j1p)
            b = pad(pads, "IC2", ic2p)
            mid = (b[0], a[1])
            routes += route_l([a, mid, b], n, 0.35)
        except KeyError as e:
            print("hsync skip", e)

    # 5V: J1-9 -> IC1 VIN + local bypass
    n5 = names["Net-(IC1-VIN)"]
    j9 = pad(pads, "J1", "9")
    vin = pad(pads, "IC1", "5")
    routes += route_l([j9, (vin[0], j9[1]), vin], n5, 0.45)

    # Boost switch node: IC1 SW -> L1 -> D1 anode
    nsw = names["Net-(D1-A)"]
    sw = pad(pads, "IC1", "4")
    l1 = pad(pads, "L1", "1")
    d1a = pad(pads, "D1", "2")
    routes += route_l([sw, (sw[0], l1[1]), l1, d1a], nsw, 0.5)

    # Boost output D1-K -> C3 pad (if present) stub
    nv12 = names["Net-(D1-K)"]
    d1k = pad(pads, "D1", "1")
    try:
        c3 = pad(pads, "C3", "1")
        routes += route_l([d1k, c3], nv12, 0.5)
    except KeyError:
        pass

    # Audio: J3 tip/ring -> J2 pin 6 / 2
    try:
        nL = names["Net-(J2-Pad6)"]
        nR = names["Net-(J2-Pad2)"]
        j3t = pad(pads, "J3", "1")
        j3r = pad(pads, "J3", "2")
        j2l = pad(pads, "J2", "6")
        j2r = pad(pads, "J2", "2")
        routes += route_l([j3t, (j3t[0], j2l[1]), j2l], nL, 0.35)
        routes += route_l([j3r, (j3r[0], j2r[1]), j2r], nR, 0.35)
    except KeyError as e:
        print("audio skip", e)

    # Sync out: IC2 -> Q1 -> J2 pin 20
    try:
        n = names["Net-(J2-Pad20)"]
        ic = pad(pads, "IC2", "8")
        q1b = pad(pads, "Q1", "1")
        q1c = pad(pads, "Q1", "3")
        j20 = pad(pads, "J2", "20")
        routes += route_l([ic, q1b, q1c, (q1c[0], j20[1]), j20], n, 0.35)
    except KeyError as e:
        print("sync skip", e)

    # Blanking J2-16 from R9/R12 network via existing net 32
    try:
        n = names["Net-(J2-Pad16)"]
        j16 = pad(pads, "J2", "16")
        r9 = pad(pads, "R9", "2")
        routes += route_l([r9, (r9[0], j16[1]), j16], n, 0.35)
    except KeyError as e:
        print("blank skip", e)

    # GND spine along board bottom
    gnd_y = 102.0
    gnd_xs = sorted({p["x"] for ref in pads for p in pads[ref] if p["net"] == gnd})
    if gnd_xs:
        chain = [(gnd_xs[0], gnd_y)]
        for x in gnd_xs:
            chain.append((x, gnd_y))
        routes += route_l(chain, gnd, 0.6)
        for ref in ("J1", "IC1", "IC2", "J2", "J3", "D1"):
            if ref not in pads:
                continue
            for p in pads[ref]:
                if p["net"] == gnd:
                    routes += route_l([(p["x"], p["y"]), (p["x"], gnd_y)], gnd, 0.45)

    marker = "\t(embedded_fonts no)\n)"
    block = "\n".join(routes) + "\n"
    text = text.replace(marker, block + marker, 1)
    PCB.write_text(text, encoding="utf-8")
    print(f"Appended {len(routes)} segments; refs={sorted(pads.keys())}")


if __name__ == "__main__":
    main()
