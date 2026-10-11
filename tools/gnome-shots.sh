#!/bin/bash
# SPDX-FileCopyrightText: 2026 Anne Jan Brouwer
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Linux/GNOME screenshots of QtPass: Mutter (GNOME's window manager, with
# its Adwaita title bars) on Xvfb, QtPass through Qt's GTK platform theme
# with Adwaita / Adwaita-dark, the demo store, light and dark.
#   tools/gnome-shots.sh path/to/qtpass
set -euo pipefail

QTPASS=$(realpath "$1")
OUT=$(pwd)/shots
mkdir -p "$OUT"
WORK=$(mktemp -d /tmp/qtshots.XXXX)
export HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/run" GNUPGHOME="$WORK/home/.gnupg"
mkdir -p "$HOME/.config" "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export DISPLAY=:77 LANG=en_US.UTF-8 XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_TYPE=x11
export QT_QPA_PLATFORMTHEME=gtk3

python3 tools/demo-store.py "$(command -v gpg)" "$WORK/store" "$(dirname "$QTPASS")/qtpass.ini"

session() { # $1: Adwaita or Adwaita-dark
	rm -rf "$HOME/.cache"
	local scheme=default dark=0
	if [ "$1" = Adwaita-dark ]; then scheme=prefer-dark dark=1; fi
	mkdir -p "$HOME/.config/gtk-3.0"
	printf '[Settings]\ngtk-theme-name=%s\ngtk-icon-theme-name=Adwaita\ngtk-font-name=Cantarell 11\ngtk-application-prefer-dark-theme=%s\n' \
		"$1" "$dark" >"$HOME/.config/gtk-3.0/settings.ini"
	Xvfb :77 -screen 0 1280x900x24 -dpi 96 -nolisten tcp >"$WORK/xvfb.log" 2>&1 &
	XVFB=$!
	sleep 2
	eval "$(dbus-launch --sh-syntax)"
	gsettings set org.gnome.desktop.interface color-scheme "$scheme"
	gsettings set org.gnome.desktop.interface gtk-theme "$1"
	gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
	gsettings set org.gnome.desktop.background picture-options none
	gsettings set org.gnome.desktop.background color-shading-type solid
	gsettings set org.gnome.desktop.background primary-color '#000000'
	mutter --x11 --replace >"$WORK/wm.log" 2>&1 &
	WM=$!
	sleep 5
}

end_session() {
	kill "$WM" "$XVFB" "$DBUS_SESSION_BUS_PID" 2>/dev/null || true
	sleep 2
}

capture() { # $1 theme, $2 output name
	session "$1"
	"$QTPASS" >"$OUT/qtpass-$1.log" 2>&1 &
	local qp=$!
	sleep 6
	# "." loads every folder (the filter hides folders not loaded yet), then
	# the real search selects and opens the first match, twice to be sure.
	"$QTPASS" . >>"$OUT/qtpass-$1.log" 2>&1 || true
	sleep 4
	"$QTPASS" example.com >>"$OUT/qtpass-$1.log" 2>&1 || true
	sleep 3
	"$QTPASS" example.com >>"$OUT/qtpass-$1.log" 2>&1 || true
	sleep 5
	local w
	w=$(xdotool search --onlyvisible --name '^QtPass$' | head -1)
	if [ -z "$w" ]; then
		import -window root "$OUT/screen-$1.png"
		tail -20 "$WORK/wm.log"
		echo "no QtPass window"
		return 1
	fi
	xdotool mousemove 1270 890
	sleep 1
	# Mutter reparents the client into its frame; capture the frame plus a
	# margin for Mutter's shadow, once on a black and once on a white
	# desktop, and let alpha-from-pair.sh work out the real transparency.
	local frame X Y W H m=48
	frame=$(xwininfo -children -id "$w" | awk '/Parent window id/ {print $4}')
	X=$(xwininfo -id "$frame" | awk '/Absolute upper-left X/ {print $4}')
	Y=$(xwininfo -id "$frame" | awk '/Absolute upper-left Y/ {print $4}')
	W=$(xwininfo -id "$frame" | awk '/Width:/ {print $2}')
	H=$(xwininfo -id "$frame" | awk '/Height:/ {print $2}')
	for bg in black white; do
		local colour='#000000'
		[ "$bg" = white ] && colour='#ffffff'
		gsettings set org.gnome.desktop.background primary-color "$colour"
		sleep 2
		import -window root -crop $((W + 2 * m))x$((H + 2 * m))+$((X - m))+$((Y - m)) +repage "$WORK/$bg.png"
	done
	tools/alpha-from-pair.sh "$WORK/black.png" "$WORK/white.png" "$OUT/$2"
	kill "$qp" 2>/dev/null || true
	end_session
}

capture Adwaita gnome-app.png
capture Adwaita-dark gnome-app-dark.png
ls -l "$OUT"
