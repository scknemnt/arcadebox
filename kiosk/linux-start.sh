#!/bin/sh
# Arcade Box kiosk — systemd / startx
# Log: /tmp/arcadebox-kiosk.log

LOG=/tmp/arcadebox-kiosk.log
exec >>"$LOG" 2>&1
echo "=== $(date) linux-start ==="

export DISPLAY="${DISPLAY:-:0}"

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
  for out in VGA-1 VGA-0 HDMI-1; do
    xrandr --output "$out" --auto 2>/dev/null && break
  done
fi

unclutter -idle 0.4 -root >/dev/null 2>&1 &

# startx/getty oturumunda Pulse soketi icin
uid="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$uid}"
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
  export XDG_RUNTIME_DIR="/tmp/runtime-$uid"
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
fi

# Firefox Pulse ister; menü muzigi ALSA/aplay kullanir. Ikisini de ayaga kaldir.
if command -v pipewire >/dev/null 2>&1; then
  pipewire >/dev/null 2>&1 &
  command -v pipewire-pulse >/dev/null 2>&1 && pipewire-pulse >/dev/null 2>&1 &
  command -v wireplumber >/dev/null 2>&1 && wireplumber >/dev/null 2>&1 &
  n=0
  while [ "$n" -lt 20 ]; do
    [ -S "$XDG_RUNTIME_DIR/pulse/native" ] && break
    n=$((n + 1))
    sleep 0.25
  done
elif command -v pulseaudio >/dev/null 2>&1; then
  pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1 || pulseaudio --daemonize=true 2>/dev/null || true
fi

if command -v amixer >/dev/null 2>&1; then
  amixer -q sset Master 90% unmute 2>/dev/null || true
  amixer -q sset PCM 90% unmute 2>/dev/null || true
  amixer -q sset Speaker 90% unmute 2>/dev/null || true
  amixer -q sset Headphone 90% unmute 2>/dev/null || true
  amixer -q sset Line 90% unmute 2>/dev/null || true
fi

if command -v pactl >/dev/null 2>&1; then
  analog="$(pactl list short sinks 2>/dev/null | awk '/analog|alsa_output/ && $0 !~ /hdmi|hdmi/ { print $2; exit }')"
  if [ -n "$analog" ]; then
    pactl set-default-sink "$analog" 2>/dev/null || true
  fi
  pactl set-sink-mute @DEFAULT_SINK@ 0 2>/dev/null || true
  pactl set-sink-volume @DEFAULT_SINK@ 90% 2>/dev/null || true
fi

if [ -f /proc/asound/pcm ]; then
  echo "ALSA pcm:" >>"$LOG"
  cat /proc/asound/pcm >>"$LOG" 2>&1 || true
fi
if command -v aplay >/dev/null 2>&1; then
  echo "aplay -l:" >>"$LOG"
  aplay -l >>"$LOG" 2>&1 || true
fi

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
EOF
  (
    n=0
    while [ "$n" -lt 25 ]; do
      sleep 0.4
      if command -v xdotool >/dev/null 2>&1; then
        xdotool search --onlyvisible --class Firefox windowactivate --sync click 1 && break
      fi
      n=$((n + 1))
    done
  ) >/dev/null 2>&1 &
  python3 backend/arcadebox.py --kiosk --no-browser &
  srv=$!
  sleep 1
  if ! kill -0 "$srv" 2>/dev/null; then
    echo "HATA: python server hemen kapandi"
    wait "$srv" 2>/dev/null || true
    exit 1
  fi
  echo "python pid=$srv, firefox-esr aciliyor DISPLAY=$DISPLAY profile=$FF_PROF"
  exec firefox-esr --kiosk --no-first-run --disable-session-restore --no-remote --profile "$FF_PROF" "$URL"
fi

exec python3 backend/arcadebox.py --kiosk
