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
	mutter --x11 --replace >"$WORK/wm.log" 2>&1 &
	WM=$!
	# Qt 6.8 takes the colour scheme from the settings portal, which takes
	# it from the gsettings above.
	/usr/libexec/xdg-desktop-portal-gtk >"$WORK/portal-gtk.log" 2>&1 &
	/usr/libexec/xdg-desktop-portal >"$WORK/portal.log" 2>&1 &
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
	# The window Mutter manages (wmctrl lists only those); xdotool also
	# finds Qt's unmanaged helper windows of the same name.
	w=$(wmctrl -l | awk '$NF == "QtPass" {print $1; exit}')
	if [ -z "$w" ]; then
		import -window root "$OUT/screen-$1.png"
		tail -20 "$WORK/wm.log"
		echo "no QtPass window"
		return 1
	fi
	xdotool mousemove 1270 890
	sleep 1
	# The client's position and the frame extents Mutter sets on it give
	# the frame; tools/finish-x11.sh adds corners and shadow afterwards.
	local X Y W H L R T B
	X=$(xwininfo -id "$w" | awk '/Absolute upper-left X/ {print $4}')
	Y=$(xwininfo -id "$w" | awk '/Absolute upper-left Y/ {print $4}')
	W=$(xwininfo -id "$w" | awk '/Width:/ {print $2}')
	H=$(xwininfo -id "$w" | awk '/Height:/ {print $2}')
	read -r L R T B < <(xprop -id "$w" _NET_FRAME_EXTENTS | sed -n 's/.*= //p' | tr -d ,)
	L=${L:-0} R=${R:-0} T=${T:-0} B=${B:-0}
	echo "client $w at $X,$Y ${W}x$H, frame extents $L $R $T $B"
	import -window root -crop $((W + L + R))x$((H + T + B))+$((X - L))+$((Y - T)) +repage "$OUT/$2"
	kill "$qp" 2>/dev/null || true
	end_session
}

capture Adwaita gnome-app.png
capture Adwaita-dark gnome-app-dark.png
ls -l "$OUT"
