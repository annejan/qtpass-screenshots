#!/bin/bash
# SPDX-FileCopyrightText: 2026 Anne Jan Brouwer
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Two captures of the same window, on a black and on a white background,
# give its real transparency (corners, shadow): alpha = 1 - (white - black),
# colour = black / alpha. Then trim the fully transparent border.
#
#   alpha-from-pair.sh BLACK.png WHITE.png OUT.png
set -euo pipefail
black=$1 white=$2 out=$3
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
magick "$white" "$black" -compose minus_src -composite -colorspace gray -negate "$tmp/alpha.png"
magick "$black" "$tmp/alpha.png" -fx 'v.r > 0.004 ? u / v.r : 0' "$tmp/colour.png"
magick "$tmp/colour.png" "$tmp/alpha.png" -alpha off -compose copy_opacity -composite \
  -trim +repage -define png:compression-level=9 -strip "$out"
