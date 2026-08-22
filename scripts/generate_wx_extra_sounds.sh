#!/bin/bash
# Generate optional weather announcement sounds with asl-tts (ASL3).
#
# Run on a node with asl3-tts installed (e.g. crazytrain). Requires root or
# passwordless sudo for: sudo -u asterisk asl-tts ...
#
# Usage:
#   ASL_NODE=546050 ./scripts/generate_wx_extra_sounds.sh [DEST_DIR]
#
# DEST_DIR defaults to /usr/share/asterisk/sounds/en/wx
# Output files are *.ulaw (renamed from asl-tts *.ul).
#
# To copy into this repo after generating on crazytrain:
#   scp 'crazytrain:/usr/share/asterisk/sounds/en/wx/{feels-like,dewpoint,...}.ulaw' sounds/

set -euo pipefail

NODE="${ASL_NODE:-546050}"
DEST="${1:-/usr/share/asterisk/sounds/en/wx}"
TMP="$(sudo -u asterisk mktemp -d /tmp/wx-extra-sounds.XXXXXX)"
trap 'sudo rm -rf "$TMP"' EXIT

if ! command -v asl-tts >/dev/null 2>&1; then
  echo "asl-tts not found (install asl3-tts)" >&2
  exit 1
fi

mkdir -p "$DEST"

generate() {
  local base="$1"
  local text="$2"
  echo "  $base.ulaw  <-  \"$text\""
  if ! sudo -u asterisk asl-tts -n "$NODE" -t "$text" -f "$TMP/$base" >/dev/null 2>&1; then
    echo "asl-tts failed for: $base" >&2
    exit 1
  fi
  if [[ ! -f "$TMP/$base.ul" ]]; then
    echo "missing output: $TMP/$base.ul" >&2
    exit 1
  fi
  sudo install -m 644 -o asterisk -g asterisk "$TMP/$base.ul" "$DEST/$base.ulaw"
}

echo "Generating optional wx sounds (node $NODE) -> $DEST"
echo

echo "Field labels:"
generate feels-like      "feels like"
generate dewpoint        "dewpoint"
generate humidity        "humidity"
generate percent         "percent"
generate wind            "wind"
generate gust            "gust"
generate pressure        "pressure"
generate precipitation   "precipitation"
generate uv-index        "U V index"
generate visibility      "visibility"
generate point           "point"
generate trace           "trace"

echo
echo "Units (Fahrenheit / US mode):"
generate miles-per-hour    "miles per hour"
generate inches-of-mercury "inches of mercury"
generate inches          "inches"
generate miles           "miles"

echo
echo "Units (Celsius / metric mode):"
generate kilometers-per-hour "kilometers per hour"
generate hectopascals        "hectopascals"
generate millimeters         "millimeters"
generate kilometers          "kilometers"

echo
echo "Wind directions (16-point):"
generate north               "north"
generate north-northeast     "north northeast"
generate northeast           "northeast"
generate east-northeast      "east northeast"
generate east                "east"
generate east-southeast      "east southeast"
generate southeast           "southeast"
generate south-southeast     "south southeast"
generate south               "south"
generate south-southwest     "south southwest"
generate southwest           "southwest"
generate west-southwest      "west southwest"
generate west                "west"
generate west-northwest      "west northwest"
generate northwest           "northwest"
generate north-northwest     "north northwest"

echo
echo "Done. $(find "$DEST" -maxdepth 1 -name '*.ulaw' | wc -l) files in $DEST"
