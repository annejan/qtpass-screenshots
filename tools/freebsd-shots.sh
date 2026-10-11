#!/bin/sh
# SPDX-FileCopyrightText: 2026 Anne Jan Brouwer
# SPDX-License-Identifier: GPL-3.0-or-later
#
# FreeBSD screenshots of QtPass for qtpass.org's platform tiles: the Xfce
# window manager (xfwm4) with Greybird, QtPass through Qt's GTK platform
# theme, on Xvfb, with the demo store, light and dark. Run inside the
# FreeBSD VM from the repository root with the built QtPass as $1.
set -eu

QTPASS=$(realpath "$1")
OUT=$(pwd)/shots
mkdir -p "$OUT"
WORK=$(mktemp -d /tmp/qtshots.XXXX)
export HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/run" GNUPGHOME="$WORK/home/.gnupg"
mkdir -p "$HOME/.config" "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export DISPLAY=:77 LANG=en_US.UTF-8
export XDG_CURRENT_DESKTOP=XFCE QT_QPA_PLATFORMTHEME=gtk3

python3 tools/demo-store.py "$(command -v gpg)" "$WORK/store" "$(dirname "$QTPASS")/qtpass.ini"

session() { # $1: Greybird or Greybird-dark
	rm -rf "$HOME/.cache" "$HOME/.config/gtk-3.0" "$HOME/.config/xfce4"
	icons=elementary-Xfce dark=0
	if [ "$1" = Greybird-dark ]; then icons=elementary-Xfce-dark dark=1; fi
	mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
	cat >"$HOME/.config/gtk-3.0/settings.ini" <<GTK
[Settings]
gtk-theme-name=$1
gtk-icon-theme-name=$icons
gtk-font-name=Noto Sans 10
gtk-application-prefer-dark-theme=$dark
GTK
	cat >"$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" <<XFWM
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="$1"/>
    <property name="title_font" type="string" value="Noto Sans Bold 10"/>
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
XFWM
	Xvfb :77 -screen 0 1280x900x24 -dpi 96 -nolisten tcp >"$WORK/xvfb.log" 2>&1 &
	XVFB=$!
	sleep 2
	eval "$(dbus-launch --sh-syntax)"
	xfwm4 --replace >"$WORK/wm.log" 2>&1 &
	WM=$!
	sleep 4
}

end_session() {
	kill "$WM" "$XVFB" "$DBUS_SESSION_BUS_PID" 2>/dev/null || true
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
		tail -20 "$WORK/wm.log"
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

capture Greybird freebsd-app.png
capture Greybird-dark freebsd-app-dark.png
ls -l "$OUT"
