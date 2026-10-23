#!/usr/bin/env bash
# Renders the README images into docs/ (demo GIFs + history.png) from the real SwiftUI views,
# with made-up channels. Needs gifski for good-looking GIFs: brew install gifski
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="docs"
FPS=25
WIDTH="${WIDTH:-1200}"

swift build
.build/debug/Hashdrop --render-demo "$OUT"

if command -v gifski >/dev/null; then
  for dir in "$OUT"/*.frames; do
    gif="${dir%.frames}.gif"
    seq_dir="$(mktemp -d)"
    # gifski uses a constant frame rate, so repeat frames to honour each one's delay
    # (gifski folds identical consecutive frames back together).
    i=0
    while read -r name delay; do
      n=$(awk -v d="$delay" -v fps="$FPS" 'BEGIN { n = int(d * fps + 0.5); print (n < 1 ? 1 : n) }')
      for ((k = 0; k < n; k++)); do
        ln -s "$PWD/$dir/$name" "$seq_dir/$(printf %05d "$i").png"
        i=$((i + 1))
      done
    done < "$dir/frames.txt"
    gifski --quiet --fps "$FPS" --width "$WIDTH" --quality 90 -o "$gif" "$seq_dir"/*.png
    rm -rf "$seq_dir"
  done
else
  echo "gifski not found — keeping ImageIO's lower-quality GIFs (brew install gifski for better ones)." >&2
fi

rm -rf "$OUT"/*.frames
ls -lh "$OUT"
