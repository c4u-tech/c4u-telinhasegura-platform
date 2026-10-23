#!/usr/bin/env bash
# Composes the store images from the raw captures of the app: each frame is
# frame.html (a caption over the real screen) rendered by headless Chrome at
# the exact store size, then saved as JPEG; the Play feature graphic is
# feature.html at 1024x500. Run from the repository root, after
# `make store-screens-raw` has written app/build/store_screens/raw.
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

# profile, store width, store height, output path with NN in place of the frame.
profiles=(
  "android_phone 1080 1920 $play/phoneScreenshots/NN.jpg"
  "android_tablet10 1600 2560 $play/tenInchScreenshots/NN.jpg"
  "iphone61 1179 2556 $ios/NN_iphone61.jpg"
  "ipad13 2064 2752 $ios/NN_ipad13.jpg"
)

# A frame dropped from captions.tsv must not linger in the stores, so the
# old outputs go before the new ones are written.
mkdir -p "$play/phoneScreenshots" "$play/tenInchScreenshots" "$ios"
rm -f "$play"/phoneScreenshots/*.jpg "$play"/tenInchScreenshots/*.jpg \
  "$ios"/*_iphone61.jpg "$ios"/*_ipad13.jpg "$play/featureGraphic.jpg"

urlencode() {
  python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1"
}

# render <page url> <width> <height> <dest jpg>
render() {
  local url="$1" w="$2" h="$3" dest="$4" png="$tmp/shot.png"
  rm -rf "$png" "$tmp/profile"
  # A fresh throwaway profile per render keeps it apart from any Chrome
  # already open and from the window size a previous render left behind;
  # the virtual time budget lets the font and the capture load before the shot.
  # Chrome may exit non-zero on teardown after writing the shot, so success
  # is the file it wrote, checked below.
  "$chrome" --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --user-data-dir="$tmp/profile" \
    --virtual-time-budget=5000 --allow-file-access-from-files \
    --window-size="$w,$h" --screenshot="$png" "$url" >/dev/null 2>&1 || true
  [ -s "$png" ] || { echo "compose: Chrome wrote no screenshot for $dest" >&2; exit 1; }
  sips -s format jpeg -s formatOptions 92 "$png" --out "$dest" >/dev/null
}

written=()
while IFS=$'\t' read -r nn caption; do
  [ -n "$nn" ] || continue
  enc="$(urlencode "$caption")"
  for p in "${profiles[@]}"; do
    read -r profile w h pattern <<<"$p"
    src="$raw/$profile/$nn.png"
    [ -f "$src" ] || { echo "compose: missing raw capture $src" >&2; exit 1; }
    dest="${pattern/NN/$nn}"
    render "file://$PWD/$here/frame.html?w=$w&h=$h&caption=$enc&shot=$(urlencode "file://$PWD/$src")" \
      "$w" "$h" "$dest"
    written+=("$dest $w $h")
  done
done <"$here/captions.tsv"

render "file://$PWD/$here/feature.html" 1024 500 "$play/featureGraphic.jpg"
written+=("$play/featureGraphic.jpg 1024 500")

# Each store rejects an image a pixel off its size, so check every output.
status=0
for entry in "${written[@]}"; do
  read -r file w h <<<"$entry"
  got_w="$(sips -g pixelWidth "$file" | awk '/pixelWidth/ {print $2}')"
  got_h="$(sips -g pixelHeight "$file" | awk '/pixelHeight/ {print $2}')"
  if [ "$got_w" != "$w" ] || [ "$got_h" != "$h" ]; then
    echo "compose: $file is ${got_w}x${got_h}, want ${w}x${h}" >&2
    status=1
  fi
done
[ "$status" -eq 0 ] || exit 1
echo "compose: wrote ${#written[@]} images"
