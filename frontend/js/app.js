const state = {
  view: "boot",
  systems: [],
  games: [],
  music: [],
  bios: {},
  config: {},
  systemIndex: 0,
  gameIndex: 0,
  idle: 0,
  launching: false,
  controls: {
    up: ["ArrowUp", "StickUp"],
    down: ["ArrowDown", "StickDown"],
    left: ["ArrowLeft", "StickLeft"],
    right: ["ArrowRight", "StickRight"],
    ok: ["Enter", " ", "1", "Gamepad0", "Gamepad9"],
    back: ["Escape", "Backspace", "Gamepad1"],
    service: ["F2", "Tab", "9", "Gamepad8"],
    hotkey: ["Gamepad4"],
    exit: ["Gamepad10"],
    fav: ["y", "Y", "Gamepad3"],
  },
  crtFx: { scanlines: 0, flicker: false, rgb: false, sound: true },
  serviceTab: 0,
  serviceIndex: 0,
  listening: null,
  held: {},
  lastPad: {},
  padName: "",
  padReady: false,
  lastSignal: "—",
  catalogReady: false,
  gameCounts: {},
  favorites: [],
};

const ACTIONS = [
  { id: "up", label: "YUKARI" },
  { id: "down", label: "AŞAĞI" },
  { id: "left", label: "SOL" },
  { id: "right", label: "SAĞ" },
  { id: "ok", label: "START / A" },
  { id: "back", label: "GERİ / B" },
  { id: "service", label: "SERVİS" },
  { id: "hotkey", label: "OYUN HOTKEY" },
  { id: "exit", label: "OYUNDAN ÇIKIŞ" },
  { id: "fav", label: "FAVORİ" },
];

const CRT_LEVELS = [
  { label: "TARAMA KAPALI", scanlines: 0 },
  { label: "TARAMA AZ", scanlines: 0.28 },
  { label: "TARAMA ORTA", scanlines: 0.55 },
  { label: "TARAMA ÇOK", scanlines: 0.78 },
];


const $ = (id) => document.getElementById(id);

let audioCtx = null;
let audioReady = false;
let bgm = null;
let musicIndex = 0;
let musicDuckTimer = 0;
let synthTimer = 0;
let synthNodes = null;

const SILENT_WAV =
  "data:audio/wav;base64,UklGRigAAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YQQAAAAAAA==";

async function unlockAudio() {
  const Ctx = window.AudioContext || window.webkitAudioContext;
  if (Ctx && !audioCtx) audioCtx = new Ctx();
  if (audioCtx && audioCtx.state === "suspended") {
    try {
      await audioCtx.resume();
    } catch (_error) {
      /* kiosk may block until input */
    }
  }
  if (!audioReady) {
    try {
      const ping = new Audio(SILENT_WAV);
      ping.volume = 0.001;
      await ping.play();
      audioReady = true;
    } catch (_error) {
      /* retry on next input */
    }
  }
  return audioReady || (audioCtx && audioCtx.state === "running");
}

let musicWatch = 0;

function primeAudio() {
  playMenuMusic();
  [150, 400, 900, 1800, 3500, 7000].forEach((ms) => window.setTimeout(playMenuMusic, ms));
  if (!musicWatch) {
    musicWatch = window.setInterval(() => {
      if (musicWanted() && (!bgm || bgm.paused)) playMenuMusic();
    }, 2000);
  }
}

function toneWav(freq, seconds, volume) {
  const sr = 22050;
  const n = Math.max(8, Math.floor(sr * seconds));
  const bytes = new Uint8Array(44 + n * 2);
  const view = new DataView(bytes.buffer);
  const ascii = (offset, text) => {
    for (let i = 0; i < text.length; i += 1) bytes[offset + i] = text.charCodeAt(i);
  };
  ascii(0, "RIFF");
  view.setUint32(4, 36 + n * 2, true);
  ascii(8, "WAVEfmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sr, true);
  view.setUint32(28, sr * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  ascii(36, "data");
  view.setUint32(40, n * 2, true);
  for (let i = 0; i < n; i += 1) {
    const env = Math.min(1, i / 90) * (1 - i / n);
    view.setInt16(44 + i * 2, Math.sin((2 * Math.PI * freq * i) / sr) * volume * env * 32767, true);
  }
  return URL.createObjectURL(new Blob([bytes], { type: "audio/wav" }));
}

const SFX_SRC = {
  move: toneWav(1180, 0.05, 0.55),
  ok: toneWav(880, 0.09, 0.6),
  back: toneWav(360, 0.1, 0.55),
  launch: toneWav(523, 0.14, 0.62),
  boot: toneWav(659, 0.16, 0.6),
  error: toneWav(180, 0.16, 0.6),
};

function useHostAudio() {
  return document.body.dataset.kiosk === "vga" && /Linux/i.test(navigator.userAgent);
}

function hostAudio(body) {
  fetch("/api/audio", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  }).catch(() => {});
}

function playSfxUrl(url) {
  const shot = new Audio(url);
  shot.volume = 0.7;
  shot.play().catch(() => {});
}

function beep(freq, dur, vol) {
  playSfxUrl(toneWav(freq, dur, vol || 0.55));
}

function sfx(kind) {
  if (state.crtFx.sound === false) return;
  if (useHostAudio()) {
    hostAudio({ cmd: "sfx", kind });
    return;
  }
  duckMusic();
  if (SFX_SRC[kind]) playSfxUrl(SFX_SRC[kind]);
}

const MUSIC_VOL = 0.42;
const MUSIC_DUCK = 0.08;
const BUILTIN_BGM = "media/menu-ambient.wav";
const SYSTEM_LOGOS = {
  favorites: "media/pandora/logos/favorites.png",
  atari2600: "media/pandora/logos/atari2600.png",
  nes: "media/pandora/logos/nes.png",
  snes: "media/pandora/logos/snes.png",
  megadrive: "media/pandora/logos/megadrive.png",
  arcade: "media/pandora/logos/arcade.png",
  neogeo: "media/pandora/logos/neogeo.png",
  psx: "media/pandora/logos/psx.png",
};
const SYSTEM_HERO = {
  favorites: "media/home/system-arcade.jpg",
  atari2600: "media/home/system-atari2600.jpg",
  nes: "media/home/system-nes.jpg",
  snes: "media/home/system-snes.jpg",
  megadrive: "media/home/system-megadrive.jpg",
  arcade: "media/home/system-arcade.jpg",
  neogeo: "media/home/system-neogeo.jpg",
  psx: "media/home/system-psx.jpg",
};
const FAV_SYSTEM = {
  id: "favorites",
  name: "Favoriler",
  short: "FAV",
  era: "★",
  bits: "PICKS",
  emulator: "Hızlı seçim",
  accent: "#ff4ae8",
  romDir: "",
  blurb: "Yıldızladığın oyunlar.",
};

function systemsWithFav(list) {
  return [FAV_SYSTEM, ...(list || []).filter((item) => item.id !== "favorites")];
}

function isFavorite(id) {
  return (state.favorites || []).includes(id);
}
const BOOT_SYSTEMS = [
  { id: "atari2600", name: "Atari 2600", short: "ATARI", era: "1977", bits: "8-BIT", emulator: "RetroArch → Stella", accent: "#ff4d3a", blurb: "Klasöre attığın ROM menüde görünür." },
  { id: "nes", name: "NES / Famicom", short: "NES", era: "1983", bits: "8-BIT", emulator: "RetroArch → Mesen", accent: "#e03c31", blurb: "roms/nes klasörünü tarar." },
  { id: "snes", name: "Super Nintendo", short: "SNES", era: "1990", bits: "16-BIT", emulator: "RetroArch → Snes9x", accent: "#7b5cff", blurb: "roms/snes klasörünü tarar." },
  { id: "megadrive", name: "Mega Drive", short: "SEGA", era: "1988", bits: "16-BIT", emulator: "RetroArch → Genesis Plus GX", accent: "#2f6bff", blurb: "roms/megadrive klasörünü tarar." },
  { id: "arcade", name: "Arcade", short: "MAME", era: "CAB", bits: "PCB", emulator: "RetroArch → FBNeo", accent: "#ff7a18", blurb: "roms/arcade klasöründeki zip'ler." },
  { id: "neogeo", name: "Neo Geo", short: "NEO", era: "1990", bits: "AES", emulator: "RetroArch → FBNeo", accent: "#ffe14a", blurb: "roms/neogeo klasörü + BIOS." },
  { id: "psx", name: "PlayStation", short: "PS1", era: "1994", bits: "32-BIT", emulator: "RetroArch → SwanStation", accent: "#3ad4ff", blurb: "roms/psx klasörünü tarar." },
];

function musicWanted() {
  const inMenu = state.view === "home" || state.view === "games" || state.view === "service";
  return Boolean(state.crtFx.sound !== false && inMenu && !state.launching);
}

function stopSynthBgm() {
  window.clearInterval(synthTimer);
  synthTimer = 0;
  if (!synthNodes) return;
  try {
    synthNodes.bass.stop();
  } catch (_error) {
    /* already stopped */
  }
  synthNodes.bassGain.disconnect();
  synthNodes = null;
}

function startSynthBgm() {
  if (synthNodes || !musicWanted()) return;
  unlockAudio().then((ready) => {
    if (!ready || !audioCtx || synthNodes) return;
    const bass = audioCtx.createOscillator();
    const filter = audioCtx.createBiquadFilter();
    const bassGain = audioCtx.createGain();
    bass.type = "triangle";
    bass.frequency.value = 49;
    filter.type = "lowpass";
    filter.frequency.value = 420;
    bassGain.gain.value = MUSIC_VOL * 0.16;
    bass.connect(filter);
    filter.connect(bassGain);
    bassGain.connect(audioCtx.destination);
    bass.start();
    synthNodes = { bass, bassGain };
  });
}

function ensureBgm() {
  if (bgm) return bgm;
  bgm = document.getElementById("bgm-prime") || new Audio();
  bgm.preload = "auto";
  if (!bgm.dataset.ready) {
    bgm.dataset.ready = "1";
    bgm.addEventListener("error", () => {
      if (!(state.music || []).length) return;
      musicIndex = (musicIndex + 1) % state.music.length;
      playMenuMusic();
    });
  }
  return bgm;
}

function setBgmSource(url, key, loop) {
  const player = ensureBgm();
  player.loop = loop;
  player.muted = false;
  if (player.dataset.track !== key) {
    player.dataset.track = key;
    player.src = url;
    player.load();
  }
  return player;
}

function attemptBgmPlay(player) {
  if (!musicWanted()) return Promise.resolve();
  player.volume = MUSIC_VOL;
  player.muted = false;
  return player.play().catch(() => {
    player.muted = true;
    player.volume = 0.001;
    return player.play().then(() => {
      player.muted = false;
      player.volume = MUSIC_VOL;
    });
  });
}

let lastHostBgm = "";

function playMenuMusic() {
  if (useHostAudio()) {
    if (!musicWanted()) {
      lastHostBgm = "";
      hostAudio({ cmd: "stop" });
      return;
    }
    const key = (state.music && state.music.length) ? state.music[musicIndex % state.music.length] : "__builtin__";
    if (lastHostBgm === key) return;
    lastHostBgm = key;
    hostAudio({ cmd: "bgm", file: key === "__builtin__" ? "" : key });
    return;
  }
  if (!musicWanted()) {
    stopSynthBgm();
    if (bgm && !bgm.paused) bgm.pause();
    return;
  }
  stopSynthBgm();
  const tracks = state.music || [];
  if (tracks.length) {
    const track = tracks[musicIndex % tracks.length];
    const url = "/api/music?file=" + encodeURIComponent(track);
    const player = setBgmSource(url, track, false);
    player.onended = () => {
      if (!(state.music || []).length) return;
      musicIndex = (musicIndex + 1) % state.music.length;
      playMenuMusic();
    };
    attemptBgmPlay(player).catch(() => {
      const fallback = setBgmSource(BUILTIN_BGM, "__builtin__", true);
      fallback.onended = null;
      attemptBgmPlay(fallback).catch(() => startSynthBgm());
    });
    return;
  }
  const player = setBgmSource(BUILTIN_BGM, "__builtin__", true);
  player.onended = null;
  attemptBgmPlay(player).catch(() => startSynthBgm());
}

function syncMusic() {
  playMenuMusic();
}

function duckMusic() {
  if (synthNodes && synthNodes.bassGain) {
    synthNodes.bassGain.gain.value = MUSIC_DUCK * 0.55;
    window.clearTimeout(musicDuckTimer);
    musicDuckTimer = window.setTimeout(() => {
      if (synthNodes && synthNodes.bassGain && musicWanted()) synthNodes.bassGain.gain.value = MUSIC_VOL * 0.22;
    }, 220);
  }
  if (!bgm || bgm.paused) return;
  bgm.volume = MUSIC_DUCK;
  window.clearTimeout(musicDuckTimer);
  musicDuckTimer = window.setTimeout(() => {
    if (bgm && !bgm.paused && musicWanted()) bgm.volume = MUSIC_VOL;
  }, 220);
}

const STAGE = { w: 800, h: 600, bezelW: 860, bezelH: 648 };

function scaleStage() {
  const bezel = $("bezel");
  const tube = $("tube");
  const stage = $("stage");
  const out = state.config?.display?.output || document.body.dataset.kiosk || "";
  if (out === "vga") {
    const w = window.innerWidth;
    const h = window.innerHeight;
    document.documentElement.style.setProperty("--stage-w", `${w}px`);
    document.documentElement.style.setProperty("--stage-h", `${h}px`);
    document.documentElement.classList.add("vga-kiosk");
    document.body.classList.add("vga-kiosk");
    bezel.style.transform = "none";
    bezel.style.width = `${w}px`;
    bezel.style.height = `${h}px`;
    if (tube) {
      tube.style.width = `${w}px`;
      tube.style.height = `${h}px`;
    }
    if (stage) {
      stage.style.width = `${w}px`;
      stage.style.height = `${h}px`;
    }
    return;
  }
  document.documentElement.classList.remove("vga-kiosk");
  if (tube) {
    tube.style.width = "";
    tube.style.height = "";
  }
  if (stage) {
    stage.style.width = "";
    stage.style.height = "";
  }
  const mode = state.config?.display?.scale || "fit";
  const x = window.innerWidth / STAGE.bezelW;
  const y = window.innerHeight / STAGE.bezelH;
  const scale = mode === "fill" ? Math.max(x, y) : Math.min(x, y);
  bezel.style.transform = `translate(${(window.innerWidth - STAGE.bezelW * scale) / 2}px, ${(window.innerHeight - STAGE.bezelH * scale) / 2}px) scale(${scale})`;
}

function applyDisplayProfile() {
  const out = state.config?.display?.output || document.body.dataset.kiosk || "";
  document.body.classList.toggle("vga-kiosk", out === "vga");
  document.body.classList.toggle("pi-kiosk", Boolean(state.config?.pi));
  scaleStage();
}

function primeKioskDisplay() {
  const local = location.hostname === "127.0.0.1" || location.hostname === "localhost";
  if (document.body.dataset.kiosk !== "vga" && !local) return;
  state.config = {
    ...state.config,
    fastBoot: true,
    display: { ...(state.config.display || {}), output: "vga", scale: "fill" },
  };
  applyDisplayProfile();
  window.setTimeout(() => {
    document.querySelectorAll(".pandora-bg").forEach((bg) => bg.classList.add("loaded"));
  }, 1800);
}

function stars() {
  const root = $("stars");
  root.innerHTML = "";
  const light = Boolean(state.config.pi);
  const layers = light
    ? [{ count: 12, size: 1, dur: [40, 60], op: [0.2, 0.45], dx: 4 }]
    : [
        { count: 22, size: 1, dur: [32, 48], op: [0.16, 0.36], dx: 6 },
        { count: 18, size: 2, dur: [18, 28], op: [0.3, 0.58], dx: 12 },
        { count: 10, size: 2, dur: [10, 16], op: [0.48, 0.85], dx: 18 },
      ];
  layers.forEach((layer, depth) => {
    for (let i = 0; i < layer.count; i += 1) {
      const dot = document.createElement("span");
      const dur = layer.dur[0] + Math.random() * (layer.dur[1] - layer.dur[0]);
      dot.style.setProperty("--x", `${Math.random() * 100}%`);
      dot.style.setProperty("--dur", `${dur.toFixed(1)}s`);
      dot.style.setProperty("--delay", `${(-Math.random() * dur).toFixed(1)}s`);
      dot.style.setProperty("--dx", `${((Math.random() - 0.5) * layer.dx).toFixed(1)}px`);
      dot.style.setProperty("--op", (layer.op[0] + Math.random() * (layer.op[1] - layer.op[0])).toFixed(2));
      dot.style.width = `${layer.size}px`;
      dot.style.height = `${layer.size}px`;
      if (depth === 2 && Math.random() < 0.4) {
        dot.style.boxShadow = "0 0 3px rgba(215, 246, 255, 0.8)";
      }
      root.appendChild(dot);
    }
  });
}

function show(view) {
  state.view = view;
  state.idle = 0;
  ["boot", "home", "games", "launch", "service"].forEach((name) => {
    $("view-" + name).classList.toggle("hidden", name !== view);
  });
  syncMusic();
}

function toast(message) {
  const el = $("toast");
  el.textContent = message;
  el.classList.remove("hidden");
  window.setTimeout(() => el.classList.add("hidden"), 4200);
}

function currentSystem() {
  return state.systems[state.systemIndex];
}

function systemById(id) {
  return (state.systems || []).find((item) => item.id === id);
}

function gameSystem(game) {
  return (game && systemById(game.system)) || currentSystem();
}

function gamesFor(systemId) {
  if (systemId === "favorites") {
    const ids = new Set(state.favorites || []);
    return state.games
      .filter((game) => ids.has(game.id))
      .sort((a, b) => String(a.title).localeCompare(String(b.title), "en", { sensitivity: "base" }));
  }
  return state.games.filter((game) => game.system === systemId);
}

function gameCount(systemId) {
  if (state.gameCounts[systemId] !== undefined) return state.gameCounts[systemId];
  return gamesFor(systemId).length;
}

function rebuildGameCounts() {
  const counts = {};
  state.games.forEach((game) => {
    counts[game.system] = (counts[game.system] || 0) + 1;
  });
  counts.favorites = gamesFor("favorites").length;
  state.gameCounts = counts;
}

const LETTERS = ["#", ..."ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")];

function gameLetter(title) {
  const stripped = String(title || "")
    .replace(/^(the|a|an)\s+/i, "")
    .replace(/^[^a-z0-9]+/i, "");
  const ch = (stripped[0] || "#").toUpperCase();
  return ch >= "A" && ch <= "Z" ? ch : "#";
}

function lettersIn(list) {
  return new Set(list.map((game) => gameLetter(game.title)));
}

function firstIndexForLetter(list, letter) {
  return list.findIndex((game) => gameLetter(game.title) === letter);
}

function jumpLetter(dir, opts) {
  const list = currentGames();
  if (list.length < 2) return;
  const present = [...lettersIn(list)];
  present.sort((a, b) => LETTERS.indexOf(a) - LETTERS.indexOf(b));
  const current = gameLetter(currentGame()?.title);
  let slot = present.indexOf(current);
  if (slot < 0) slot = 0;
  const next = present[(slot + dir + present.length) % present.length];
  const index = firstIndexForLetter(list, next);
  if (index < 0 || index === state.gameIndex) return;
  state.gameIndex = index;
  if (opts && opts.skipRender) return;
  renderGames();
  if (!opts || !opts.silent) sfx("move");
}

function currentGames() {
  return gamesFor(currentSystem()?.id);
}

function currentGame() {
  return currentGames()[state.gameIndex];
}

function posterHtml(game, system) {
  if (game.cover) {
    return `<div class="poster art" aria-hidden="true"><img src="${game.cover}" alt="" onerror="this.parentNode.style.display='none'"></div>`;
  }
  const seed = [...(game.title + system.id)].reduce((sum, ch) => sum + ch.charCodeAt(0), 0);
  const a = system.accent;
  return `
    <div class="poster" aria-hidden="true">
      <b style="width:46%;height:70%;left:8%;top:12%;background:${a};opacity:.28"></b>
      <b style="width:28%;height:40%;right:10%;top:18%;background:#7cff3f;opacity:.18"></b>
      <b style="width:22%;height:22%;right:18%;bottom:16%;background:#ff7a18;opacity:.24"></b>
      <b style="width:12%;height:12%;left:${12 + (seed % 40)}%;top:${20 + (seed % 30)}%;background:#fff;opacity:.12"></b>
    </div>`;
}

function setMarquee(id, text) {
  const line = `${text}   ★   ${text}   ★   `;
  $(id).textContent = line + line;
}

function systemLogo(id) {
  return SYSTEM_LOGOS[id] || SYSTEM_LOGOS.nes;
}

function renderHome() {
  const system = currentSystem();
  if (!system) return;
  const count = gameCount(system.id);
  $("home-title").textContent = system.name;
  $("home-era").textContent = !state.catalogReady && !count
    ? `${system.era} · ${system.bits}`
    : `${count} GAMES`;
  $("home-count").textContent = !state.catalogReady && !count ? "SCAN…" : `${count} GAMES`;
  $("home-core").textContent = system.emulator.replace("RetroArch → ", "");
  const pageNum = String(state.systemIndex + 1).padStart(3, "0");
  const pageTotal = String(state.systems.length).padStart(3, "0");
  const pageEl = $("home-page");
  if (pageEl) pageEl.textContent = `${pageNum}/${pageTotal}`;
  const logoEl = $("home-sys-logo");
  if (logoEl) {
    const logo = systemLogo(system.id);
    if (logoEl.dataset.src !== logo) {
      logoEl.dataset.src = logo;
      logoEl.src = logo;
    }
    logoEl.alt = system.name;
  }
  const art = $("home-art");
  if (art) {
    const next = SYSTEM_HERO[system.id] || SYSTEM_HERO.nes;
    if (art.dataset.src !== next) {
      art.dataset.src = next;
      art.src = next;
    }
    art.alt = system.name;
  }

  const row = $("system-row");
  const sig = `${state.systems.length}:${state.catalogReady ? 1 : 0}`;
  if (row.dataset.sig !== sig || row.childElementCount !== state.systems.length) {
    row.dataset.sig = sig;
    row.innerHTML = state.systems
      .map((item, index) => {
        const active = index === state.systemIndex;
        return `
        <li class="${active ? "active" : ""}" data-index="${index}">
          <img class="sys-logo-item" src="${systemLogo(item.id)}" alt="${item.name}">
        </li>`;
      })
      .join("");
    return;
  }

  [...row.children].forEach((li, index) => {
    li.classList.toggle("active", index === state.systemIndex);
  });
}

let letterRailKey = "";

function paintLetterRail(list, activeLetter, rebuild) {
  const rail = $("letter-rail");
  const key = `${currentSystem()?.id || ""}:${list.length}`;
  rail.hidden = list.length < 8;
  if (rebuild || letterRailKey !== key || !rail.children.length) {
    letterRailKey = key;
    const present = lettersIn(list);
    rail.innerHTML = LETTERS.map((letter) => {
      const has = present.has(letter);
      const on = letter === activeLetter;
      return `<button type="button" class="${on ? "on" : ""} ${has ? "has" : "empty"}" data-letter="${letter}" ${has ? "" : "tabindex='-1'"}>${letter}</button>`;
    }).join("");
    return;
  }
  rail.querySelectorAll("button").forEach((btn) => {
    btn.classList.toggle("on", btn.dataset.letter === activeLetter);
  });
}

function paintGameWindow(list, game) {
  const page = 9;
  const start = Math.max(0, Math.min(state.gameIndex - 4, Math.max(0, list.length - page)));
  const visible = list.slice(start, start + page);
  $("game-list").innerHTML = visible
    .map((item) => {
      const active = item.id === game.id;
      const fav = isFavorite(item.id);
      return `<li class="${active ? "active" : ""} ${item.installed ? "" : "missing"}" data-id="${item.id}">
        <span class="g-star ${fav ? "on" : ""}">${fav ? "★" : active ? "☆" : ""}</span>
        <span class="g-title">${item.title}</span>
      </li>`;
    })
    .join("");
}

function renderGames(opts) {
  const system = currentSystem();
  const list = currentGames();
  if (!system) return;
  const titleEl = $("games-title");
  if (titleEl) {
    const logo = systemLogo(system.id);
    if (titleEl.dataset.src !== logo) {
      titleEl.dataset.src = logo;
      titleEl.src = logo;
    }
    titleEl.alt = system.name;
  }
  document.documentElement.style.setProperty("--card-accent", system.accent);

  if (!list.length) {
    $("rom-count").textContent = "0";
    $("letter-rail").hidden = true;
    $("letter-rail").innerHTML = "";
    letterRailKey = "";
    $("game-list").innerHTML = "";
    const empty = system.id === "favorites"
      ? "Listede bir oyuna Y (üçgen) bas — yıldızla. Sonra buradan aç."
      : (state.catalogReady ? `ROM’ları roms/${system.romDir}/ içine at.` : "Liste taranıyor…");
    $("game-stage").innerHTML = `
      <div class="stage-body">
        <p class="warn">${empty}</p>
      </div>`;
    return;
  }
  if (state.gameIndex >= list.length) state.gameIndex = 0;
  const game = list[state.gameIndex];
  $("rom-count").textContent = `${state.gameIndex + 1} / ${list.length}`;
  paintLetterRail(list, gameLetter(game.title), false);
  paintGameWindow(list, game);

  const host = gameSystem(game) || system;
  const bios = state.bios[host.id] || { ok: true };
  let warn = "";
  if (!state.config.retroarchExists) warn = "RetroArch yolu config.json içinde henüz yok.";
  else if (!bios.ok) warn = `BIOS eksik: ${(bios.needed || []).join(", ")}`;
  else if (!game.installed) warn = `ROM yok. Yasal dump'ı roms/${host.romDir}/ klasörüne koy.`;

  $("game-stage").innerHTML = `
    ${posterHtml(game, host)}
    ${warn ? `<div class="stage-body"><p class="warn">${warn}</p></div>` : ""}`;
}

async function loadCatalog() {
  const response = await fetch("/api/catalog");
  if (!response.ok) throw new Error("Katalog okunamadı");
  const data = await response.json();
  state.systems = systemsWithFav(data.systems);
  state.games = data.games;
  if (Array.isArray(data.config.favorites)) state.favorites = data.config.favorites;
  rebuildGameCounts();
  state.catalogReady = !!data.catalogReady;
  state.bios = data.bios;
  state.config = data.config;
  if (data.config.controls) state.controls = { ...state.controls, ...data.config.controls };
  if (data.config.crtFx) state.crtFx = { ...state.crtFx, ...data.config.crtFx };
  if (data.config.pi) {
    document.body.classList.add("pi-kiosk");
    stars();
  }
  applyDisplayProfile();
  state.music = data.music || [];
  applyCrt();
  syncMusic();
}

function pollCatalog() {
  if (state.catalogReady || state.launching) return;
  window.setTimeout(async () => {
    try {
      await loadCatalog();
      if (state.view === "home") renderHome();
      if (state.view === "games") renderGames();
    } catch (_error) {
      /* keep last list */
    }
    pollCatalog();
  }, 350);
}

async function launchCurrent() {
  const game = currentGame();
  const system = gameSystem(game);
  if (!game || !system || system.id === "favorites" || state.launching) return;
  show("launch");
  $("launch-sys").textContent = system.name;
  $("launch-title").textContent = game.title;
  $("launch-copy").textContent = `${system.emulator} arka planda açılıyor…`;
  state.launching = true;
  try {
    const response = await fetch("/api/launch", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: game.id }),
    });
    const result = await response.json();
    if (!result.ok) {
      sfx("error");
      show("games");
      renderGames();
      toast(result.error || "Başlatılamadı.");
      state.launching = false;
      return;
    }
    $("launch-copy").textContent = `${result.core.replace("_libretro.dll", "")} · ${result.rom}`;
    pollExit();
  }     catch (error) {
    show("games");
    toast("Launcher baglantisi koptu. F2 servis menusu.");
    state.launching = false;
  }
}

async function pollExit() {
  const tick = async () => {
    try {
      const response = await fetch("/api/status");
      const status = await response.json();
      if (!status.busy) {
        state.launching = false;
        show("games");
        renderGames();
        if (status.lastError) toast(status.lastError);
        return;
      }
    } catch (_error) {
      state.launching = false;
      show("games");
      return;
    }
    window.setTimeout(tick, 800);
  };
  window.setTimeout(tick, 900);
}

function move(delta, opts) {
  if (!delta) return;
  const silent = opts === true || (opts && opts.silent);
  const skip = opts && opts.skipRender;
  if (state.view === "home") {
    const total = state.systems.length;
    if (!total) return;
    state.systemIndex = (state.systemIndex + delta + total) % total;
    if (!skip) renderHome();
    if (!silent) sfx("move");
    return;
  }
  if (state.view === "games") {
    const total = currentGames().length;
    if (!total) return;
    state.gameIndex = (state.gameIndex + delta % total + total) % total;
    if (!skip) renderGames();
    if (!silent) sfx("move");
  }
}

function confirm() {
  if (state.view === "home") {
    sfx("ok");
    state.gameIndex = 0;
    show("games");
    renderGames();
    if (!state.catalogReady) {
      loadCatalog()
        .then(() => renderGames())
        .catch(() => renderGames());
    }
    return;
  }
  if (state.view === "games") {
    sfx("launch");
    launchCurrent();
  }
}

function back() {
  if (state.view === "games") {
    sfx("back");
    show("home");
    renderHome();
  }
}

function prettyToken(token) {
  const names = {
    ArrowUp: "↑",
    ArrowDown: "↓",
    ArrowLeft: "←",
    ArrowRight: "→",
    " ": "SPACE",
    Escape: "ESC",
    Backspace: "BKSP",
    Enter: "ENTER",
    StickUp: "STICK ↑",
    StickDown: "STICK ↓",
    StickLeft: "STICK ←",
    StickRight: "STICK →",
  };
  if (names[token]) return names[token];
  if (token.startsWith("Gamepad")) return "PAD " + token.replace("Gamepad", "");
  return String(token).toUpperCase();
}

function applyCrt() {
  document.documentElement.style.setProperty("--scanline-opacity", String(state.crtFx.scanlines));
  const heavy = state.crtFx.scanlines > 0.2 || state.crtFx.flicker || state.crtFx.rgb;
  document.body.classList.toggle("lcd-menu", !heavy);
  const flicker = $("flicker");
  const rgb = document.querySelector(".rgb-mask");
  const scan = document.querySelector(".scanlines");
  if (flicker) flicker.style.display = state.crtFx.flicker ? "" : "none";
  if (rgb) rgb.style.display = state.crtFx.rgb ? "" : "none";
  if (scan) scan.style.display = state.crtFx.scanlines > 0 ? "" : "none";
}

async function saveSettings() {
  try {
    await fetch("/api/config", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        controls: state.controls,
        crtFx: state.crtFx,
        favorites: state.favorites,
      }),
    });
  } catch (_error) {
    toast("Ayar yazılamadı.");
  }
}

function toggleFavorite() {
  if (state.view !== "games") return;
  const game = currentGame();
  if (!game) return;
  const had = isFavorite(game.id);
  state.favorites = had
    ? state.favorites.filter((id) => id !== game.id)
    : [...state.favorites, game.id];
  rebuildGameCounts();
  if (currentSystem()?.id === "favorites" && had) {
    if (state.gameIndex >= currentGames().length) {
      state.gameIndex = Math.max(0, currentGames().length - 1);
    }
  }
  renderGames();
  sfx(had ? "back" : "ok");
  saveSettings();
}

function openService() {
  if (state.view === "launch" || state.view === "boot") return;
  state.listening = null;
  state.serviceTab = 0;
  state.serviceIndex = 0;
  show("service");
  renderService();
}

function closeService() {
  state.listening = null;
  sfx("back");
  show("home");
  renderHome();
}

function serviceItems() {
  if (state.serviceTab === 1) return ACTIONS;
  if (state.serviceTab === 2) return [{ id: "sound" }, ...CRT_LEVELS, { id: "flicker" }, { id: "rgb" }];
  return [];
}

function renderService() {
  const tabs = ["TEST", "TUŞLAR", "SES"];
  $("svc-tabs").innerHTML = tabs
    .map((name, index) => `<button type="button" class="${index === state.serviceTab ? "on" : ""}" data-tab="${index}">${name}</button>`)
    .join("");
  $("pad-pill").textContent = state.padName ? "USB PAD HAZIR" : "KOL BEKLENİYOR";

  if (state.serviceTab === 0) {
    $("service-body").innerHTML = `
      <div class="svc-panel">
        <p class="svc-lead">Kol / encoder tuşuna bas — ışık yanmalı.</p>
        <div class="svc-test">
          <div class="joy">
            <i class="u" data-act="up">↑</i>
            <i class="l" data-act="left">←</i>
            <i class="c">PAD</i>
            <i class="r" data-act="right">→</i>
            <i class="d" data-act="down">↓</i>
          </div>
          <div class="hit-row">
            <i class="hit" data-act="ok">A / START</i>
            <i class="hit" data-act="back">B / GERİ</i>
            <i class="hit" data-act="service">SERVİS</i>
          </div>
          <p class="signal" id="signal-log">${state.lastSignal}</p>
        </div>
      </div>`;
    paintHeld();
    return;
  }

  if (state.serviceTab === 1) {
    $("service-body").innerHTML = `<div class="bind-list">${ACTIONS.map((item, index) => {
      const waiting = state.listening === item.id;
      const keys = (state.controls[item.id] || []).map(prettyToken).join("  +  ");
      return `<div class="bind-row ${index === state.serviceIndex ? "on" : ""} ${waiting ? "waiting" : ""}" data-index="${index}">
        <strong>${item.label}</strong>
        <span>${waiting ? "TUŞA BAS…" : keys}</span>
      </div>`;
    }).join("")}</div>`;
    return;
  }

  const scanIndex = CRT_LEVELS.findIndex((item) => item.scanlines === state.crtFx.scanlines);
  const rows = [
    { label: state.crtFx.sound !== false ? "MENÜ SESİ  ·  AÇIK" : "MENÜ SESİ  ·  KAPALI", on: state.crtFx.sound !== false },
    ...CRT_LEVELS.map((item, index) => ({
      label: item.label,
      on: index === (scanIndex < 0 ? 0 : scanIndex),
    })),
    { label: state.crtFx.flicker ? "TİTREŞİM  ·  AÇIK" : "TİTREŞİM  ·  KAPALI", on: state.crtFx.flicker },
    { label: state.crtFx.rgb ? "RGB MASKE  ·  AÇIK" : "RGB MASKE  ·  KAPALI", on: state.crtFx.rgb },
  ];
  $("service-body").innerHTML = `<div class="crt-opts">${rows
    .map((row, index) => `<button type="button" class="${index === state.serviceIndex ? "sel" : ""} ${row.on ? "on" : ""}" data-index="${index}">${row.label}</button>`)
    .join("")}</div>`;
}

function paintHeld() {
  if (state.view !== "service" || state.serviceTab !== 0) return;
  document.querySelectorAll("[data-act]").forEach((node) => {
    node.classList.toggle("hot", Boolean(state.held[node.dataset.act]));
  });
  const log = $("signal-log");
  if (log) log.textContent = state.lastSignal;
  const pill = $("pad-pill");
  if (pill) pill.textContent = state.padName ? "USB PAD" : "USB —";
}

const HOLD = { timer: 0, started: 0 };

function stopHold(refresh) {
  if (HOLD.timer) window.clearTimeout(HOLD.timer);
  HOLD.timer = 0;
  if (refresh && state.view === "games") renderGames();
}

function tickHold() {
  const action = ["up", "down", "left", "right"].find((id) => state.held[id]);
  if (!action || state.view === "boot" || state.view === "launch") {
    stopHold(true);
    return;
  }
  const elapsed = Date.now() - HOLD.started;
  let step = 1;
  let wait = 80;
  if (elapsed > 1500) {
    step = 6;
    wait = 28;
  } else if (elapsed > 800) {
    step = 3;
    wait = 42;
  } else if (elapsed > 400) {
    step = 2;
    wait = 55;
  }
  if (state.view === "games") {
    if (action === "up") move(-step, { silent: true, skipRender: true });
    else if (action === "down") move(step, { silent: true, skipRender: true });
    else if (action === "left") jumpLetter(-1, { silent: true, skipRender: true });
    else if (action === "right") jumpLetter(1, { silent: true, skipRender: true });
    renderGames({ light: true });
  } else if (state.view === "home") {
    if (action === "left" || action === "up") move(-1, { silent: true });
    else if (action === "right" || action === "down") move(1, { silent: true });
  } else if (state.view === "service") {
    if (action === "up" || action === "down") handleService(action);
  }
  HOLD.timer = window.setTimeout(tickHold, wait);
}

function startHold(action) {
  if (!["up", "down", "left", "right"].includes(action)) return;
  if (HOLD.timer) window.clearTimeout(HOLD.timer);
  HOLD.started = Date.now();
  HOLD.timer = window.setTimeout(tickHold, 140);
}

function fireAction(action) {
  state.idle = 0;
  if (["ok", "back", "service", "fav"].includes(action)) stopHold(false);
  if (state.view === "boot" || state.view === "launch") return;
  if (action === "service") {
    if (state.view === "service") return;
    openService();
    return;
  }
  if (state.view === "service") {
    handleService(action);
    return;
  }
  if (action === "left") {
    if (state.view === "home") move(-1);
    if (state.view === "games") jumpLetter(-1);
  }
  if (action === "right") {
    if (state.view === "home") move(1);
    if (state.view === "games") jumpLetter(1);
  }
  if (action === "up") move(state.view === "games" || state.view === "home" ? -1 : 0);
  if (action === "down") move(state.view === "games" || state.view === "home" ? 1 : 0);
  if (action === "ok") confirm();
  if (action === "back") back();
  if (action === "fav") toggleFavorite();
}

function handleService(action) {
  if (state.listening) return;
  if (action === "back") {
    closeService();
    return;
  }
  if (action === "left") {
    sfx("move");
    state.serviceTab = (state.serviceTab + 2) % 3;
    state.serviceIndex = 0;
    renderService();
    return;
  }
  if (action === "right") {
    sfx("move");
    state.serviceTab = (state.serviceTab + 1) % 3;
    state.serviceIndex = 0;
    renderService();
    return;
  }
  const items = serviceItems();
  if (action === "up" && items.length) {
    sfx("move");
    state.serviceIndex = (state.serviceIndex - 1 + items.length) % items.length;
    renderService();
    return;
  }
  if (action === "down" && items.length) {
    sfx("move");
    state.serviceIndex = (state.serviceIndex + 1) % items.length;
    renderService();
    return;
  }
  if (action === "ok") activateService();
}

function activateService() {
  if (state.serviceTab === 1) {
    state.listening = ACTIONS[state.serviceIndex].id;
    renderService();
    return;
  }
  if (state.serviceTab === 2) {
    if (state.serviceIndex === 0) {
      state.crtFx.sound = state.crtFx.sound === false;
      if (state.crtFx.sound) sfx("ok");
      syncMusic();
    } else if (state.serviceIndex <= CRT_LEVELS.length) {
      state.crtFx.scanlines = CRT_LEVELS[state.serviceIndex - 1].scanlines;
    } else if (state.serviceIndex === CRT_LEVELS.length + 1) {
      state.crtFx.flicker = !state.crtFx.flicker;
    } else {
      state.crtFx.rgb = !state.crtFx.rgb;
    }
    applyCrt();
    saveSettings();
    renderService();
  }
}

function ingest(token, down) {
  unlockAudio().then(() => {
    if (down) {
      syncMusic();
    }
  });
  state.lastSignal = prettyToken(token);
  if (state.listening && down) {
    const action = state.listening;
    state.controls[action] = [token];
    if (action === "ok" && token !== "Enter") state.controls.ok = [token, "Enter"];
    state.listening = null;
    saveSettings();
    renderService();
    return;
  }
  ACTIONS.forEach((item) => {
    if ((state.controls[item.id] || []).includes(token)) {
      state.held[item.id] = down;
    }
  });
  paintHeld();
  if (down) {
    const hit = ACTIONS.find((item) => (state.controls[item.id] || []).includes(token));
    if (hit) {
      fireAction(hit.id);
      startHold(hit.id);
    }
  } else if (["up", "down", "left", "right"].some((id) => (state.controls[id] || []).includes(token))) {
    stopHold(true);
  }
}

function onKey(event) {
  if (event.repeat) return;
  if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Enter", "Escape", " ", "Tab"].includes(event.key)) {
    event.preventDefault();
  }
  ingest(event.key, true);
}

function onKeyUp(event) {
  ingest(event.key, false);
}

function collectPad(now, pad) {
  const dead = 0.32;
  const ax = pad.axes[0] || 0;
  const ay = pad.axes[1] || 0;
  if (ax < -dead) now.StickLeft = true;
  if (ax > dead) now.StickRight = true;
  if (ay < -dead) now.StickUp = true;
  if (ay > dead) now.StickDown = true;
  if (pad.buttons[12] && pad.buttons[12].pressed) now.StickUp = true;
  if (pad.buttons[13] && pad.buttons[13].pressed) now.StickDown = true;
  if (pad.buttons[14] && pad.buttons[14].pressed) now.StickLeft = true;
  if (pad.buttons[15] && pad.buttons[15].pressed) now.StickRight = true;
  pad.buttons.forEach((button, index) => {
    if (button && button.pressed) now["Gamepad" + index] = true;
  });
}

function pollPad() {
  const pads = navigator.getGamepads ? [...navigator.getGamepads()].filter(Boolean) : [];
  state.padName = pads.map((pad) => pad.id.split("(")[0].trim()).join(" + ");
  if (pads.length && !state.padReady) {
    state.padReady = true;
    unlockAudio().then((ready) => ready && syncMusic());
  }
  if (!pads.length) {
    state.lastPad = {};
    window.requestAnimationFrame(pollPad);
    return;
  }
  const now = {};
  pads.forEach((pad) => collectPad(now, pad));
  const keys = new Set([...Object.keys(now), ...Object.keys(state.lastPad)]);
  keys.forEach((token) => {
    if (now[token] && !state.lastPad[token]) ingest(token, true);
    if (!now[token] && state.lastPad[token]) ingest(token, false);
  });
  state.lastPad = now;
  window.requestAnimationFrame(pollPad);
}

function bindClicks() {
  $("system-row").addEventListener("click", (event) => {
    const card = event.target.closest("[data-index]");
    if (!card) return;
    state.systemIndex = Number(card.dataset.index);
    renderHome();
    confirm();
  });
  $("back-home").addEventListener("click", back);
  $("open-service").addEventListener("click", openService);
  $("letter-rail").addEventListener("click", (event) => {
    const btn = event.target.closest("[data-letter]");
    if (!btn || btn.classList.contains("empty")) return;
    const list = currentGames();
    const index = firstIndexForLetter(list, btn.dataset.letter);
    if (index < 0) return;
    state.gameIndex = index;
    renderGames();
    sfx("move");
  });
  $("game-list").addEventListener("click", (event) => {
    const row = event.target.closest("li");
    if (!row) return;
    state.gameIndex = currentGames().findIndex((game) => game.id === row.dataset.id);
    renderGames();
  });
  $("game-stage").addEventListener("click", (event) => {
    if (event.target.id === "play-btn") launchCurrent();
  });
  $("svc-tabs").addEventListener("click", (event) => {
    const tab = event.target.closest("button");
    if (!tab) return;
    state.serviceTab = Number(tab.dataset.tab);
    state.serviceIndex = 0;
    state.listening = null;
    renderService();
  });
  $("service-body").addEventListener("click", (event) => {
    const row = event.target.closest("[data-index]");
    if (!row) return;
    state.serviceIndex = Number(row.dataset.index);
    activateService();
  });
}

function attract() {
  window.setInterval(() => {
    if (state.view === "service") return;
    state.idle += 1;
    const limit = state.config.idleDemoSeconds || 40;
    if (state.view === "home" && state.idle > limit) {
      move(1, true);
      state.idle = Math.floor(limit / 2);
    }
    if (state.view === "games" && state.idle > limit) {
      move(1, true);
      state.idle = Math.floor(limit / 2);
    }
  }, 1000);
}

function bootPadScan() {
  let ticks = 0;
  const scan = window.setInterval(() => {
    ticks += 1;
    if (navigator.getGamepads) {
      const pads = [...navigator.getGamepads()].filter(Boolean);
      if (pads.length) {
        state.padReady = true;
        state.padName = pads.map((pad) => pad.id.split("(")[0].trim()).join(" + ");
        window.clearInterval(scan);
      }
    }
    if (ticks >= 120) window.clearInterval(scan);
  }, 100);
}

function hideSplash() {
  const splash = document.getElementById("splash");
  if (!splash) return;
  let gone = false;
  const done = () => {
    if (gone) return;
    gone = true;
    splash.remove();
  };
  const img = new Image();
  img.onload = () => window.setTimeout(done, 40);
  img.onerror = done;
  img.src = "media/pandora/system_main.jpg?v=3";
  window.setTimeout(done, 2500);
}

function boot() {
  hideSplash();
  primeKioskDisplay();
  bootPadScan();
  if (!document.body.classList.contains("vga-kiosk")) stars();
  state.systems = systemsWithFav(BOOT_SYSTEMS.slice());
  show("home");
  renderHome();
  primeAudio();

  loadCatalog()
    .then(async () => {
      applyDisplayProfile();
      applyCrt();
      primeAudio();
      if (state.config.fastBoot) {
        renderHome();
        pollCatalog();
        return;
      }
      show("boot");
      applyCrt();
      const fill = $("boot-fill");
      const steps = ["Tüp ısınması", "Stella", "Mesen", "Snes9x", "Genesis Plus GX", "FBNeo", "SwanStation"];
      const stepMs = 80;
      for (let i = 0; i < steps.length; i += 1) {
        $("boot-status").textContent = `${steps[i]} hazırlanıyor…`;
        fill.style.width = `${((i + 1) / steps.length) * 100}%`;
        await new Promise((resolve) => window.setTimeout(resolve, stepMs));
      }
      show("home");
      renderHome();
      sfx("boot");
      pollCatalog();
    })
    .catch(() => {
      toast("Launcher bağlanıyor…");
      pollCatalog();
    });
}

window.addEventListener("resize", scaleStage);
window.addEventListener("blur", () => stopHold(true));
window.addEventListener("keydown", onKey);
window.addEventListener("keyup", onKeyUp);
window.addEventListener("pointerdown", () => {
  unlockAudio().then(() => primeAudio());
}, { once: true });
window.addEventListener("gamepadconnected", () => {
  state.padReady = true;
  unlockAudio().then(() => primeAudio());
});
bindClicks();
attract();
pollPad();
boot();
