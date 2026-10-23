#!/usr/bin/env bash
# Composes the store images from the raw captures of the app: each frame is
# frame.html (a caption over the real screen) rendered by headless Chrome at
# the exact store size, then saved as JPEG; the Play feature graphic is
# feature.html at 1024x500. Run from the repository root, after
# `make store-screens-raw` has written app/build/store_screens/raw.
#
# Everything is rendered and checked in a temporary folder first; the
# committed images are replaced only when every check passes.
set -euo pipefail

chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
here="app/store_screens"
raw="app/build/store_screens/raw"
play="app/fastlane/metadata/android/pt-BR/images"
ios="app/fastlane/screenshots/ios/pt-BR"

[ -x "$chrome" ] || { echo "compose: Google Chrome not found at $chrome" >&2; exit 1; }
[ -d "$raw" ] || { echo "compose: no raw captures in $raw; run make store-screens-raw" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
out="$tmp/out"

# profile, store width, store height, output path with NN in place of the frame.
profiles=(
  "android_phone 1080 1920 $play/phoneScreenshots/NN.jpg"
  "android_tablet10 1600 2560 $play/tenInchScreenshots/NN.jpg"
  "iphone61 1179 2556 $ios/NN_iphone61.jpg"
  "ipad13 2064 2752 $ios/NN_ipad13.jpg"
)

# Percent-encodes a path or a value for a file URL or a query string.
urlencode() {
  python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1"
}

# The part of a capture a frame shows: "x0,y0,x1" from focus.tsv, or all of it.
focus() {
  awk -F'\t' -v nn="$1" -v p="$2" '$1==nn && $2==p {print $3","$4","$5; found=1}
    END {if (!found) print "0,0,1"}' "$here/focus.tsv"
}

# Fails unless the bottom row of the image has a pixel lighter than the
# ground: the screen card (or its cream rim) must run off the bottom edge,
# and a blank page, which the templates leave when the brand font or the
# capture fails, has none.
bleeds() {
  sips -s format bmp "$1" --out "$tmp/check.bmp" >/dev/null
  python3 - "$tmp/check.bmp" <<'PY'
import struct, sys
data = open(sys.argv[1], "rb").read()
offset, = struct.unpack_from("<I", data, 10)
width, height = struct.unpack_from("<ii", data, 18)
bpp, = struct.unpack_from("<H", data, 28)
step = bpp // 8
stride = (width * step + 3) & ~3
# Rows are stored bottom-up unless the height is negative.
row = offset if height > 0 else offset + (abs(height) - 1) * stride
ground = 0x1E + 0x5B + 0x66
for x in range(width):
    b, g, r = data[row + x * step: row + x * step + 3]
    if r + g + b > ground + 60:
        sys.exit(0)
sys.exit(1)
PY
}

# render <page file> <query> <width> <height> <dest jpg>
render() {
  local page="$1" query="$2" w="$3" h="$4" dest="$5" png="$tmp/shot.png"
  local url="file://$(urlencode "$PWD/$page")${query:+?$query}"
  mkdir -p "$(dirname "$dest")"
  # A fresh throwaway profile per render keeps it apart from any Chrome
  # already open; the virtual time budget lets the font and the capture load
  # before the shot. Chrome may exit non-zero on teardown after writing the
  # shot, so success is the file it wrote. Now and then headless Chrome
  # paints a viewport a few pixels shorter than the window, leaving a strip
  # of ground at the bottom; the bleed check catches it and the render is
  # tried again.
  local attempt
  for attempt in 1 2 3; do
    rm -rf "$png" "$tmp/profile"
    "$chrome" --headless --disable-gpu --hide-scrollbars \
      --force-device-scale-factor=1 --user-data-dir="$tmp/profile" \
      --virtual-time-budget=5000 --allow-file-access-from-files \
      --window-size="$w,$h" --screenshot="$png" "$url" >/dev/null 2>&1 || true
    [ -s "$png" ] && bleeds "$png" && break
    if [ "$attempt" -eq 3 ]; then
      echo "compose: $dest is blank, or its screen does not reach the bottom edge" >&2
      exit 1
    fi
  done
  sips -s format jpeg -s formatOptions 92 "$png" --out "$dest" >/dev/null
}

written=()
while IFS=$'\t' read -r nn caption; do
  [ -n "$nn" ] || continue
  for p in "${profiles[@]}"; do
    read -r profile w h pattern <<<"$p"
    src="$raw/$profile/$nn.png"
    [ -f "$src" ] || { echo "compose: missing raw capture $src" >&2; exit 1; }
    dest="${pattern/NN/$nn}"
    query="w=$w&h=$h&caption=$(urlencode "$caption")&crop=$(focus "$nn" "$profile")"
    query+="&shot=$(urlencode "file://$PWD/$src")"
    render "$here/frame.html" "$query" "$w" "$h" "$out/$dest"
    written+=("$dest $w $h")
  done
done <"$here/captions.tsv"

render "$here/feature.html" "" 1024 500 "$out/$play/featureGraphic.jpg"
written+=("$play/featureGraphic.jpg 1024 500")

# Each store rejects an image a pixel off its size, so check every output.
status=0
for entry in "${written[@]}"; do
  read -r file w h <<<"$entry"
  got_w="$(sips -g pixelWidth "$out/$file" | awk '/pixelWidth/ {print $2}')"
  got_h="$(sips -g pixelHeight "$out/$file" | awk '/pixelHeight/ {print $2}')"
  if [ "$got_w" != "$w" ] || [ "$got_h" != "$h" ]; then
    echo "compose: $file is ${got_w}x${got_h}, want ${w}x${h}" >&2
    status=1
  fi
done
[ "$status" -eq 0 ] || exit 1

# All good: a frame dropped from captions.tsv must not linger in the stores,
# so the old outputs go before the new ones move in.
mkdir -p "$play/phoneScreenshots" "$play/tenInchScreenshots" "$ios"
rm -f "$play"/phoneScreenshots/*.jpg "$play"/tenInchScreenshots/*.jpg \
  "$ios"/*_iphone61.jpg "$ios"/*_ipad13.jpg "$play/featureGraphic.jpg"
for entry in "${written[@]}"; do
  read -r file _ <<<"$entry"
  mv "$out/$file" "$file"
done
echo "compose: wrote ${#written[@]} images"
