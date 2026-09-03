# Arcade Box — local kiosk server + silent emulator launcher.
# Serves the custom frontend and starts RetroArch cores in fullscreen.
# Place legally dumped ROMs / BIOS yourself. This file never downloads them.

from __future__ import annotations

import json
import mimetypes
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import webbrowser
import zipfile
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from shutil import which
from urllib.parse import parse_qs, quote, unquote, urlparse

ROOT = Path(__file__).resolve().parent.parent
FRONTEND = ROOT / "frontend"
DATA = ROOT / "data"
ROMS = ROOT / "roms"
BIOS = ROOT / "bios"
MUSIC = ROOT / "music"
CONFIG_PATH = ROOT / "config.json"
EMULATORS = ROOT / "emulators" / "retroarch"

_STATE = {
    "busy": False,
    "gameId": None,
    "process": None,
    "lastError": None,
}
_LOCK = threading.Lock()
_BROWSER_PROC: subprocess.Popen | None = None


def load_json(path: Path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path: Path, payload) -> None:
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def config() -> dict:
    return load_json(CONFIG_PATH)


def systems() -> list:
    return load_json(DATA / "systems.json")


def games() -> list:
    return load_json(DATA / "games.json")


def pretty_title(stem: str) -> str:
    cleaned = re.sub(r"\s*[\(\[][^)\]]*[\)\]]", "", stem)
    cleaned = re.sub(r"[()[\]]+", "", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" -_")
    return cleaned or stem


def year_from_stem(stem: str) -> str:
    hit = re.search(r"\((19\d{2}|20\d{2})\)", stem)
    return hit.group(1) if hit else ""


def file_game_id(system_id: str, filename: str) -> str:
    stem = Path(filename).stem.lower()
    slug = re.sub(r"[^a-z0-9]+", "-", stem).strip("-")[:96]
    return f"file-{system_id}-{slug}"


SKIP_ROM_DIRS = {
    "media",
    "images",
    "covers",
    "boxart",
    "manuals",
    "videos",
    "marquees",
    "screenshots",
    "titlescreens",
    "fanart",
    "wheel",
    "downloaded_images",
    "mixrbv2",
    "archives",
    "_archives",
}
COVER_EXTS = {".png", ".jpg", ".jpeg", ".webp"}
MUSIC_EXTS = {".mp3", ".ogg", ".wav", ".m4a", ".flac"}
PSX_DISC_EXTS = {".chd", ".cue", ".bin", ".iso", ".img", ".pbp", ".mdf"}
_COVER_INDEX: dict[str, dict] = {}
def music_tracks() -> list[str]:
    if not MUSIC.is_dir():
        return []
    names = [
        path.name
        for path in MUSIC.iterdir()
        if path.is_file() and path.suffix.lower() in MUSIC_EXTS
    ]
    names.sort(key=str.lower)
    return names


def resolve_music(name: str) -> Path | None:
    raw = unquote(name or "")
    if not raw or "/" in raw or "\\" in raw or ".." in raw:
        return None
    path = MUSIC / Path(raw).name
    if path.is_file() and path.suffix.lower() in MUSIC_EXTS:
        return path
    return None


def psx_archive_playable(path: Path) -> bool:
    if path.suffix.lower() != ".zip":
        return True
    try:
        with zipfile.ZipFile(path) as archive:
            names = [item.filename.lower() for item in archive.infolist() if not item.is_dir()]
    except zipfile.BadZipFile:
        return False
    if any(Path(name).suffix in PSX_DISC_EXTS for name in names):
        return True
    return False


def iter_rom_files(system: dict):
    folder = ROMS / system["romDir"]
    if not folder.exists():
        return
    extensions = tuple(ext.lower() for ext in system.get("extensions", []))
    skip = {"oku.txt", "neogeo.zip"}
    junk = {".txt", ".dat", ".xml", ".nfo", ".jpg", ".png", ".gif", ".md"}
    for path in folder.rglob("*"):
        if not path.is_file():
            continue
        rel_parts = path.relative_to(folder).parts[:-1]
        if any(part.lower() in SKIP_ROM_DIRS for part in rel_parts):
            continue
        if path.name.lower() in skip:
            continue
        if path.suffix.lower() in junk:
            continue
        if path.suffix.lower() not in extensions:
            continue
        if system["id"] == "psx" and path.suffix.lower() == ".zip" and not psx_archive_playable(path):
            continue
        yield path


def cover_index(system: dict) -> dict:
    cached = _COVER_INDEX.get(system["id"])
    if cached is not None:
        return cached
    exact: dict[str, Path] = {}
    core: dict[str, list[Path]] = {}
    folder = ROMS / system["romDir"]
    if folder.is_dir():
        for path in folder.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in COVER_EXTS:
                continue
            exact[path.stem.lower()] = path
            key = normalize(path.stem)
            if key:
                core.setdefault(key, []).append(path)
    payload = {"exact": exact, "core": core}
    _COVER_INDEX[system["id"]] = payload
    return payload


def _stem_prefix_hit(short: str, long: str) -> bool:
    if long == short:
        return True
    if not long.startswith(short):
        return False
    rest = long[len(short) :]
    return rest.startswith(" (") or rest.startswith("(")


def match_cover(system: dict, rom_stem: str) -> Path | None:
    index = cover_index(system)
    stem = rom_stem.lower()
    hit = index["exact"].get(stem)
    if hit:
        return hit
    for art_stem, path in index["exact"].items():
        if _stem_prefix_hit(stem, art_stem) or _stem_prefix_hit(art_stem, stem):
            return path
    core = normalize(rom_stem)
    cands = index["core"].get(core) or []
    if not cands:
        return None
    if len(cands) == 1:
        return cands[0]
    rom_flags = set(re.findall(r"\(([^)]+)\)", rom_stem.lower()))

    def score(path: Path) -> int:
        flags = set(re.findall(r"\(([^)]+)\)", path.stem.lower()))
        return len(rom_flags & flags)

    cands = sorted(cands, key=score, reverse=True)
    return cands[0]


def cover_url(system: dict, rom_name: str) -> str | None:
    if not match_cover(system, Path(rom_name).stem):
        return None
    return f"/api/cover?system={quote(system['id'])}&rom={quote(rom_name)}"


def resolve_cover(system_id: str, rom_name: str) -> Path | None:
    system = system_by_id(system_id)
    if not system:
        return None
    name = unquote(rom_name or "")
    if not name or "/" in name or "\\" in name or ".." in name:
        return None
    return match_cover(system, Path(name).stem)


_ARCADE_TITLES = None
_ARCADE_YEARS = None


def _arcade_keys(stem: str) -> list[str]:
    raw = stem.lower()
    compact = re.sub(r"[^a-z0-9]+", "", raw)
    keys = [raw]
    if compact and compact != raw:
        keys.append(compact)
    return keys


def load_arcade_db() -> None:
    global _ARCADE_TITLES, _ARCADE_YEARS
    if _ARCADE_TITLES is not None:
        return
    titles_path = DATA / "arcade-titles.json"
    years_path = DATA / "arcade-years.json"
    _ARCADE_TITLES = load_json(titles_path) if titles_path.exists() else {}
    _ARCADE_YEARS = load_json(years_path) if years_path.exists() else {}


def arcade_display_title(stem: str) -> str | None:
    load_arcade_db()
    for key in _arcade_keys(stem):
        hit = _ARCADE_TITLES.get(key)
        if hit:
            return pretty_title(str(hit))
    return None


def arcade_display_year(stem: str) -> str:
    load_arcade_db()
    for key in _arcade_keys(stem):
        hit = _ARCADE_YEARS.get(key)
        if hit:
            return str(hit)
    return ""


_FBNEO_REVERSE = None
_FBNEO_SKIP = re.compile(
    r"(unity|cqi|boot|hack|dd$|dg$|eb$|fd$|ki$|lw$|sc$|zh$|h$)",
    re.I,
)


def fbneo_short_name(stem: str) -> str | None:
    raw = Path(stem).stem.lower()
    if re.fullmatch(r"[a-z0-9]+", raw):
        return raw
    load_arcade_db()
    global _FBNEO_REVERSE
    if _FBNEO_REVERSE is None:
        index: dict[str, list[str]] = {}
        for key, title in (_ARCADE_TITLES or {}).items():
            index.setdefault(normalize(str(title)), []).append(key)
        _FBNEO_REVERSE = index
    want = normalize(pretty_title(stem))
    keys = list(_FBNEO_REVERSE.get(want) or [])
    if not keys:
        for title_key, names in _FBNEO_REVERSE.items():
            if want == title_key or want.startswith(title_key + " ") or title_key.startswith(want + " "):
                keys.extend(names)
    if not keys:
        return None
    keys = list(dict.fromkeys(keys))
    keys.sort(key=lambda k: (0 if not _FBNEO_SKIP.search(k) else 1, len(k), k))
    return keys[0]


def fbneo_alias_rom(rom: Path, system: dict) -> Path:
    if system["id"] not in {"arcade", "neogeo"}:
        return rom
    short = fbneo_short_name(rom.stem)
    if not short or short == rom.stem.lower():
        return rom
    dest = Path("/tmp/arcadebox-cache/fbneo") if os.name != "nt" else Path(os.environ.get("TEMP", ".")) / "arcadebox-fbneo"
    dest.mkdir(parents=True, exist_ok=True)
    aliased = dest / f"{short}{rom.suffix.lower()}"
    try:
        if aliased.exists() or aliased.is_symlink():
            aliased.unlink()
        os.symlink(rom.resolve(), aliased)
        return aliased
    except OSError:
        try:
            shutil.copy2(rom, aliased)
            return aliased
        except OSError:
            return rom


def catalog_with_folder_roms() -> list:
    catalog = games()
    rows = []
    for system in systems():
        files = list(iter_rom_files(system))
        cues = {path.stem.lower() for path in files if path.suffix.lower() == ".cue"}
        chds = {path.stem.lower() for path in files if path.suffix.lower() == ".chd"}
        unpacked = {
            path.stem.lower()
            for path in files
            if path.suffix.lower() not in {".7z", ".zip"}
        }
        for path in files:
            stem = path.stem.lower()
            if system["id"] == "psx" and path.suffix.lower() == ".bin" and (stem in cues or stem in chds):
                continue
            if path.suffix.lower() in {".7z", ".zip"} and stem in unpacked:
                continue
            meta = _catalog_match(catalog, system, path)
            title = pretty_title(path.stem)
            year = year_from_stem(path.stem)
            mapped = arcade_display_title(path.stem)
            mame_like = bool(re.fullmatch(r"[a-z0-9]+", path.stem.lower() or ""))
            if mapped and (system["id"] in {"arcade", "neogeo"} or mame_like):
                title = mapped
                year = year or arcade_display_year(path.stem)
            genre = "ROM"
            players = "1-2"
            if meta:
                if not mapped and (system.get("exactRom") or len(title) < 4):
                    title = meta["title"]
                year = year or str(meta.get("year") or "")
                genre = meta.get("genre") or genre
                players = meta.get("players") or players
            cover = cover_url(system, path.name)
            rows.append(
                {
                    "id": file_game_id(system["id"], path.name),
                    "system": system["id"],
                    "title": title,
                    "year": year,
                    "players": players,
                    "genre": genre,
                    "search": path.stem,
                    "rom": path.name,
                    "cover": cover,
                    "installed": True,
                }
            )
    rows.sort(key=lambda item: (item["system"], item["title"].lower()))
    return rows


def _catalog_match(catalog: list, system: dict, path: Path) -> dict | None:
    best = None
    best_score = -1
    for game in catalog:
        if game["system"] != system["id"]:
            continue
        if system.get("exactRom"):
            want = game["rom"].lower()
            if path.name.lower() == want or path.stem.lower() == Path(game["rom"]).stem.lower():
                return game
            continue
        scored = score_rom(path, game, system)
        if scored > best_score:
            best_score = scored
            best = game
    if best_score >= 500:
        return best
    return None


def system_by_id(system_id: str) -> dict | None:
    for item in systems():
        if item["id"] == system_id:
            return item
    return None


def _launch_id_key(game_id: str) -> str:
    key = (game_id or "").lower()
    return re.sub(r"-(7z|zip|bin|a26|rom|nes|unf|sfc|smc|md|gen|cue|chd|iso)$", "", key)


def game_by_id(game_id: str) -> dict | None:
    library = catalog_with_folder_roms()
    for item in library:
        if item["id"] == game_id:
            return item
    want = _launch_id_key(game_id)
    for item in library:
        if _launch_id_key(item["id"]) == want:
            return item
    for item in games():
        if item["id"] == game_id:
            system = system_by_id(item["system"])
            rom = find_rom(item, system) if system else None
            if not rom:
                return None
            row = dict(item)
            row["rom"] = rom.name
            row["installed"] = True
            return row
    return None


def normalize(text: str) -> str:
    text = text.lower().replace("&", " and ")
    text = re.sub(r"['’!.]", "", text)
    text = re.sub(r"\[[^\]]*\]|\([^)]*\)", " ", text)
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def tokens(text: str) -> list[str]:
    return [part for part in normalize(text).split(" ") if part]


def extra_sequel(file_tokens: list[str], search_tokens: list[str]) -> bool:
    leftovers = file_tokens[len(search_tokens) :] if file_tokens[: len(search_tokens)] == search_tokens else []
    if not leftovers:
        # still catch "mario bros 3" when search is "mario bros"
        search_set = set(search_tokens)
        extras = [tok for tok in file_tokens if tok not in search_set]
        leftovers = extras
    sequelish = {"2", "3", "4", "ii", "iii", "iv", "x", "dx", "deluxe"}
    return any(tok in sequelish for tok in leftovers)


def score_rom(path: Path, game: dict, system: dict) -> int:
    name = path.stem
    search = tokens(game.get("search") or game["title"])
    file_tok = tokens(name)
    if not search or not file_tok:
        return -1
    if path.name.lower() == str(game.get("rom", "")).lower():
        return 1000
    if file_tok == search:
        return 900
    if file_tok[: len(search)] == search and not extra_sequel(file_tok, search):
        return 800 - abs(len(file_tok) - len(search))
    if all(tok in file_tok for tok in search) and not extra_sequel(file_tok, search):
        return 500 - abs(len(file_tok) - len(search))
    return -1


def find_rom(game: dict, system: dict) -> Path | None:
    folder = ROMS / system["romDir"]
    if not folder.exists():
        return None
    expected = folder / game["rom"]
    if expected.exists():
        return expected

    extensions = tuple(ext.lower() for ext in system.get("extensions", []))
    candidates: list[tuple[int, Path]] = []
    for path in folder.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in extensions:
            continue
        if system.get("exactRom"):
            if path.name.lower() == game["rom"].lower():
                return path
            continue
        scored = score_rom(path, game, system)
        if scored >= 0:
            candidates.append((scored, path))
    if not candidates:
        return None
    candidates.sort(key=lambda item: (-item[0], len(item[1].name)))
    return candidates[0][1]


def _archive_extract_cmd(archive: Path, dest: Path) -> list[str] | None:
    dest.mkdir(parents=True, exist_ok=True)
    if archive.suffix.lower() == ".zip":
        return None
    for bin_name in ("7z", "7za", "7zr"):
        found = which(bin_name)
        if found:
            return [found, "e", "-y", f"-o{dest}", str(archive)]
    found = which("bsdtar")
    if found:
        return [found, "-xf", str(archive), "-C", str(dest)]
    return []


def _sibling_unpacked(archive: Path, system: dict) -> Path | None:
    inner = [
        ext.lower()
        for ext in system.get("extensions", [])
        if ext.lower() not in {".7z", ".zip"}
    ]
    for ext in inner:
        candidate = archive.with_suffix(ext)
        if candidate.is_file():
            return candidate
    return None


def unpack_rom(rom: Path, system: dict) -> Path:
    """Stella (and some cores) cannot load .7z; extract a raw dump first."""
    ext = rom.suffix.lower()
    if ext not in {".7z", ".zip"}:
        return rom
    sibling = _sibling_unpacked(rom, system)
    if sibling:
        return sibling
    inner_exts = tuple(e.lower() for e in system.get("extensions", []) if e.lower() not in {".7z", ".zip"})
    if not inner_exts:
        inner_exts = (".bin", ".a26", ".rom", ".nes", ".unf", ".sfc", ".smc", ".md", ".gen")
    cache = Path("/tmp/arcadebox-cache") if os.name != "nt" else Path(os.environ.get("TEMP", ".") ) / "arcadebox-cache"
    dest = cache / "unpacked" / system.get("id", "rom") / rom.stem
    if dest.exists():
        hits = [p for p in dest.rglob("*") if p.is_file() and p.suffix.lower() in inner_exts]
        if hits:
            return max(hits, key=lambda p: p.stat().st_size)
    dest.mkdir(parents=True, exist_ok=True)
    try:
        if ext == ".zip":
            with zipfile.ZipFile(rom) as archive:
                archive.extractall(dest)
        else:
            cmd = _archive_extract_cmd(rom, dest)
            if not cmd:
                return rom
            subprocess.run(cmd, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, zipfile.BadZipFile):
        return rom
    hits = [p for p in dest.rglob("*") if p.is_file() and p.suffix.lower() in inner_exts]
    if not hits:
        return rom
    return max(hits, key=lambda p: p.stat().st_size)


def resolve_path(value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = (ROOT / path).resolve()
    return path


def _core_exts() -> tuple[str, ...]:
    if os.name == "nt":
        return (".dll",)
    return (".so", ".dylib")


def _dir_has_cores(path: Path) -> bool:
    if not path.is_dir():
        return False
    exts = _core_exts()
    return any(item.is_file() and item.suffix.lower() in exts for item in path.iterdir())


def retroarch_exe() -> Path | None:
    names = []
    cfg = config().get("retroarch", {})
    if cfg.get("exe"):
        names.append(resolve_path(cfg["exe"]))
    names.extend(
        [
            EMULATORS / ("retroarch.exe" if os.name == "nt" else "retroarch"),
            Path("C:/RetroArch/retroarch.exe"),
            Path("/usr/bin/retroarch"),
            Path("/usr/local/bin/retroarch"),
        ]
    )
    for path in names:
        if path.exists():
            return path
    found = which("retroarch")
    return Path(found) if found else None


def core_search_dirs() -> list[Path]:
    cfg = config().get("retroarch", {})
    candidates = []
    if cfg.get("cores"):
        candidates.append(resolve_path(cfg["cores"]))
    exe = retroarch_exe()
    if exe:
        candidates.append(exe.parent / "cores")
    home = Path.home() / ".config" / "retroarch" / "cores"
    candidates.extend(
        [
            home,
            Path("/usr/lib/aarch64-linux-gnu/libretro"),
            Path("/usr/lib/arm-linux-gnueabihf/libretro"),
            Path("/usr/lib/x86_64-linux-gnu/libretro"),
            Path("/usr/lib/libretro"),
            Path("/usr/lib/retroarch/cores"),
            EMULATORS / "cores",
        ]
    )
    seen: list[Path] = []
    for path in candidates:
        resolved = path.resolve() if path.exists() else path
        if resolved not in seen:
            seen.append(resolved)
    return seen


def cores_dir() -> Path:
    for path in core_search_dirs():
        if _dir_has_cores(path):
            return path
    return EMULATORS / "cores"


def find_core(system: dict) -> Path | None:
    stems = []
    for name in system.get("cores", []):
        stem = Path(name).stem
        if stem not in stems:
            stems.append(stem)
    if os.name != "nt" and system.get("id") == "atari2600":
        preferred = [s for s in stems if "2014" in s]
        stems = preferred + [s for s in stems if s not in preferred]
    exts = _core_exts()
    for folder in core_search_dirs():
        if not folder.is_dir():
            continue
        for stem in stems:
            for ext in exts:
                candidate = folder / f"{stem}{ext}"
                if candidate.is_file():
                    return candidate
    for folder in core_search_dirs():
        if not folder.is_dir():
            continue
        keys = []
        if system.get("id") == "atari2600":
            keys = ["stella2014", "stella"]
        else:
            keys = [stem.replace("_libretro", "").split("_")[0] for stem in stems]
        for key in keys:
            if len(key) < 3:
                continue
            for ext in exts:
                hits = sorted(folder.glob(f"*{key}*{ext}"))
                if hits:
                    return hits[0]
    return None


def bios_status(system: dict) -> dict:
    needed = []
    found = []
    if system.get("biosFile"):
        needed.append(system["biosFile"])
        locations = [
            ROMS / system["romDir"] / system["biosFile"],
            BIOS / system["romDir"] / system["biosFile"],
        ]
        if any(path.exists() for path in locations):
            found.append(system["biosFile"])
    if system.get("biosDir") == "psx":
        needed.append("PS1 BIOS (scph1001.bin / scph5501.bin / scph5502.bin)")
        bios_dir = BIOS / "psx"
        hits = []
        if bios_dir.exists():
            hits = [
                path.name
                for path in bios_dir.iterdir()
                if path.is_file() and path.suffix.lower() in {".bin", ".rom"}
            ]
        if hits:
            found.extend(hits)
    return {"needed": needed, "found": found, "ok": not needed or bool(found)}


def rom_inventory() -> dict[str, bool]:
    present = {}
    for game in games():
        system = system_by_id(game["system"])
        present[game["id"]] = bool(system and find_rom(game, system))
    return present


def launch_game(game_id: str) -> dict:
    game = game_by_id(game_id)
    if not game:
        return {"ok": False, "error": "Oyun katalogda yok."}
    system = system_by_id(game["system"])
    if not system:
        return {"ok": False, "error": "Sistem tanımı yok."}

    exe = retroarch_exe()
    if not exe:
        return {
            "ok": False,
            "error": "RetroArch yok. Portable kopyayı emulators/retroarch klasörüne koy.",
        }

    core = find_core(system)
    if not core:
        ext = _core_exts()[0]
        wanted = ", ".join(f"{Path(name).stem}{ext}" for name in system.get("cores", []))
        return {
            "ok": False,
            "error": f"{system['name']} core yok. Beklenen: {wanted}",
        }

    rom = find_rom(game, system)
    if not rom:
        return {
            "ok": False,
            "error": f"ROM yok. Yasal dump dosyasını şuraya koy: roms/{system['romDir']}/",
            "missing": True,
            "folder": str(ROMS / system["romDir"]),
        }
    rom = unpack_rom(rom, system)
    if rom.suffix.lower() in {".7z", ".zip"} and system["id"] == "atari2600":
        return {
            "ok": False,
            "error": "Atari 7z açılamadı. SSH: sudo apt-get install -y p7zip-full",
        }
    rom = fbneo_alias_rom(rom, system)

    bios = bios_status(system)
    if bios["needed"] and not bios["ok"]:
        return {
            "ok": False,
            "error": f"BIOS eksik: {', '.join(bios['needed'])}",
            "missing": True,
        }

    with _LOCK:
        if _STATE["busy"]:
            return {"ok": False, "error": "Bir oyun zaten açık."}
        _STATE["busy"] = True
        _STATE["gameId"] = game_id
        _STATE["lastError"] = None

    override = ROOT / "config" / "runtime.cfg"
    override.parent.mkdir(parents=True, exist_ok=True)
    if system["id"] == "psx":
        sysdir = (BIOS / "psx").as_posix()
    else:
        sysdir = rom.parent.as_posix()
    lines = [
        'rgui_show_start_screen = "false"',
        'quit_press_twice = "false"',
        'video_fullscreen = "true"',
        'video_font_enable = "false"',
        'pause_nonactive = "false"',
        'video_vsync = "true"',
        'video_hard_sync = "false"',
        'video_threaded = "false"',
        'video_swap_interval = "1"',
        'video_refresh_rate = "50"',
        'video_autoswitch_refresh_rate = "0"',
        'vrr_runloop_enable = "false"',
        'run_ahead_enabled = "false"',
        'audio_enable = "true"',
        'audio_sync = "true"',
        'audio_rate_control = "true"',
        'fastforward_ratio = "1.0"',
        'input_toggle_fast_forward = "nul"',
        'input_hold_fast_forward = "nul"',
        'input_toggle_slowmotion = "nul"',
        'input_hold_slowmotion = "nul"',
        'rewind_enable = "false"',
        'video_smooth = "false"',
        'video_scale_integer = "false"',
        'aspect_ratio_index = "0"',
        'custom_viewport_width = "800"',
        'custom_viewport_height = "600"',
        f'system_directory = "{sysdir}"',
        f'rgui_browser_directory = "{sysdir}"',
    ]
    if os.name != "nt":
        cache = Path("/tmp/arcadebox-cache")
        cache.mkdir(parents=True, exist_ok=True)
        lines.extend(
            [
                'video_driver = "gl"',
                'audio_driver = "alsa"',
                f'cache_directory = "{cache.as_posix()}"',
            ]
        )
    override.write_text("\n".join(lines) + "\n", encoding="utf-8")

    args = [str(exe), "--verbose", "-L", str(core), "-f", "--appendconfig", str(override), str(rom)]
    creationflags = 0
    popen_env = os.environ.copy()
    popen_env.pop("vblank_mode", None)
    if os.name == "nt":
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

    log_path = Path("/tmp/arcadebox-launch.log") if os.name != "nt" else ROOT / "config" / "launch.log"
    try:
        log_handle = log_path.open("ab", buffering=0)
        log_handle.write(f"\n--- {game['title']} core={core} rom={rom}\n".encode("utf-8", "replace"))
    except OSError:
        log_handle = subprocess.DEVNULL

    try:
        process = subprocess.Popen(
            args,
            cwd=str(ROOT),
            creationflags=creationflags,
            env=popen_env,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
        )
    except OSError as exc:
        if hasattr(log_handle, "close"):
            log_handle.close()
        with _LOCK:
            _STATE["busy"] = False
            _STATE["gameId"] = None
            _STATE["lastError"] = str(exc)
        return {"ok": False, "error": f"Emülatör başlatılamadı: {exc}"}

    with _LOCK:
        _STATE["process"] = process

    def _pause_later() -> None:
        time.sleep(4)
        if process.poll() is None:
            pause_kiosk_browser(True)

    threading.Thread(target=_pause_later, daemon=True).start()
    started = time.time()

    def watch() -> None:
        code = process.wait()
        pause_kiosk_browser(False)
        if hasattr(log_handle, "close"):
            try:
                log_handle.close()
            except OSError:
                pass
        elapsed = time.time() - started
        with _LOCK:
            if elapsed < 8:
                _STATE["lastError"] = (
                    f"{system['name']} {elapsed:.1f}sn içinde kapandı (kod {code}). "
                    "2 Pak deneme; Pac-Man dene. Log: /tmp/arcadebox-launch.log"
                )
            _STATE["busy"] = False
            _STATE["gameId"] = None
            _STATE["process"] = None

    threading.Thread(target=watch, daemon=True).start()
    return {
        "ok": True,
        "game": game["title"],
        "system": system["name"],
        "core": core.name,
        "rom": rom.name,
    }


def status_payload() -> dict:
    with _LOCK:
        process = _STATE["process"]
        busy = _STATE["busy"] and process is not None and process.poll() is None
        return {
            "busy": busy,
            "gameId": _STATE["gameId"] if busy else None,
            "lastError": _STATE["lastError"],
        }


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(FRONTEND), **kwargs)

    def log_message(self, format: str, *args) -> None:
        sys.stderr.write("ArcadeBox: " + (format % args) + "\n")

    def _json(self, payload: dict, code: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/api/catalog":
            library = catalog_with_folder_roms()
            payload = {
                "systems": systems(),
                "games": library,
                "status": status_payload(),
                "bios": {item["id"]: bios_status(item) for item in systems()},
                "config": {
                    "pi": Path("/sys/firmware/devicetree/base/model").exists(),
                    "retroarchExists": retroarch_exe() is not None,
                    "idleDemoSeconds": config().get("idleDemoSeconds", 40),
                    "controls": config().get("controls", {}),
                    "crtFx": config().get("crtFx", {}),
                },
                "music": music_tracks(),
            }
            self._json(payload)
            return
        if parsed.path == "/api/status":
            self._json(status_payload())
            return
        if parsed.path == "/api/cover":
            qs = parse_qs(parsed.query)
            system_id = (qs.get("system") or [""])[0]
            rom_name = (qs.get("rom") or [""])[0]
            path = resolve_cover(system_id, rom_name)
            if not path or not path.is_file():
                self.send_error(404, "Kapak yok")
                return
            mime = mimetypes.guess_type(path.name)[0] or "image/png"
            data = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", mime)
            self.send_header("Cache-Control", "public, max-age=86400")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if parsed.path == "/api/music":
            qs = parse_qs(parsed.query)
            name = (qs.get("file") or [""])[0]
            path = resolve_music(name)
            if not path:
                self.send_error(404, "Parça yok")
                return
            mime = mimetypes.guess_type(path.name)[0] or "audio/mpeg"
            data = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", mime)
            self.send_header("Cache-Control", "public, max-age=3600")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        return super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            body = {}

        if parsed.path == "/api/launch":
            result = launch_game(str(body.get("id") or parse_qs(parsed.query).get("id", [""])[0]))
            self._json(result, 200 if result.get("ok") else 400)
            return
        if parsed.path == "/api/config":
            current = config()
            if "exe" in body:
                current["retroarch"]["exe"] = body["exe"]
                current["retroarch"]["cores"] = str(Path(body["exe"]).parent / "cores")
            if "controls" in body and isinstance(body["controls"], dict):
                current["controls"] = body["controls"]
            if "crtFx" in body and isinstance(body["crtFx"], dict):
                current["crtFx"] = body["crtFx"]
            save_json(CONFIG_PATH, current)
            self._json({"ok": True, "config": current})
            return
        self._json({"ok": False, "error": "Bilinmeyen istek."}, 404)


def find_browser() -> list[str] | None:
    if os.name == "nt":
        candidates = [
            os.path.expandvars(r"%ProgramFiles%\Google\Chrome\Application\chrome.exe"),
            os.path.expandvars(r"%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"),
            os.path.expandvars(r"%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"),
            os.path.expandvars(r"%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"),
        ]
        for path in candidates:
            if Path(path).exists():
                name = Path(path).name.lower()
                if "msedge" in name:
                    return [path, "--kiosk", "--edge-kiosk-type=fullscreen", "--no-first-run"]
                return [path, "--kiosk", "--no-first-run", "--disable-features=Translate"]
        return None
    for binary in ("chromium", "chromium-browser", "google-chrome", "firefox"):
        found = which(binary)
        if found and binary == "firefox":
            return [found, "--kiosk"]
        if found:
            flags = [
                "--kiosk",
                "--noerrdialogs",
                "--disable-infobars",
                "--incognito",
                "--no-first-run",
                "--disable-session-crashed-bubble",
                "--check-for-update-interval=31536000",
                "--disable-features=Translate,TranslateUI",
            ]
            if Path("/sys/firmware/devicetree/base/model").exists():
                flags.extend(
                    [
                        "--ozone-platform=x11",
                        "--start-fullscreen",
                        "--disable-background-networking",
                        "--disable-component-update",
                        "--disable-sync",
                        "--num-raster-threads=1",
                        "--enable-low-end-device-mode",
                        "--disable-gpu-rasterization",
                    ]
                )
            return [found, *flags]
    return None


def pause_kiosk_browser(pause: bool) -> None:
    if os.name == "nt" or _BROWSER_PROC is None or _BROWSER_PROC.poll() is not None:
        return
    sig = signal.SIGSTOP if pause else signal.SIGCONT
    try:
        os.killpg(_BROWSER_PROC.pid, sig)
    except OSError:
        try:
            os.kill(_BROWSER_PROC.pid, sig)
        except OSError:
            pass


def open_kiosk(url: str) -> None:
    global _BROWSER_PROC
    command = find_browser()
    if not command:
        webbrowser.open(url)
        return
    _BROWSER_PROC = subprocess.Popen(command + [url], cwd=str(ROOT), start_new_session=True)


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    cfg = config()
    port = int(cfg.get("port", 7842))
    kiosk = cfg.get("kiosk") or ("--kiosk" in sys.argv)
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    url = f"http://127.0.0.1:{port}/"
    print("Arcade Box OS  ->  " + url)
    print("ROM klasoru    ->  " + str(ROMS))
    print("Emulator       ->  " + str(retroarch_exe() or (EMULATORS / "retroarch")))
    if "--no-browser" not in sys.argv:
        if kiosk:
            open_kiosk(url)
        else:
            webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nKapatildi.")


if __name__ == "__main__":
    main()
