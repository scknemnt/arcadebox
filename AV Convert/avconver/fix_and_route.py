#!/usr/bin/env python3
"""Fix SCART schematic wires and generate single-layer PCB routes."""
import re
import uuid
from pathlib import Path

ROOT = Path(__file__).parent
SCH = ROOT / "avconver.kicad_sch"
PCB = ROOT / "avconver.kicad_pcb"

NEW_WIRES = [
    ((124.46, 55.88), (138.43, 55.88)),
    ((138.43, 55.88), (138.43, 58.42)),
    ((137.16, 58.42), (128.27, 58.42)),
    ((121.92, 68.58), (128.27, 68.58)),
    ((124.46, 55.88), (128.27, 55.88)),
]

NEW_JUNCTIONS = [
    (124.46, 55.88),
    (138.43, 55.88),
    (138.43, 58.42),
    (128.27, 58.42),
    (128.27, 68.58),
]


def uid():
    return str(uuid.uuid4())


def fix_schematic():
    text = SCH.read_text(encoding="utf-8")

    value_fixes = {
        '"Reference" "C3"\n\t\t\t(at 77.47 113.0299 0)': None,
        '(property "Value" "22mf"\n\t\t\t(at 77.47 115.5699 0)': '(property "Value" "680uF"\n\t\t\t(at 77.47 115.5699 0)',
        '(property "Value" "22mf"\n\t\t\t(at 69.85 118.1099 0)': '(property "Value" "22uF"\n\t\t\t(at 69.85 118.1099 0)',
        '(property "Value" "22mf"\n\t\t\t(at 77.47 113.0299 0)': '(property "Value" "22uF"\n\t\t\t(at 77.47 113.0299 0)',
        '(property "Value" "1K"\n\t\t\t(at 142.24 30.48 90)': '(property "Value" "1K"\n\t\t\t(at 142.24 30.48 90)',
    }
    for old, new in value_fixes.items():
        if old and new and old in text:
            text = text.replace(old, new, 1)

    # C3 footprint -> radial electrolytic placeholder
    text = text.replace(
        '(property "Reference" "C3"\n\t\t\t(at 77.47 113.0299 0)',
        '(property "Reference" "C3"\n\t\t\t(at 77.47 113.0299 0)',
    )
    text = re.sub(
        r'(\(symbol[^\n]*\n\t\t\(lib_id "PCM_Capacitor_AKL:C_0603"\n\t\t\(at 73\.66 114\.3 0\).*?\(property "Footprint" ")[^"]+(")',
        r'\1Capacitor_THT:CP_Radial_D5.0mm_P2.50mm\2',
        text,
        count=1,
        flags=re.S,
    )

    wire_block = ""
    for (x1, y1), (x2, y2) in NEW_WIRES:
        wire_block += f"""\t(wire
\t\t(pts
\t\t\t(xy {x1} {y1}) (xy {x2} {y2})
\t\t)
\t\t(stroke
\t\t\t(width 0)
\t\t\t(type default)
\t\t)
\t\t(uuid "{uid()}")
\t)
"""
    junc_block = ""
    for x, y in NEW_JUNCTIONS:
        junc_block += f"""\t(junction
\t\t(at {x} {y})
\t\t(diameter 0)
\t\t(color 0 0 0 0)
\t\t(uuid "{uid()}")
\t)
"""

    marker = "\t(wire\n\t\t(pts\n\t\t\t(xy 53.34 48.26) (xy 55.88 48.26)"
    if "xy 128.27 68.58)" not in text:
        text = text.replace(marker, junc_block + wire_block + marker, 1)

    SCH.write_text(text, encoding="utf-8")
    print("Schematic updated")


def pad_pos(fp_at, pad_at, rot_deg):
    import math

    r = math.radians(rot_deg)
    px, py = pad_at
    cx, cy = fp_at
    rx = px * math.cos(r) - py * math.sin(r)
    ry = px * math.sin(r) + py * math.cos(r)
    return (cx + rx, cy + ry)


def parse_footprints(pcb_text):
    fps = {}
    for m in re.finditer(
        r'\(footprint "([^"]+)"\s*\n\t\t\(layer "F\.Cu"\)\s*\n\t\t\(uuid "[^"]+"\)\s*\n\t\t\(at ([\d.-]+) ([\d.-]+)(?: ([\d.-]+))?\)',
        pcb_text,
    ):
        fp_name = m.group(1)
        x, y = float(m.group(2)), float(m.group(3))
        rot = float(m.group(4) or 0)
        start = m.end()
        ref_m = re.search(r'\(property "Reference" "([^"]+)"', pcb_text[start : start + 4000])
        if not ref_m:
            continue
        ref = ref_m.group(1)
        pads = []
        fp_chunk = pcb_text[start : start + 12000]
        for pm in re.finditer(
            r'\(pad "([^"]+)" [^\n]*\n(?:[^\n]*\n)*?\s*\(at ([\d.-]+) ([\d.-]+)(?: ([\d.-]+))?\)[^\n]*\n(?:[^\n]*\n)*?\s*\(net \d+ "([^"]+)"\)',
            fp_chunk,
        ):
            pad_n, px, py, prot, net = pm.group(1), float(pm.group(2)), float(pm.group(3)), pm.group(4), pm.group(5)
            prot = float(prot or 0)
            ax, ay = pad_pos((x, y), (px, py), rot + prot)
            pads.append({"num": pad_n, "x": ax, "y": ay, "net": net})
        fps[ref] = {"x": x, "y": y, "rot": rot, "pads": pads, "fp": fp_name}
    return fps


def seg(x1, y1, x2, y2, net, width=0.4):
    return f"""\t(segment
\t\t(start {x1} {y1})
\t\t(end {x2} {y2})
\t\t(width {width})
\t\t(layer "F.Cu")
\t\t(net {net})
\t\t(uuid "{uid()}")
\t)
"""


def route_chain(points, net, width=0.4):
    out = []
    for a, b in zip(points, points[1:]):
        out.append(seg(a[0], a[1], b[0], b[1], net, width))
    return out


def find_pad(fps, ref, num):
    for p in fps[ref]["pads"]:
        if p["num"] == str(num):
            return (p["x"], p["y"])
    raise KeyError(ref, num)


def fix_pcb():
    text = PCB.read_text(encoding="utf-8")

    # Rename nets for SCART switch and audio gnd
    text = text.replace('(net 23 "unconnected-(J2-Pad8)")', '(net 23 "+12V_SW")')
    text = text.replace('(net 29 "unconnected-(J2-Pad4)")', '(net 29 "GND")')
    text = text.replace('(net 23 "unconnected-(J2-Pad8)")', '(net 23 "+12V_SW")')

    # Add R16 footprint before closing if missing
    if '"R16"' not in text:
        r16 = """
\t(footprint "Resistor_SMD:R_0201_0603Metric"
\t\t(layer "F.Cu")
\t\t(uuid "{u}")
\t\t(at 79.0 58.5)
\t\t(property "Reference" "R16"
\t\t\t(at 0 -1.05 0)
\t\t\t(layer "F.SilkS")
\t\t\t(uuid "{u2}")
\t\t\t(effects (font (size 1 1) (thickness 0.15)))
\t\t)
\t\t(property "Value" "1K"
\t\t\t(at 0 1.05 0)
\t\t\t(layer "F.Fab")
\t\t\t(uuid "{u3}")
\t\t\t(effects (font (size 1 1) (thickness 0.15)))
\t\t)
\t\t(path "/edefffed-924d-44e5-b853-9a60a47df57a")
\t\t(sheetname "/")
\t\t(sheetfile "avconver.kicad_sch")
\t\t(attr smd)
\t\t(pad "1" smd roundrect
\t\t\t(at -0.32 0)
\t\t\t(size 0.46 0.4)
\t\t\t(layers "F.Cu" "F.Mask")
\t\t\t(roundrect_rratio 0.25)
\t\t\t(net 6 "Net-(D1-K)")
\t\t\t(pintype "passive")
\t\t\t(uuid "{u4}")
\t\t)
\t\t(pad "2" smd roundrect
\t\t\t(at 0.32 0)
\t\t\t(size 0.46 0.4)
\t\t\t(layers "F.Cu" "F.Mask")
\t\t\t(roundrect_rratio 0.25)
\t\t\t(net 23 "+12V_SW")
\t\t\t(pintype "passive")
\t\t\t(uuid "{u5}")
\t\t)
\t\t(embedded_fonts no)
\t)
""".format(u=uid(), u2=uid(), u3=uid(), u4=uid(), u5=uid())
        text = text.replace("\t(embedded_fonts no)\n)", r16 + "\t(embedded_fonts no)\n)", 1)

    # Update J2 pad nets
    text = re.sub(
        r'(\(pad "8" thru_hole circle[\s\S]*?\(net )23 ("[^"]+")',
        r'\g<1>23 "+12V_SW"',
        text,
        count=1,
    )
    text = re.sub(
        r'(\(pad "4" thru_hole circle[\s\S]*?\(net )29 ("[^"]+")',
        r'\g<1>2 "GND"',
        text,
        count=1,
    )

    fps = parse_footprints(text)
    net_map = {}
    for m in re.finditer(r'\(net (\d+) "([^"]+)"\)', text):
        net_map[m.group(2)] = int(m.group(1))

    routes = []

    def net_id(name):
        return net_map.get(name, 0)

    # GND zone outline + edge cuts
    edge = """
\t(gr_rect
\t\t(start 40 34)
\t\t(end 118 100)
\t\t(stroke (width 0.1) (type default))
\t\t(fill no)
\t\t(layer "Edge.Cuts")
\t\t(uuid "{u}")
\t)
""".format(u=uid())
    if "Edge.Cuts" not in text or 'layer "Edge.Cuts"' not in text:
        pass
    text = re.sub(
        r'\t\(gr_rect\n\t\t\(start 41\.5 36\.8\)\n\t\t\(end 114\.9 99\.1\)[\s\S]*?\(layer "F\.Cu"\)',
        edge.strip(),
        text,
        count=1,
    )

    # Remove erroneous F.Cu rect if still present
    text = re.sub(
        r'\t\(gr_rect\n\t\t\(start 41\.5 36\.8\)\n\t\t\(end 114\.9 99\.1\)[\s\S]*?\(layer "F\.Cu"\)\n\t\t\(uuid "[^"]+"\)\n\t\)\n',
        "",
        text,
        count=1,
    )

    gnd = net_id("GND")
    v12 = net_id("Net-(D1-K)")
    sw = net_id("+12V_SW")

    try:
        # Pin4 already GND pad - route from nearby GND pad5
        p4 = find_pad(fps, "J2", "4")
        p5 = find_pad(fps, "J2", "5")
        routes += route_chain([p5, p4], gnd, 0.5)

        # 12V: D1-K -> R16 -> J2 pin8
        d1k = find_pad(fps, "D1", "1")
        r16_1 = find_pad(fps, "R16", "1") if "R16" in fps else (79.0 - 0.32, 58.5)
        r16_2 = find_pad(fps, "R16", "2") if "R16" in fps else (79.0 + 0.32, 58.5)
        p8 = find_pad(fps, "J2", "8")
        routes += route_chain([d1k, (d1k[0], 58.5), r16_1], v12, 0.5)
        routes += route_chain([r16_1, r16_2], v12, 0.5)
        routes += route_chain([r16_2, (r16_2[0], p8[1]), p8], sw, 0.5)

        # GND bus along bottom
        gnd_pts = []
        for ref in ["J1", "IC1", "IC2", "J2", "J3"]:
            if ref not in fps:
                continue
            for p in fps[ref]["pads"]:
                if p["net"] == "GND":
                    gnd_pts.append((p["x"], p["y"]))
        if gnd_pts:
            xs = sorted(set(round(p[0], 1) for p in gnd_pts))
            y = min(p[1] for p in gnd_pts) - 2
            chain = [(xs[0], y)]
            for x in xs:
                chain.append((x, y))
            routes += route_chain(chain, gnd, 0.8)

        # VGA RGB direct (already same net) - stitch J1 to J2
        for j1, j2, netname in [("1", "15", "Net-(J1-Pad1)"), ("2", "11", "Net-(J1-Pad2)"), ("3", "7", "Net-(J1-Pad3)")]:
            n = net_id(netname)
            a = find_pad(fps, "J1", j1)
            b = find_pad(fps, "J2", j2)
            mid = ((a[0] + b[0]) / 2, a[1])
            routes += route_chain([a, mid, (mid[0], b[1]), b], n, 0.4)

        # Sync HS/VS J1 -> IC2
        for j1p, nname in [("13", "Net-(IC2-1A)"), ("14", "Net-(IC2-2A)")]:
            n = net_id(nname)
            a = find_pad(fps, "J1", j1p)
            ic = find_pad(fps, "IC2", "1" if "1A" in nname else "4")
            routes += route_chain([a, (a[0], ic[1]), ic], n, 0.35)

        # 5V J1-9 -> IC1 VIN
        n = net_id("Net-(IC1-VIN)")
        a = find_pad(fps, "J1", "9")
        b = find_pad(fps, "IC1", "5")
        routes += route_chain([a, (b[0], a[1]), b], n, 0.5)

    except KeyError as e:
        print("Routing warning:", e)

    if routes and "(segment" not in text:
        insert = "\n".join(routes)
        text = text.replace("\t(embedded_fonts no)\n)", insert + "\n\t(embedded_fonts no)\n)", 1)

    # Single layer: disable B.Cu usage note in setup - keep B.Cu for optional GND pour user can add
    PCB.write_text(text, encoding="utf-8")
    print("PCB updated with routes")


if __name__ == "__main__":
    fix_schematic()
    fix_pcb()
