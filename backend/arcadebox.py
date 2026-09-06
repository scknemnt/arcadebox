# Arcade Box — local kiosk server + silent emulator launcher.
# Serves the custom frontend and starts RetroArch cores in fullscreen.
# Place legally dumped ROMs / BIOS yourself. This file never downloads them.

from __future__ import annotations

import json
import math
import mimetypes
import os
import platform
import re
import shlex
import shutil
import signal
import struct
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
PANDORA_MUSIC = FRONTEND / "media" / "pandora" / "music"
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
_JSON_MEMO: dict[str, object] = {}
_CATALOG_LOCK = threading.Lock()
_CATALOG_GAMES: list | None = None
_CATALOG_READY = False
_CATALOG_BUILDING = False
_COVER_LOCK = threading.Lock()


def load_json(path: Path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path: Path, payload) -> None:
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    key = str(path.resolve())
    if key in _JSON_MEMO:
        _JSON_MEMO[key] = payload


def _memo_json(path: Path):
    key = str(path.resolve())
    cached = _JSON_MEMO.get(key)
    if cached is not None:
        return cached
    data = load_json(path)
    _JSON_MEMO[key] = data
    return data


def config() -> dict:
    return load_json(CONFIG_PATH)


def systems() -> list:
    return _memo_json(DATA / "systems.json")


def games() -> list:
    return _memo_json(DATA / "games.json")


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


def _music_dir_names(folder: Path, prefix: str = "") -> list[str]:
    if not folder.is_dir():
        return []
    out = []
    for path in folder.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in MUSIC_EXTS:
            continue
        rel = path.relative_to(folder).as_posix()
        if any(part == ".." for part in rel.split("/")):
            continue
        out.append(f"{prefix}{rel}" if prefix else rel)
    return out


def music_tracks() -> list[str]:
    names = _music_dir_names(MUSIC)
    if names:
        names.sort(key=str.lower)
        return names
    names = _music_dir_names(PANDORA_MUSIC, "pandora/")
    names.sort(key=str.lower)
    return names


def _safe_music_path(root: Path, rel: str) -> Path | None:
    if not rel or any(part == ".." for part in rel.replace("\\", "/").split("/")):
        return None
    path = (root / rel).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError:
        return None
    if path.is_file() and path.suffix.lower() in MUSIC_EXTS:
        return path
    return None


def resolve_music(name: str) -> Path | None:
    raw = unquote(name or "")
    if not raw:
        return None
    raw = raw.replace("\\", "/")
    if raw.startswith("pandora/"):
        return _safe_music_path(PANDORA_MUSIC, raw[8:])
    return _safe_music_path(MUSIC, raw)


_AUDIO = {
    "lock": threading.Lock(),
    "bgm_proc": None,
    "wanted": False,
    "path": None,
    "supervisor": False,
}
_SFX_WAV: dict[str, bytes] = {}
_SFX_TONES = {
    "move": (1180, 0.05, 0.55),
    "ok": (880, 0.09, 0.6),
    "back": (360, 0.1, 0.55),
    "launch": (523, 0.14, 0.62),
    "boot": (659, 0.16, 0.6),
    "error": (180, 0.16, 0.6),
}


def _tone_wav(freq: float, seconds: float, volume: float) -> bytes:
    rate = 22050
    count = max(8, int(rate * seconds))
    samples = bytearray()
    for index in range(count):
        env = min(1.0, index / 90.0) * (1.0 - index / count)
        value = int(math.sin(2 * math.pi * freq * index / rate) * volume * env * 32767)
        samples.extend(struct.pack("<h", max(-32767, min(32767, value))))
    header = struct.pack(
        "<4sI4s4sIHHIIHH4sI",
        b"RIFF",
        36 + len(samples),
        b"WAVE",
        b"fmt ",
        16,
        1,
        1,
        rate,
        rate * 2,
        2,
        16,
        b"data",
        len(samples),
    )
    return header + bytes(samples)


def _sfx_wav(kind: str) -> bytes:
    if kind not in _SFX_WAV:
        freq, seconds, volume = _SFX_TONES.get(kind, _SFX_TONES["ok"])
        _SFX_WAV[kind] = _tone_wav(freq, seconds, volume)
    return _SFX_WAV[kind]


def _pick_alsa_device() -> str | None:
    forced = os.environ.get("ARCADEBOX_ALSA_DEVICE")
    if forced:
        return forced
    pcm = Path("/proc/asound/pcm")
    if not pcm.is_file():
        return None
    analog = None
    other = None
    for line in pcm.read_text(encoding="utf-8", errors="replace").splitlines():
        low = line.lower()
        if "playback" not in low:
            continue
        head = line.split(":", 1)[0].strip()
        if "-" not in head:
            continue
        card, device = head.split("-", 1)
        try:
            name = f"plughw:{int(card)},{int(device)}"
        except ValueError:
            continue
        if "hdmi" in low or "displayport" in low:
            continue
        if analog is None and ("analog" in low or "speaker" in low or "alc" in low):
            analog = name
        elif other is None:
            other = name
    return analog or other


def _play_wav_bytes(data: bytes) -> None:
    device = _pick_alsa_device()
    commands = []
    if which("aplay"):
        cmd = ["aplay", "-q", "-t", "wav"]
        if device:
            cmd.extend(["-D", device])
        cmd.append("-")
        commands.append(cmd)
        if device:
            commands.append(["aplay", "-q", "-t", "wav", "-"])
    if which("paplay"):
        commands.append(["paplay", "--file-format=wav"])
    if which("pw-play"):
        commands.append(["pw-play", "-"])
    for command in commands:
        try:
            proc = subprocess.Popen(
                command,
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            assert proc.stdin is not None
            proc.stdin.write(data)
            proc.stdin.close()
            return
        except OSError:
            continue


def _playlist_paths() -> list[Path]:
    paths = []
    for name in music_tracks():
        found = resolve_music(name)
        if found:
            paths.append(found)
    if paths:
        return paths
    for path in (
        FRONTEND / "media" / "menu-ambient.wav",
        FRONTEND / "media" / "pandora" / "music" / "menu-ambient.wav",
    ):
        if path.is_file():
            return [path]
    return []


def default_bgm_path(name: str = "") -> Path | None:
    if name and name != "__builtin__":
        found = resolve_music(name)
        if found:
            return found
    tracks = _playlist_paths()
    return tracks[0] if tracks else None


def _next_bgm_path(current: Path | None) -> Path | None:
    tracks = _playlist_paths()
    if not tracks:
        return None
    if current is None or current not in tracks:
        return tracks[0]
    return tracks[(tracks.index(current) + 1) % len(tracks)]


def _spawn_bgm(path: Path) -> subprocess.Popen | None:
    device = _pick_alsa_device()
    suffix = path.suffix.lower()
    wav_only = suffix == ".wav"
    commands: list[list[str]] = []
    if suffix == ".mp3" and which("mpg123"):
        commands.append(["mpg123", "-q", str(path)])
        if device:
            commands.append(["mpg123", "-q", "-a", device, str(path)])
    if which("ffplay"):
        commands.append(["ffplay", "-nodisp", "-hide_banner", "-loglevel", "error", "-autoexit", str(path)])
    if which("mpv"):
        commands.append(["mpv", "--no-video", "--really-quiet", str(path)])
    if wav_only and which("aplay"):
        cmd = ["aplay", "-q"]
        if device:
            cmd.extend(["-D", device])
        cmd.append(str(path))
        commands.append(cmd)
    if wav_only and which("paplay"):
        commands.append(["paplay", str(path)])
    for command in commands:
        try:
            print(f"Kiosk BGM {' '.join(command[:2])} {path.name}", flush=True)
            return subprocess.Popen(
                command,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError:
            continue
    if which("ffmpeg") and which("aplay") and not wav_only:
        aplay = "aplay -q -t wav"
        if device:
            aplay += f" -D {shlex.quote(device)}"
        pipeline = (
            f"ffmpeg -hide_banner -loglevel error -i {shlex.quote(str(path))} -f wav - | {aplay}"
        )
        try:
            print(f"Kiosk BGM ffmpeg|aplay {path.name}", flush=True)
            return subprocess.Popen(
                pipeline,
                shell=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError:
            return None
    return None


def _kill_bgm_proc() -> None:
    with _AUDIO["lock"]:
        proc = _AUDIO["bgm_proc"]
        _AUDIO["bgm_proc"] = None
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except OSError:
        try:
            proc.terminate()
        except OSError:
            pass
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            try:
                proc.kill()
            except OSError:
                pass


def stop_kiosk_bgm(keep_wanted: bool = False) -> None:
    with _AUDIO["lock"]:
        if not keep_wanted:
            _AUDIO["wanted"] = False
    _kill_bgm_proc()
    deadline = time.time() + 1.2
    while time.time() < deadline:
        with _AUDIO["lock"]:
            proc = _AUDIO["bgm_proc"]
        if proc is None or proc.poll() is not None:
            break
        time.sleep(0.05)
    if os.name != "nt":
        time.sleep(0.2)


def _bgm_supervisor() -> None:
    while True:
        time.sleep(0.2)
        with _AUDIO["lock"]:
            wanted = _AUDIO["wanted"]
            path = _AUDIO["path"]
            proc = _AUDIO["bgm_proc"]
        if not wanted:
            if proc is not None:
                _kill_bgm_proc()
            continue
        if path is None:
            continue
        if proc is not None and proc.poll() is None:
            continue
        if proc is not None and proc.poll() is not None:
            path = _next_bgm_path(path)
            with _AUDIO["lock"]:
                _AUDIO["path"] = path
            if path is None:
                continue
        spawned = _spawn_bgm(path)
        if spawned is None:
            time.sleep(1)
            continue
        with _AUDIO["lock"]:
            if not _AUDIO["wanted"] or _AUDIO["path"] != path:
                try:
                    os.killpg(spawned.pid, signal.SIGTERM)
                except OSError:
                    spawned.kill()
                continue
            _AUDIO["bgm_proc"] = spawned


def start_kiosk_bgm(name: str = "") -> bool:
    if os.name == "nt":
        return False
    if config().get("crtFx", {}).get("sound") is False:
        stop_kiosk_bgm()
        return False
    path = default_bgm_path(name)
    if not path:
        return False
    with _AUDIO["lock"]:
        same = _AUDIO["path"] == path and _AUDIO["bgm_proc"] is not None and _AUDIO["bgm_proc"].poll() is None
        _AUDIO["wanted"] = True
        _AUDIO["path"] = path
        if not _AUDIO["supervisor"]:
            _AUDIO["supervisor"] = True
            threading.Thread(target=_bgm_supervisor, daemon=True).start()
    if not same:
        _kill_bgm_proc()
    return True


def play_kiosk_sfx(kind: str) -> None:
    if os.name == "nt":
        return
    if config().get("crtFx", {}).get("sound") is False:
        return
    data = _sfx_wav(kind)
    threading.Thread(target=_play_wav_bytes, args=(data,), daemon=True).start()


def handle_audio_command(body: dict) -> dict:
    cmd = str(body.get("cmd") or "")
    if cmd == "stop":
        with _AUDIO["lock"]:
            _AUDIO["wanted"] = False
        stop_kiosk_bgm()
        return {"ok": True}
    if cmd == "sfx":
        play_kiosk_sfx(str(body.get("kind") or "ok"))
        return {"ok": True}
    if cmd == "bgm":
        ok = start_kiosk_bgm(str(body.get("file") or ""))
        return {"ok": ok}
    return {"ok": False, "error": "Bilinmeyen ses komutu."}


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
    for dirpath, dirnames, filenames in os.walk(folder):
        dirnames[:] = [name for name in dirnames if name.lower() not in SKIP_ROM_DIRS]
        for name in filenames:
            path = Path(dirpath) / name
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
    with _COVER_LOCK:
        cached = _COVER_INDEX.get(system["id"])
        if cached is not None:
            return cached
        exact: dict[str, Path] = {}
        core: dict[str, list[Path]] = {}
        folder = ROMS / system["romDir"]

        def _add(path: Path) -> None:
            if not path.is_file() or path.suffix.lower() not in COVER_EXTS:
                return
            exact[path.stem.lower()] = path
            key = normalize(path.stem)
            if key:
                core.setdefault(key, []).append(path)

        if folder.is_dir():
            for path in folder.iterdir():
                if path.is_file():
                    _add(path)
                elif path.is_dir() and path.name.lower() in SKIP_ROM_DIRS:
                    for art in path.rglob("*"):
                        _add(art)
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


def kick_catalog_build() -> None:
    global _CATALOG_BUILDING
    with _CATALOG_LOCK:
        if _CATALOG_BUILDING or _CATALOG_READY:
            return
        _CATALOG_BUILDING = True
    threading.Thread(target=_catalog_worker, daemon=True).start()


def _catalog_worker() -> None:
    global _CATALOG_GAMES, _CATALOG_READY, _CATALOG_BUILDING
    try:
        rows = catalog_with_folder_roms()
        with _CATALOG_LOCK:
            _CATALOG_GAMES = rows
            _CATALOG_READY = True
    finally:
        with _CATALOG_LOCK:
            _CATALOG_BUILDING = False


def cached_catalog(wait: bool = False) -> list:
    kick_catalog_build()
    deadline = time.time() + (25 if wait else 0)
    while True:
        with _CATALOG_LOCK:
            ready = _CATALOG_READY
            games_list = _CATALOG_GAMES
        if ready and games_list is not None:
            return list(games_list)
        if not wait or time.time() >= deadline:
            return list(games_list or [])
        time.sleep(0.05)


def catalog_ready() -> bool:
    with _CATALOG_LOCK:
        return _CATALOG_READY


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
    library = cached_catalog(wait=True)
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
    if system.get("exactRom"):
        want = game["rom"].lower()
        for path in folder.iterdir():
            if path.is_file() and path.name.lower() == want:
                return path
        return None

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
    if system.get("id") in {"arcade", "neogeo"}:
        return rom
    ext = rom.suffix.lower()
    if ext not in {".7z", ".zip"}:
        return rom
    sibling = _sibling_unpacked(rom, system)
    if sibling:
        return sibling
    inner_exts = tuple(e.lower() for e in system.get("extensions", []) if e.lower() not in {".7z", ".zip"})
    if not inner_exts:
        return rom
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
        path = resolve_path(cfg["exe"])
        if os.name == "nt" or path.suffix.lower() != ".exe":
            if path.exists():
                names.append(path)
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
    home = Path.home() / ".config" / "retroarch" / "cores"
    candidates = [home]
    if cfg.get("cores"):
        candidates.append(resolve_path(cfg["cores"]))
    exe = retroarch_exe()
    if exe:
        candidates.append(exe.parent / "cores")
    candidates.extend(
        [
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


def _core_arch_ok(path: Path) -> bool:
    if os.name == "nt":
        return True
    try:
        with path.open("rb") as handle:
            header = handle.read(5)
    except OSError:
        return False
    if header[:4] != b"\x7fELF":
        return True
    machine = os.uname().machine
    want_64 = machine in {"aarch64", "x86_64", "amd64"}
    return (header[4] == 2) == want_64


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
                if candidate.is_file() and _core_arch_ok(candidate):
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
                hits = [hit for hit in sorted(folder.glob(f"*{key}*{ext}")) if _core_arch_ok(hit)]
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


def _crt_output() -> bool:
    disp = config().get("display") or {}
    return str(disp.get("output", "hdmi")).lower() == "crt"


def _aspect_ratio_index() -> str:
    if _crt_output():
        return "0"
    aspect = str((config().get("display") or {}).get("aspect") or "16:9").lower().replace(" ", "")
    if aspect in {"4:3", "4/3"}:
        return "0"
    if aspect in {"full", "stretch"}:
        return "23"
    return "1"


def _game_refresh_rate(system: dict) -> str:
    # Neo Geo / CPS / most 90s boards are ~59.18–60 Hz. Forcing 50 Hz on a 60 Hz VGA
    # panel makes vsync miss; FBNeo then runs Metal Slug and friends uncapped.
    if system["id"] == "neogeo":
        return "59.185606"
    if system["id"] in {"arcade", "megadrive", "snes", "psx"}:
        return "59.94"
    if system["id"] == "nes":
        return "60.098812"
    return "60"


def _first_gamepad(tokens) -> str | None:
    for token in tokens or []:
        text = str(token)
        if text.startswith("Gamepad") and text[7:].isdigit():
            return text[7:]
    return None


def linux_joypads() -> list[dict]:
    path = Path("/proc/bus/input/devices")
    if os.name == "nt" or not path.is_file():
        return []
    pads: list[dict] = []
    name = ""
    vendor = ""
    js = None
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    for line in text.splitlines() + [""]:
        if line.startswith("N: Name="):
            name = line.split("=", 1)[1].strip().strip('"')
        elif line.startswith("I: "):
            bits = dict(part.split("=", 1) for part in line[3:].split() if "=" in part)
            vendor = bits.get("Vendor", "")
        elif line.startswith("H: Handlers="):
            for token in line.split():
                if token.startswith("js") and token[2:].isdigit():
                    js = int(token[2:])
        elif not line.strip() and js is not None:
            pads.append({"name": name, "js": js, "vendor": vendor})
            name, vendor, js = "", "", None
    return pads


def _is_game_pad(pad: dict) -> bool:
    blob = f"{pad.get('name', '')} {pad.get('vendor', '')}".lower()
    if any(word in blob for word in ("mouse", "keyboard", "power", "hdmi", "cec")):
        return False
    return True


def _is_ps_pad(pad: dict) -> bool:
    blob = f"{pad.get('name', '')} {pad.get('vendor', '')}".lower()
    return pad.get("vendor", "").lower() == "054c" or any(
        word in blob for word in ("playstation", "sony", "shanwan", "dualshock", "ps3")
    )


def pick_player1_pad() -> dict:
    pads = [pad for pad in linux_joypads() if _is_game_pad(pad)]
    for pad in pads:
        if _is_ps_pad(pad):
            return pad
    return pads[0] if pads else {"name": "", "js": 0, "vendor": ""}


def retroarch_exit_lines() -> list[str]:
    controls = config().get("controls") or {}
    hotkey = _first_gamepad(controls.get("hotkey") or ["Gamepad4"])
    exit_btn = _first_gamepad(controls.get("exit") or ["Gamepad10"])
    if hotkey == "9":
        hotkey = "10"
    if exit_btn == "9":
        exit_btn = "10"
    hold = hotkey or "nul"
    if hotkey and exit_btn and hotkey == exit_btn:
        hold = "nul"
    return [
        'input_exit_emulator = "nul"',
        'input_enable_hotkey = "nul"',
        f'input_enable_hotkey_btn = "{hold}"',
        f'input_exit_emulator_btn = "{exit_btn or "nul"}"',
        'input_bind_hold = "300"',
    ]


def retroarch_menu_lock() -> list[str]:
    return [
        'menu_driver = "rgui"',
        'rgui_show_start_screen = "false"',
        'quick_menu_enable = "false"',
        'config_save_on_exit = "false"',
        'quit_press_twice = "false"',
        'input_menu_toggle = "nul"',
        'input_menu_toggle_btn = "nul"',
        'input_menu_toggle_gamepad_combo = "0"',
        'input_desktop_menu_toggle = "nul"',
        'input_toggle_fast_forward = "nul"',
        'input_toggle_fast_forward_btn = "nul"',
        'input_hold_fast_forward = "nul"',
        'input_toggle_slowmotion = "nul"',
        'input_rewind = "nul"',
        'input_save_state = "nul"',
        'input_load_state = "nul"',
        'input_state_slot_increase = "nul"',
        'input_state_slot_decrease = "nul"',
        'input_reset = "nul"',
        'input_shader_toggle = "nul"',
        'input_screenshot = "nul"',
        'input_cheat_toggle = "nul"',
        'input_ai_service = "nul"',
    ]


def joypad_autoconfig_dir() -> Path:
    return Path.home() / ".config" / "retroarch" / "autoconfig"


def install_joypad_profiles() -> Path:
    dest_root = joypad_autoconfig_dir()
    bundled = ROOT / "kiosk" / "autoconfig"
    if os.name == "nt" or not bundled.is_dir():
        return dest_root
    for driver in ("udev", "linuxraw"):
        folder = dest_root / driver
        folder.mkdir(parents=True, exist_ok=True)
        for src in bundled.glob("*.cfg"):
            text = src.read_text(encoding="utf-8", errors="replace")
            text = text.replace('input_driver = "udev"', f'input_driver = "{driver}"')
            (folder / src.name).write_text(text, encoding="utf-8")
    return dest_root


def _shader_file() -> Path | None:
    names = [
        Path.home() / ".config/retroarch/shaders/shaders_slang/interpolation/sharp-bilinear.slangp",
        Path("/usr/share/libretro/shaders/shaders_slang/interpolation/sharp-bilinear.slangp"),
        Path("/usr/share/retroarch/shaders/shaders_slang/interpolation/sharp-bilinear.slangp"),
        Path("/usr/share/libretro/shaders/shaders_glsl/interpolation/sharp-bilinear.glslp"),
    ]
    for path in names:
        if path.is_file():
            return path
    return None


def _core_option_lines(system: dict, core: Path) -> list[str]:
    stem = core.stem.lower()
    lines: list[str] = []
    if system["id"] == "psx":
        lines.extend(
            [
                'pcsx_rearmed_neon_enhancement_enable = "enabled"',
                'pcsx_rearmed_neon_enhancement_no_main = "disabled"',
                'pcsx_rearmed_dithering = "enabled"',
                'pcsx_rearmed_frameskip = "0"',
                'swanstation_GPU_Renderer = "Software"',
                'swanstation_GPU_ResolutionScale = "2"',
                'duckstation_GPU.Renderer = "Software"',
                'duckstation_GPU.ResolutionScale = "2"',
            ]
        )
    if "stella" in stem:
        lines.append('stella_crop_hoverscan = "enabled"')
    if system["id"] in {"arcade", "neogeo"} or "fbneo" in stem or "mame" in stem:
        lines.extend(
            [
                'fbneo-allow-patched-romsets = "disabled"',
                'fbneo-allow-depth = "8"',
                'fbneo-sample-interpolation = "disabled"',
                'fbneo-diagnostic = "disabled"',
                'fbneo-cpu-speed-adjust = "100"',
                'fbneo-frameskip = "0"',
            ]
        )
    return lines


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
        extra = ""
        if os.name != "nt" and system["id"] in {"arcade", "neogeo"}:
            extra = " 64-bit FBNeo: sh kiosk/pi-cores.sh"
        return {
            "ok": False,
            "error": f"{system['name']} core yok. Beklenen: {wanted}.{extra}",
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
    stop_kiosk_bgm(keep_wanted=True)

    override = ROOT / "config" / "runtime.cfg"
    override.parent.mkdir(parents=True, exist_ok=True)
    if system["id"] == "psx":
        sysdir = (BIOS / "psx").as_posix()
    else:
        sysdir = rom.parent.as_posix()
    lines = retroarch_menu_lock() + [
        'video_fullscreen = "true"',
        'video_font_enable = "false"',
        'pause_nonactive = "false"',
        'video_vsync = "true"',
        'video_hard_sync = "false"',
        'video_threaded = "false"',
        'video_swap_interval = "1"',
        f'video_refresh_rate = "{_game_refresh_rate(system)}"',
        'video_autoswitch_refresh_rate = "0"',
        'vrr_runloop_enable = "false"',
        'run_ahead_enabled = "false"',
        'audio_enable = "true"',
        'audio_sync = "true"',
        'audio_rate_control = "true"',
        'audio_latency = "64"',
        'fastforward_ratio = "1.0"',
        'input_toggle_fast_forward = "nul"',
        'input_hold_fast_forward = "nul"',
        'input_toggle_slowmotion = "nul"',
        'input_hold_slowmotion = "nul"',
        'rewind_enable = "false"',
        f'aspect_ratio_index = "{_aspect_ratio_index()}"',
        f'system_directory = "{sysdir}"',
        f'rgui_browser_directory = "{sysdir}"',
    ]
    if os.name != "nt":
        pads = install_joypad_profiles()
        analog = "0" if system["id"] == "psx" else "1"
        pad = pick_player1_pad()
        lines.extend(
            [
                'input_driver = "x"',
                'input_joypad_driver = "linuxraw"',
                'input_autodetect_enable = "true"',
                f'joypad_autoconfig_dir = "{pads.as_posix()}"',
                'input_max_users = "2"',
                f'input_player1_joypad_index = "{pad.get("js", 0)}"',
                'input_player1_start = "enter"',
                f'input_player1_analog_dpad_mode = "{analog}"',
                f'input_player2_analog_dpad_mode = "{analog}"',
            ]
        )
        if _is_ps_pad(pad) or not pad.get("name"):
            lines.extend(
                [
                    'input_player1_b_btn = "0"',
                    'input_player1_a_btn = "1"',
                    'input_player1_x_btn = "2"',
                    'input_player1_y_btn = "3"',
                    'input_player1_l_btn = "4"',
                    'input_player1_r_btn = "5"',
                    'input_player1_select_btn = "8"',
                    'input_player1_start_btn = "9"',
                    'input_player1_up_btn = "13"',
                    'input_player1_down_btn = "14"',
                    'input_player1_left_btn = "15"',
                    'input_player1_right_btn = "16"',
                    'input_player1_l_x_plus_axis = "+0"',
                    'input_player1_l_x_minus_axis = "-0"',
                    'input_player1_l_y_plus_axis = "+1"',
                    'input_player1_l_y_minus_axis = "-1"',
                ]
            )
    lines.extend(retroarch_exit_lines())
    if _crt_output():
        lines.extend(
            [
                'video_smooth = "false"',
                'video_scale_integer = "true"',
                'custom_viewport_width = "800"',
                'custom_viewport_height = "600"',
            ]
        )
    else:
        # LCD: 2D nearest (crisp pixels). Bilinear makes NES/SNES look muddy.
        smooth = "true" if system["id"] == "psx" else "false"
        lines.extend(
            [
                f'video_smooth = "{smooth}"',
                'video_scale_integer = "false"',
                'video_shader_enable = "false"',
            ]
        )
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
    lines.extend(_core_option_lines(system, core))
    override.write_text("\n".join(lines) + "\n", encoding="utf-8")

    launch_cwd = str(rom.parent) if system["id"] in {"arcade", "neogeo"} else str(ROOT)
    rom_arg = rom.name if system["id"] in {"arcade", "neogeo"} else str(rom)
    args = [str(exe), "--verbose", "-L", str(core), "-f", "--appendconfig", str(override), rom_arg]
    creationflags = 0
    popen_env = os.environ.copy()
    popen_env["vblank_mode"] = "1"
    if os.name == "nt":
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

    log_path = Path("/tmp/arcadebox-launch.log") if os.name != "nt" else ROOT / "config" / "launch.log"
    try:
        log_handle = log_path.open("ab", buffering=0)
        log_handle.write(
            f"\n--- {game['title']} core={core} cwd={launch_cwd} rom={rom_arg} full={rom} pad={pick_player1_pad()}\n".encode(
                "utf-8", "replace"
            )
        )
    except OSError:
        log_handle = subprocess.DEVNULL

    try:
        process = subprocess.Popen(
            args,
            cwd=launch_cwd,
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
        start_kiosk_bgm()
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
        refocus_kiosk_browser()
        pause_kiosk_browser(False)
        if hasattr(log_handle, "close"):
            try:
                log_handle.close()
            except OSError:
                pass
        elapsed = time.time() - started
        with _LOCK:
            if code != 0 or elapsed < 8:
                err = f"{system['name']} {elapsed:.1f}sn içinde kapandı (kod {code})."
                if system["id"] in {"arcade", "neogeo"}:
                    err += " ROM adi FBNeo ile uyumlu mu? Log: /tmp/arcadebox-launch.log"
                else:
                    err += " Log: /tmp/arcadebox-launch.log"
                _STATE["lastError"] = err
            _STATE["busy"] = False
            _STATE["gameId"] = None
            _STATE["process"] = None
        with _AUDIO["lock"]:
            resume = _AUDIO["wanted"]
        if resume:
            start_kiosk_bgm()

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

    def _send_file(self, path: Path, mime: str, cache: str = "public, max-age=3600") -> None:
        size = path.stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(size))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", cache)
        self.end_headers()
        with path.open("rb") as handle:
            shutil.copyfileobj(handle, self.wfile)

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
            kick_catalog_build()
            library = cached_catalog(wait=False)
            payload = {
                "systems": systems(),
                "games": library,
                "catalogReady": catalog_ready(),
                "status": status_payload(),
                "bios": {item["id"]: bios_status(item) for item in systems()},
                "config": {
                    "pi": Path("/sys/firmware/devicetree/base/model").exists(),
                    "retroarchExists": retroarch_exe() is not None,
                    "fastBoot": bool(config().get("fastBoot")),
                    "idleDemoSeconds": config().get("idleDemoSeconds", 40),
                    "display": config().get("display", {}),
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
            if path.suffix.lower() == ".mp3":
                mime = "audio/mpeg"
            self._send_file(path, mime)
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
            try:
                result = launch_game(str(body.get("id") or parse_qs(parsed.query).get("id", [""])[0]))
            except Exception as exc:
                result = {"ok": False, "error": f"Baslatma hatasi: {exc}"}
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
            if current.get("crtFx", {}).get("sound") is False:
                stop_kiosk_bgm()
            self._json({"ok": True, "config": current})
            return
        if parsed.path == "/api/audio":
            self._json(handle_audio_command(body))
            return
        self._json({"ok": False, "error": "Bilinmeyen istek."}, 404)


def _linux_browser_command(binary: str, found: str) -> list[str]:
    if "firefox" in binary:
        return [found, "--kiosk"]
    flags = [
        "--kiosk",
        "--noerrdialogs",
        "--disable-infobars",
        "--incognito",
        "--no-first-run",
        "--disable-session-crashed-bubble",
        "--check-for-update-interval=31536000",
        "--disable-features=Translate,TranslateUI",
        "--ozone-platform=x11",
        "--start-fullscreen",
        "--disable-background-networking",
        "--disable-component-update",
        "--disable-sync",
        "--num-raster-threads=1",
        "--enable-low-end-device-mode",
        "--disable-gpu-rasterization",
        "--disable-gpu",
        "--disable-gpu-compositing",
        "--disable-dev-shm-usage",
        "--disable-breakpad",
        "--no-sandbox",
    ]
    return [found, *flags]


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
    machine = platform.machine().lower()
    if machine in ("x86_64", "amd64"):
        # GeForce 405 / eski VGA: Chromium sik crash — Firefox ESR daha stabil.
        order = ("firefox-esr", "firefox", "chromium", "chromium-browser", "google-chrome")
    else:
        order = ("chromium", "chromium-browser", "google-chrome", "firefox-esr", "firefox")
    for binary in order:
        found = which(binary)
        if found:
            return _linux_browser_command(binary, found)
    return None


def _firefox_pids() -> list[int]:
    if os.name == "nt":
        return []
    try:
        proc = subprocess.run(
            ["pgrep", "-f", "firefox-esr.*7842|firefox.*127.0.0.1:7842"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        return [int(line) for line in proc.stdout.splitlines() if line.strip().isdigit()]
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return []


def refocus_kiosk_browser() -> None:
    if os.name == "nt":
        return
    for cmd in (
        ["wmctrl", "-a", "Mozilla Firefox"],
        ["wmctrl", "-a", "Firefox"],
        ["xdotool", "search", "--class", "Firefox-esr", "windowactivate", "--sync"],
        ["xdotool", "search", "--class", "Navigator", "windowactivate", "--sync"],
    ):
        try:
            subprocess.run(cmd, timeout=2, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            return
        except (OSError, subprocess.TimeoutExpired):
            continue
    pause_kiosk_browser(False)


def pause_kiosk_browser(pause: bool) -> None:
    sig = signal.SIGSTOP if pause else signal.SIGCONT
    targets = _firefox_pids()
    if _BROWSER_PROC is not None and _BROWSER_PROC.poll() is None:
        targets.append(_BROWSER_PROC.pid)
    if not targets:
        return
    for pid in dict.fromkeys(targets):
        try:
            os.kill(pid, sig)
        except OSError:
            try:
                os.killpg(pid, sig)
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
    kick_catalog_build()
    if os.name != "nt":
        install_joypad_profiles()
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
