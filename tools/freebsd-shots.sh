#!/bin/sh
# SPDX-FileCopyrightText: 2026 Anne Jan Brouwer
# SPDX-License-Identifier: GPL-3.0-or-later
#
# FreeBSD screenshots of QtPass for qtpass.org's platform tiles: KWin and
# Breeze on Xvfb, the demo store, light and dark. Run inside the FreeBSD VM
# from the repository root with the built QtPass as $1.
set -eu

QTPASS=$(realpath "$1")
OUT=$(pwd)/shots
mkdir -p "$OUT"
WORK=$(mktemp -d /tmp/qtshots.XXXX)
export HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/run" GNUPGHOME="$WORK/home/.gnupg"
mkdir -p "$HOME/.config" "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export DISPLAY=:77 LANG=en_US.UTF-8
export XDG_CURRENT_DESKTOP=KDE KDE_SESSION_VERSION=6 KDE_FULL_SESSION=true
export QT_QPA_PLATFORMTHEME=kde QT_STYLE_OVERRIDE=Breeze

python3 tools/demo-store.py "$(command -v gpg)" "$WORK/store" "$(dirname "$QTPASS")/qtpass.ini"

session() { # $1: BreezeLight or BreezeDark
	rm -rf "$HOME/.cache"
	cp "/usr/local/share/color-schemes/$1.colors" "$HOME/.config/kdeglobals"
	icons=breeze; [ "$1" = BreezeDark ] && icons=breeze-dark
	cat >>"$HOME/.config/kdeglobals" <<KDE

[KDE]
widgetStyle=Breeze

[Icons]
Theme=$icons

[General]
ColorScheme=$1
font=Noto Sans,10,-1,5,50,0,0,0,0,0
KDE
	printf '[org.kde.kdecoration2]\nlibrary=org.kde.breeze\ntheme=Breeze\n\n[Compositing]\nEnabled=false\n' >"$HOME/.config/kwinrc"
	Xvfb :77 -screen 0 1280x900x24 -dpi 96 -nolisten tcp >"$WORK/xvfb.log" 2>&1 &
	XVFB=$!
	sleep 2
	eval "$(dbus-launch --sh-syntax)"
	kwin_x11 --replace >"$WORK/kwin.log" 2>&1 &
	KWIN=$!
	sleep 4
}

end_session() {
	kill "$KWIN" "$XVFB" "$DBUS_SESSION_BUS_PID" 2>/dev/null || true
	sleep 2
}

capture() { # $1 scheme, $2 output name
	session "$1"
	"$QTPASS" >"$OUT/qtpass-$1.log" 2>&1 &
	qp=$!
	sleep 6
	# "." loads every folder (the filter hides folders not loaded yet), then
	# the real search selects and opens the first match, twice to be sure.
	"$QTPASS" . >>"$OUT/qtpass-$1.log" 2>&1 || true
	sleep 4
	"$QTPASS" example.com >>"$OUT/qtpass-$1.log" 2>&1 || true
	sleep 3
	"$QTPASS" example.com >>"$OUT/qtpass-$1.log" 2>&1 || true
	sleep 5
	w=$(xdotool search --onlyvisible --name '^QtPass$' | head -1)
	if [ -z "$w" ]; then
		import -window root "$OUT/screen-$1.png"
		tail -20 "$WORK/kwin.log"
		echo "no QtPass window"; return 1
	fi
	xdotool mousemove 1270 890
	sleep 1
	eval "$(xdotool getwindowgeometry --shell "$w")"
	read -r L R T B <<EXT
$(xprop -id "$w" _NET_FRAME_EXTENTS | sed 's/.*= //; s/,//g')
EXT
	L=${L:-0} R=${R:-0} T=${T:-0} B=${B:-0}
	import -window root -crop $((WIDTH + L + R))x$((HEIGHT + T + B))+$((X - L))+$((Y - T)) +repage "$OUT/$2"
	kill "$qp" 2>/dev/null || true
	end_session
}

capture BreezeLight freebsd-app.png
capture BreezeDark freebsd-app-dark.png
ls -l "$OUT"
