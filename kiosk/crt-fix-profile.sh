#!/bin/sh
# Bozuk .profile / .bash_profile duzelt (fi hatasi, /,,# vb.)
#   sudo sh kiosk/crt-fix-profile.sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/crt-fix-profile.sh"
  exit 1
fi

USER_NAME="${SUDO_USER:-arcadebox}"
HOME_DIR="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="/home/$USER_NAME"

cat > "$HOME_DIR/.profile" <<'PROF'
# ~/.profile — Arcade Box (temiz)
if [ -n "$BASH_VERSION" ]; then
  if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
  fi
fi
PROF

cat > "$HOME_DIR/.bash_profile" <<EOF
# Arcade Box kiosk
if [ -f "\$HOME/.profile" ]; then
  . "\$HOME/.profile"
fi
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
  exec startx "$HOME_DIR/.xinitrc" -- :0 vt1 -nocursor
fi
EOF

chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.profile" "$HOME_DIR/.bash_profile"
echo "OK: .profile + .bash_profile yenilendi"
echo "Test: bash -n $HOME_DIR/.profile && bash -n $HOME_DIR/.bash_profile && echo syntax OK"
