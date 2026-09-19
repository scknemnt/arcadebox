#!/bin/sh
# Arcade Box kiosk — systemd / startx
# Log: /tmp/arcadebox-kiosk.log

LOG=/tmp/arcadebox-kiosk.log
exec >>"$LOG" 2>&1
echo "=== $(date) linux-start ==="

export DISPLAY="${DISPLAY:-:0}"
xsetroot -solid "#1a0505" 2>/dev/null || true

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
if [ ! -f "$ROOT/backend/arcadebox.py" ]; then
  for d in /mnt/games/ArcadeBox /mnt/arcade/ArcadeBox /media/*/ArcadeBox /media/*/*/ArcadeBox /mnt/*/ArcadeBox "$HOME/ArcadeBox"; do
    if [ -f "$d/backend/arcadebox.py" ]; then
      ROOT="$d"
      break
    fi
  done
fi

# HDD gec baglanirsa bekle
wait=0
while [ "$wait" -lt 60 ]; do
  if [ -f "$ROOT/backend/arcadebox.py" ]; then
    break
  fi
  mount /mnt/games 2>/dev/null || mount -a 2>/dev/null || true
  if [ -f /mnt/games/ArcadeBox/backend/arcadebox.py ]; then
    ROOT="/mnt/games/ArcadeBox"
    break
  fi
  wait=$((wait + 1))
  sleep 1
done

if [ ! -f "$ROOT/backend/arcadebox.py" ]; then
  echo "HATA: ArcadeBox bulunamadi. lsblk + fstab kontrol."
  lsblk >>"$LOG" 2>&1
  cat /etc/fstab >>"$LOG" 2>&1
  sleep 300
  exit 1
fi

cd "$ROOT" || exit 1
echo "ROOT=$ROOT"

xset s off 2>/dev/null
xset -dpms 2>/dev/null
xset s noblank 2>/dev/null

if [ -e /sys/firmware/devicetree/base/model ] && command -v xrandr >/dev/null 2>&1; then
  for out in HDMI-1 HDMI-2 HDMI-A-1 HDMI-A-2; do
    xrandr --output "$out" --mode 1280x720 --rate 50 2>/dev/null || \
    xrandr --output "$out" --mode 1920x1080 --rate 50 2>/dev/null || \
    xrandr --output "$out" --rate 50 2>/dev/null || true
  done
  xrandr -r 50 2>/dev/null || true
fi

if [ "$(uname -m)" = "x86_64" ] && command -v xrandr >/dev/null 2>&1; then
  CRT_VGA=0
  if [ -f "$ROOT/config.json" ] && grep -q '"crt"[[:space:]]*:[[:space:]]*true' "$ROOT/config.json" 2>/dev/null; then
    CRT_VGA=1
  fi
  for out in VGA-1 VGA-0 VGA1; do
    if ! xrandr --query 2>/dev/null | grep -q "^${out} connected"; then
      continue
    fi
    if [ "$CRT_VGA" = 1 ]; then
      if [ -f "$ROOT/kiosk/crt-xrandr-pal.sh" ]; then
        sh "$ROOT/kiosk/crt-xrandr-pal.sh" && echo "CRT: crt-xrandr-pal.sh OK" || \
          echo "UYARI: crt-xrandr-pal.sh basarisiz"
      else
        xrandr --output "$out" --mode 640x480 2>/dev/null || \
        xrandr --output "$out" --auto 2>/dev/null || true
      fi
      break
    fi
    xrandr --output "$out" --auto 2>/dev/null && break
  done
fi

unclutter -idle 0.4 -root >/dev/null 2>&1 &

# Ses, ekrani bekletmesin — arka planda
uid="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$uid}"
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
  export XDG_RUNTIME_DIR="/tmp/runtime-$uid"
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
fi

(
  if command -v pipewire >/dev/null 2>&1; then
    pipewire >/dev/null 2>&1 &
    command -v pipewire-pulse >/dev/null 2>&1 && pipewire-pulse >/dev/null 2>&1 &
    command -v wireplumber >/dev/null 2>&1 && wireplumber >/dev/null 2>&1 &
  elif command -v pulseaudio >/dev/null 2>&1; then
    pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1 || pulseaudio --daemonize=true 2>/dev/null || true
  fi
  sleep 1
  amixer -q sset Master 90% unmute 2>/dev/null || true
  amixer -q sset PCM 90% unmute 2>/dev/null || true
  amixer -q sset Speaker 90% unmute 2>/dev/null || true
  amixer -q sset Headphone 90% unmute 2>/dev/null || true
  if command -v pactl >/dev/null 2>&1; then
    analog="$(pactl list short sinks 2>/dev/null | awk '/analog/ && $0 !~ /hdmi/ { print $2; exit }')"
    [ -n "$analog" ] && pactl set-default-sink "$analog" 2>/dev/null || true
    pactl set-sink-mute @DEFAULT_SINK@ 0 2>/dev/null || true
    pactl set-sink-volume @DEFAULT_SINK@ 90% 2>/dev/null || true
  fi
) >/dev/null 2>&1 &

URL="http://127.0.0.1:7842/"

if [ "$(uname -m)" = "x86_64" ] && command -v firefox-esr >/dev/null 2>&1; then
  modprobe joydev 2>/dev/null || true
  FF_PROF="$HOME/.arcadebox-firefox"
  mkdir -p "$FF_PROF"
  cat >"$FF_PROF/user.js" <<'EOF'
user_pref("media.autoplay.default", 0);
user_pref("media.autoplay.enabled", true);
user_pref("media.autoplay.blocking_policy", 0);
user_pref("media.autoplay.block-webaudio", false);
user_pref("media.autoplay.allow-muted", true);
user_pref("media.block-autoplay-until-in-foreground", false);
user_pref("dom.gamepad.enabled", true);
user_pref("dom.gamepad.non_standard_events.enabled", true);
user_pref("browser.display.background_color", "#120404");
user_pref("browser.display.use_system_colors", false);
user_pref("browser.cache.disk.enable", true);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("app.update.enabled", false);
user_pref("extensions.pocket.enabled", false);
EOF
  python3 backend/arcadebox.py --kiosk --no-browser &
  srv=$!
  n=0
  while [ "$n" -lt 40 ]; do
    if python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:7842/', timeout=0.2)" >/dev/null 2>&1; then
      break
    fi
    if ! kill -0 "$srv" 2>/dev/null; then
      echo "HATA: python server hemen kapandi"
      wait "$srv" 2>/dev/null || true
      exit 1
    fi
    n=$((n + 1))
    sleep 0.1
  done
  echo "python pid=$srv, firefox-esr aciliyor DISPLAY=$DISPLAY profile=$FF_PROF"
  pkill firefox-esr 2>/dev/null || true
  sleep 1
  while true; do
    echo "firefox baslat $(date)"
    firefox-esr --kiosk --no-first-run --disable-session-restore --no-remote --profile "$FF_PROF" "$URL" \
      || echo "firefox cikti code=$? $(date)" >>"$LOG"
    sleep 3
  done
fi

exec python3 backend/arcadebox.py --kiosk
