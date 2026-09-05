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
    hotkey: ["Gamepad10"],
    exit: ["Gamepad10"],
  },
  crtFx: { scanlines: 0, flicker: false, rgb: false, sound: true },
  serviceTab: 0,
  serviceIndex: 0,
  listening: null,
  held: {},
  lastPad: {},
  padName: "",
  lastSignal: "—",
  catalogReady: false,
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
];

const CRT_LEVELS = [
  { label: "TARAMA KAPALI", scanlines: 0 },
  { label: "TARAMA AZ", scanlines: 0.28 },
  { label: "TARAMA ORTA", scanlines: 0.55 },
  { label: "TARAMA ÇOK", scanlines: 0.78 },
];


const $ = (id) => document.getElementById(id);

let audioCtx = null;

function unlockAudio() {
  const Ctx = window.AudioContext || window.webkitAudioContext;
  if (!Ctx) return;
  if (!audioCtx) audioCtx = new Ctx();
  if (audioCtx.state === "suspended") audioCtx.resume();
}

function beep(freq, dur, vol, slide) {
  if (!state.crtFx.sound) return;
  unlockAudio();
  if (!audioCtx) return;
  const t = audioCtx.currentTime;
  const osc = audioCtx.createOscillator();
  const gain = audioCtx.createGain();
  osc.type = "square";
  osc.frequency.setValueAtTime(freq, t);
  if (slide) osc.frequency.exponentialRampToValueAtTime(Math.max(50, freq + slide), t + dur);
  gain.gain.setValueAtTime(vol || 0.055, t);
  gain.gain.exponentialRampToValueAtTime(0.001, t + dur);
  osc.connect(gain);
  gain.connect(audioCtx.destination);
  osc.start(t);
  osc.stop(t + dur + 0.02);
}

function sfx(kind) {
  if (!state.crtFx.sound) return;
  duckMusic();
  if (kind === "move") beep(1180, 0.04, 0.045);
  if (kind === "ok") {
    beep(620, 0.055, 0.05);
    window.setTimeout(() => beep(930, 0.08, 0.055), 55);
  }
  if (kind === "back") beep(390, 0.09, 0.05, -160);
  if (kind === "launch") {
    beep(392, 0.07, 0.05);
    window.setTimeout(() => beep(523, 0.07, 0.05), 80);
    window.setTimeout(() => beep(659, 0.12, 0.06), 160);
  }
  if (kind === "boot") {
    beep(523, 0.08, 0.05);
    window.setTimeout(() => beep(659, 0.08, 0.05), 90);
    window.setTimeout(() => beep(784, 0.14, 0.06), 180);
  }
  if (kind === "error") beep(180, 0.16, 0.06, -40);
}

const MUSIC_VOL = 0.055;
const MUSIC_DUCK = 0.014;
let bgm = null;
let musicIndex = 0;
let musicDuckTimer = 0;

function musicWanted() {
  const inMenu = state.view === "home" || state.view === "games";
  return Boolean(state.crtFx.sound !== false && inMenu && !state.launching && (state.music || []).length);
}

function ensureBgm() {
  if (bgm) return bgm;
  bgm = new Audio();
  bgm.preload = "auto";
  bgm.addEventListener("ended", () => {
    musicIndex = (musicIndex + 1) % Math.max(1, (state.music || []).length);
    startMusicTrack();
  });
  bgm.addEventListener("error", () => {
    musicIndex = (musicIndex + 1) % Math.max(1, (state.music || []).length);
    window.setTimeout(startMusicTrack, 500);
  });
  return bgm;
}

function startMusicTrack() {
  const tracks = state.music || [];
  if (!tracks.length || !musicWanted()) return;
  const player = ensureBgm();
  const track = tracks[musicIndex % tracks.length];
  const url = "/api/music?file=" + encodeURIComponent(track);
  if (player.dataset.track !== track) {
    player.dataset.track = track;
    player.src = url;
  }
  player.volume = MUSIC_VOL;
  player.play().catch(() => {});
}

function syncMusic() {
  if (!musicWanted()) {
    if (bgm && !bgm.paused) bgm.pause();
    return;
  }
  startMusicTrack();
}

function duckMusic() {
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
  const x = window.innerWidth / STAGE.bezelW;
  const y = window.innerHeight / STAGE.bezelH;
  const scale = Math.min(x, y);
  bezel.style.transform = `translate(${(window.innerWidth - STAGE.bezelW * scale) / 2}px, ${(window.innerHeight - STAGE.bezelH * scale) / 2}px) scale(${scale})`;
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

function gamesFor(systemId) {
  return state.games.filter((game) => game.system === systemId);
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

function renderHome() {
  const system = currentSystem();
  if (!system) return;
  const count = gamesFor(system.id).length;
  $("home-title").textContent = system.name;
  $("home-title").style.color = system.accent;
  $("home-blurb").textContent = system.blurb;
  $("home-era").textContent = `${system.era} · ${system.bits}`;
  $("home-count").textContent = !state.catalogReady && !count ? "SCAN…" : `${count} GAMES`;
  $("home-core").textContent = system.emulator.replace("RetroArch → ", "");
  $("core-pill").textContent = `${state.systems.length} SYSTEM`;
  const glow = $("home-glow");
  if (glow) glow.style.background = system.accent;
  $("home-preview").style.setProperty("--card-accent", system.accent);

  $("system-row").innerHTML = state.systems
    .map((item, index) => {
      const n = gamesFor(item.id).length;
      const meta = !state.catalogReady && !n ? "…" : String(n).padStart(3, "0");
      const num = String(index + 1).padStart(2, "0");
      return `
        <li class="${index === state.systemIndex ? "active" : ""}" data-index="${index}" style="--card-accent:${item.accent}">
          <b>${num}</b>
          <span>${item.name}</span>
          <em>${meta}</em>
        </li>`;
    })
    .join("");
}

let letterRailKey = "";

function paintLetterRail(list, activeLetter, rebuild) {
  const rail = $("letter-rail");
  const key = `${currentSystem()?.id || ""}:${list.length}`;
  rail.hidden = list.length < 12;
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
  const page = 12;
  const start = Math.max(0, Math.min(state.gameIndex - 5, Math.max(0, list.length - page)));
  const visible = list.slice(start, start + page);
  $("game-list").innerHTML = visible
    .map((item) => {
      const active = item.id === game.id;
      return `<li class="${active ? "active" : ""} ${item.installed ? "" : "missing"}" data-id="${item.id}">
        <span>${item.title}</span>
        <span class="year">${item.year}${item.installed ? "" : "  ·  YOK"}</span>
      </li>`;
    })
    .join("");
}

function renderGames(opts) {
  const light = opts && opts.light;
  const system = currentSystem();
  const list = currentGames();
  if (!system) return;
  $("games-chip").textContent = system.short;
  $("games-chip").style.color = system.accent;

  if (!list.length) {
    $("rom-count").textContent = "0";
    $("letter-rail").hidden = true;
    $("letter-rail").innerHTML = "";
    letterRailKey = "";
    $("game-list").innerHTML = "";
    $("game-stage").innerHTML = `
      <div class="stage-body">
        <p class="eyebrow">${system.name}</p>
        <h2>${state.catalogReady ? "KLASÖR BOŞ" : "TARANIYOR"}</h2>
        <p class="warn">${state.catalogReady ? `ROM’ları roms/${system.romDir}/ içine at. Adı menüde görünür.` : "USB’deki oyun listesi hazırlanıyor…"}</p>
      </div>`;
    return;
  }
  if (state.gameIndex >= list.length) state.gameIndex = 0;
  const game = list[state.gameIndex];
  $("rom-count").textContent = `${state.gameIndex + 1} / ${list.length}`;
  paintLetterRail(list, gameLetter(game.title), false);
  paintGameWindow(list, game);

  if (light) {
    const title = $("game-stage") && $("game-stage").querySelector("h2");
    if (title) title.textContent = game.title;
    return;
  }

  setMarquee("games-marquee", `${system.emulator}  ·  ${list.length} oyun  ·  sol-sag harf`);
  const bios = state.bios[system.id] || { ok: true };
  const canPlay = game.installed && bios.ok && state.config.retroarchExists;
  let warn = "";
  if (!state.config.retroarchExists) warn = "RetroArch yolu config.json içinde henüz yok.";
  else if (!bios.ok) warn = `BIOS eksik: ${(bios.needed || []).join(", ")}`;
  else if (!game.installed) warn = `ROM yok. Yasal dump'ı roms/${system.romDir}/ klasörüne koy.`;

  $("game-stage").innerHTML = `
    ${posterHtml(game, system)}
    <div class="stage-body">
      <p class="eyebrow">${system.name}</p>
      <h2>${game.title}</h2>
      <div class="facts">
        <span>${game.year}</span>
        <span>${game.players} OYUNCU</span>
        <span>${game.genre}</span>
        <span>${game.installed ? "DUMP HAZIR" : "DUMP YOK"}</span>
      </div>
      <button class="play ${canPlay ? "" : "disabled"}" id="play-btn" type="button">${canPlay ? "BAŞLAT" : "HAZIR DEĞİL"}</button>
      ${warn ? `<p class="warn">${warn}</p>` : `<p class="warn" style="color:#8b97a8">Start basınca ${system.cores[0].replace("_libretro.dll", "")} gizlenerek açılır.</p>`}
    </div>`;
}

async function loadCatalog() {
  const response = await fetch("/api/catalog");
  if (!response.ok) throw new Error("Katalog okunamadı");
  const data = await response.json();
  state.systems = data.systems;
  state.games = data.games;
  state.catalogReady = !!data.catalogReady;
  state.bios = data.bios;
  state.config = data.config;
  if (data.config.controls) state.controls = { ...state.controls, ...data.config.controls };
  if (data.config.crtFx) state.crtFx = { ...state.crtFx, ...data.config.crtFx };
  if (data.config.pi) {
    document.body.classList.add("pi-kiosk");
    stars();
  }
  state.music = data.music || [];
  applyCrt();
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
  const system = currentSystem();
  if (!game || state.launching) return;
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
      body: JSON.stringify({ controls: state.controls, crtFx: state.crtFx }),
    });
  } catch (_error) {
    toast("Ayar yazılamadı.");
  }
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
  if (state.serviceTab === 2) return [...CRT_LEVELS, { id: "flicker" }, { id: "rgb" }, { id: "sound" }];
  return [];
}

function renderService() {
  const tabs = ["TEST", "TUŞ ATA", "CRT"];
  $("svc-tabs").innerHTML = tabs
    .map((name, index) => `<button type="button" class="${index === state.serviceTab ? "on" : ""}" data-tab="${index}">${name}</button>`)
    .join("");
  $("pad-pill").textContent = state.padName ? "USB PAD" : "USB —";

  if (state.serviceTab === 0) {
    $("service-body").innerHTML = `
      <div class="svc-grid">
        <div>
          <p class="eyebrow">JOYSTICK</p>
          <div class="joy">
            <i class="u" data-act="up">↑</i>
            <i class="l" data-act="left">←</i>
            <i class="c"></i>
            <i class="r" data-act="right">→</i>
            <i class="d" data-act="down">↓</i>
          </div>
        </div>
        <div>
          <p class="eyebrow">BUTONLAR</p>
          <div class="hit-row">
            <i class="hit" data-act="ok">START</i>
            <i class="hit" data-act="back">GERİ</i>
            <i class="hit" data-act="service">SERVİS</i>
          </div>
          <p class="signal" id="signal-log">${state.lastSignal}</p>
          <p class="wire-note">Oyunda Start oyuna aittir. Çıkış: PS tuşu (veya ESC). ARC Controller: Happ stick → AU AD AL AR. Buton 1–6 aksiyon, 10 Start, 11 servis/coin.</p>
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
    }).join("")}</div><p class="wire-note">Start oyunda Start kalsın. Çıkış için PS tuşu. İkisini aynı tuşa verirsen tek basış çıkar.</p>`;
    return;
  }

  const scanIndex = CRT_LEVELS.findIndex((item) => item.scanlines === state.crtFx.scanlines);
  const rows = [
    ...CRT_LEVELS.map((item, index) => ({
      label: item.label,
      on: index === (scanIndex < 0 ? 2 : scanIndex),
    })),
    { label: state.crtFx.flicker ? "TİTREŞİM AÇIK" : "TİTREŞİM KAPALI", on: false },
    { label: state.crtFx.rgb ? "RGB MASKE AÇIK" : "RGB MASKE KAPALI", on: false },
    { label: state.crtFx.sound !== false ? "MENÜ SESİ AÇIK" : "MENÜ SESİ KAPALI", on: false },
  ];
  $("service-body").innerHTML = `<div class="crt-opts">${rows
    .map((row, index) => `<button type="button" class="${index === state.serviceIndex || row.on ? "on" : ""}" data-index="${index}">${row.label}</button>`)
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
    handleService(action);
  }
  HOLD.timer = window.setTimeout(tickHold, wait);
}

function startHold(action) {
  if (!["up", "down", "left", "right"].includes(action)) return;
  if (HOLD.timer) window.clearTimeout(HOLD.timer);
  HOLD.started = Date.now();
  HOLD.timer = window.setTimeout(tickHold, 220);
}

function fireAction(action) {
  state.idle = 0;
  if (["ok", "back", "service"].includes(action)) stopHold(false);
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
}

function handleService(action) {
  if (state.listening) return;
  if (action === "back") {
    closeService();
    return;
  }
  if (state.serviceTab === 0) {
    if (action === "ok") {
      state.serviceTab = 1;
      state.serviceIndex = 0;
      renderService();
    }
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
    if (state.serviceIndex < CRT_LEVELS.length) {
      state.crtFx.scanlines = CRT_LEVELS[state.serviceIndex].scanlines;
    } else if (state.serviceIndex === CRT_LEVELS.length) {
      state.crtFx.flicker = !state.crtFx.flicker;
    } else if (state.serviceIndex === CRT_LEVELS.length + 1) {
      state.crtFx.rgb = !state.crtFx.rgb;
    } else {
      state.crtFx.sound = state.crtFx.sound === false;
      if (state.crtFx.sound) sfx("ok");
      syncMusic();
    }
    applyCrt();
    saveSettings();
    renderService();
  }
}

function ingest(token, down) {
  unlockAudio();
  if (down) syncMusic();
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
  const dead = 0.46;
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

async function boot() {
  stars();
  scaleStage();
  applyCrt();
  const catalogPromise = loadCatalog();
  const fill = $("boot-fill");
  const steps = ["Tüp ısınması", "Stella", "Mesen", "Snes9x", "Genesis Plus GX", "FBNeo", "SwanStation"];
  const stepMs = 80;
  for (let i = 0; i < steps.length; i += 1) {
    $("boot-status").textContent = `${steps[i]} hazırlanıyor…`;
    fill.style.width = `${((i + 1) / steps.length) * 100}%`;
    await new Promise((resolve) => window.setTimeout(resolve, stepMs));
  }
  try {
    await catalogPromise;
  } catch (_error) {
    $("boot-status").textContent = "start.bat ile aç. Launcher kapalı.";
    return;
  }
  show("home");
  renderHome();
  sfx("boot");
  pollCatalog();
}

window.addEventListener("resize", scaleStage);
window.addEventListener("blur", () => stopHold(true));
window.addEventListener("keydown", onKey);
window.addEventListener("keyup", onKeyUp);
window.addEventListener("gamepadconnected", () => toast("USB encoder bulundu."));
bindClicks();
attract();
pollPad();
boot();
