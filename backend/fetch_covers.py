# Download libretro Named_Boxarts into roms/<system>/media/mixrbv2/
# Names are saved as the ROM stem so the menu matcher hits exactly.

from __future__ import annotations

import html
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "backend"))

import arcadebox  # noqa: E402

UA = "ArcadeBox/1.0 (libretro thumbnail fetch)"
BASE = "https://thumbnails.libretro.com"
TIMEOUT = 25
WORKERS = 10
FBNEO_TITLES: dict[str, str] = {}

PLAYLISTS = {
    "atari2600": ["Atari - 2600"],
    "nes": ["Nintendo - Nintendo Entertainment System"],
    "snes": ["Nintendo - Super Nintendo Entertainment System"],
    "megadrive": ["Sega - Mega Drive - Genesis"],
    "arcade": ["FBNeo - Arcade Games", "MAME"],
    "neogeo": ["SNK - Neo Geo", "FBNeo - Arcade Games"],
    "psx": ["Sony - PlayStation"],
}


def sanitize(name: str) -> str:
    out = name
    for char in "&*/:`<>?\\|":
        out = out.replace(char, "_")
    return out


def fetch_bytes(url: str) -> bytes | None:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as response:
            if response.status != 200:
                return None
            data = response.read()
            return data if data else None
    except (urllib.error.URLError, TimeoutError, ValueError):
        return None


def playlist_url(playlist: str, filename: str) -> str:
    system = urllib.parse.quote(playlist, safe="")
    file_part = urllib.parse.quote(filename, safe="")
    return f"{BASE}/{system}/Named_Boxarts/{file_part}"


def load_index(playlist: str) -> list[str]:
    url = f"{BASE}/{urllib.parse.quote(playlist, safe='')}/Named_Boxarts/"
    raw = fetch_bytes(url)
    if not raw:
        print(f"  index fail: {playlist}")
        return []
    text = raw.decode("utf-8", "replace")
    names = []
    for hit in re.findall(r'href="([^"]+\.png)"', text, flags=re.I):
        name = urllib.parse.unquote(html.unescape(hit)).replace("\\", "/")
        name = Path(name).name
        if name.lower().endswith(".png"):
            names.append(name)
    print(f"  {playlist}: {len(names)} boxart")
    return names


def flex_key(text: str) -> str:
    key = arcadebox.normalize(text)
    key = key.replace(" and ", " ")
    key = re.sub(r"\b(the|a|an)\b", " ", key)
    key = key.replace(" wo ", " o ")
    return re.sub(r"\s+", " ", key).strip()


def build_lookup(filenames: list[str]) -> tuple[dict[str, str], dict[str, list[str]]]:
    exact: dict[str, str] = {}
    core: dict[str, list[str]] = {}
    for name in filenames:
        stem = Path(name).stem
        exact[stem.lower()] = name
        key = flex_key(stem)
        if key:
            core.setdefault(key, []).append(name)
    return exact, core


def pick_name(rom_stem: str, extras: list[str], exact: dict[str, str], core: dict[str, list[str]]) -> str | None:
    tried = []
    for candidate in [rom_stem, sanitize(rom_stem), *extras]:
        if not candidate:
            continue
        key = candidate.lower()
        if key in tried:
            continue
        tried.append(key)
        if key in exact:
            return exact[key]
    keys = [flex_key(rom_stem)]
    for extra in extras:
        key = flex_key(extra)
        if key and key not in keys:
            keys.append(key)
    uniq: list[str] = []
    seen: set[str] = set()
    for key in keys:
        for name in core.get(key, []):
            if name not in seen:
                seen.add(name)
                uniq.append(name)
    if not uniq:
        rom_tokens = [tok for tok in arcadebox.tokens(rom_stem) if tok not in {"the", "a", "an"}]
        extra_tokens = []
        for extra in extras:
            extra_tokens = [tok for tok in arcadebox.tokens(extra) if tok not in {"the", "a", "an"}]
            if len(extra_tokens) >= 2:
                rom_tokens = extra_tokens
                break
        if len(rom_tokens) >= 2:
            want = set(rom_tokens)
            sequel = {"2", "3", "4", "5", "ii", "iii", "iv", "x"}
            for names in core.values():
                for name in names:
                    have = set(arcadebox.tokens(Path(name).stem))
                    if not want <= have:
                        continue
                    extra = have - want
                    if extra & sequel and not (want & sequel):
                        continue
                    if name not in seen:
                        seen.add(name)
                        uniq.append(name)
    if not uniq:
        rom_key = flex_key(rom_stem)
        extra_keys = [flex_key(extra) for extra in extras if flex_key(extra)]
        probes = [rom_key, *extra_keys]
        best_key = ""
        for key in core:
            if len(key) < 12:
                continue
            if any(key in probe or probe in key for probe in probes if len(probe) >= 8):
                if len(key) > len(best_key):
                    best_key = key
        for name in core.get(best_key, []):
            if name not in seen:
                seen.add(name)
                uniq.append(name)
    if not uniq:
        return None
    if len(uniq) == 1:
        return uniq[0]
    flags = set(re.findall(r"\(([^)]+)\)", rom_stem.lower()))
    prefer = ["usa", "europe", "world", "japan"]

    def score(name: str) -> tuple:
        stem = Path(name).stem.lower()
        remote_flags = set(re.findall(r"\(([^)]+)\)", stem))
        overlap = len(flags & remote_flags)
        region = next((i for i, tag in enumerate(prefer) if tag in stem), 99)
        return (-overlap, region, len(stem))

    uniq.sort(key=score)
    return uniq[0]


def rom_list(system: dict) -> list[Path]:
    files = list(arcadebox.iter_rom_files(system))
    cues = {path.stem.lower() for path in files if path.suffix.lower() == ".cue"}
    chds = {path.stem.lower() for path in files if path.suffix.lower() == ".chd"}
    rows = []
    for path in files:
        stem = path.stem.lower()
        if path.suffix.lower() == ".bin" and (stem in cues or stem in chds):
            continue
        rows.append(path)
    return rows


def download_one(job: tuple) -> tuple[str, bool, str]:
    dest, playlist, remote_name = job
    dest = Path(dest)
    if dest.exists() and dest.stat().st_size > 800:
        return dest.name, True, "exists"
    data = fetch_bytes(playlist_url(playlist, remote_name))
    if not data or not data.startswith(b"\x89PNG"):
        return dest.name, False, "miss"
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(".part")
    tmp.write_bytes(data)
    tmp.replace(dest)
    return dest.name, True, "ok"


def main() -> None:
    started = time.time()
    global FBNEO_TITLES
    titles_path = ROOT / "data" / "fbneo-titles.json"
    FBNEO_TITLES = arcadebox.load_json(titles_path) if titles_path.exists() else {}
    indexes: dict[str, tuple[str, dict[str, str], dict[str, list[str]]]] = {}
    print("Kataloglar indiriliyor…")
    for system in arcadebox.systems():
        for playlist in PLAYLISTS.get(system["id"], []):
            if playlist in indexes:
                continue
            names = load_index(playlist)
            indexes[playlist] = (playlist, *build_lookup(names))

    jobs = []
    missing_before = 0
    already = 0
    for system in arcadebox.systems():
        playlists = PLAYLISTS.get(system["id"], [])
        if not playlists:
            continue
        out = arcadebox.ROMS / system["romDir"] / "media" / "mixrbv2"
        for rom in rom_list(system):
            if arcadebox.match_cover(system, rom.stem):
                already += 1
                continue
            missing_before += 1
            extras = []
            mapped = arcadebox.arcade_display_title(rom.stem)
            if mapped:
                extras.append(mapped)
            fbneo = FBNEO_TITLES.get(rom.stem.lower())
            if fbneo:
                extras.append(str(fbneo))
            extras.append(arcadebox.pretty_title(rom.stem))
            remote = None
            source = None
            for playlist in playlists:
                pack = indexes.get(playlist)
                if not pack:
                    continue
                name = pick_name(rom.stem, extras, pack[1], pack[2])
                if name:
                    remote = name
                    source = playlist
                    break
            if not remote:
                continue
            dest = out / f"{rom.stem}.png"
            jobs.append((dest, source, remote))

    print(f"Kapak var: {already}  eksik: {missing_before}  indirilecek: {len(jobs)}")
    ok = skip = fail = 0
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = [pool.submit(download_one, job) for job in jobs]
        done = 0
        for fut in as_completed(futures):
            _name, success, kind = fut.result()
            done += 1
            if kind == "exists":
                skip += 1
            elif success:
                ok += 1
            else:
                fail += 1
            if done % 100 == 0 or done == len(futures):
                print(f"  {done}/{len(futures)}  yeni={ok}  atlanan={skip}  yok={fail}")

    print(f"Bitti {time.time() - started:.0f}s  yeni={ok}  atlanan={skip}  bulunamayan={fail}")


if __name__ == "__main__":
    main()
