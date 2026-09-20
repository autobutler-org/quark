#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${1:-${PERF_FIXTURE_TARGET_DIR:-}}"
FIXTURE_ROOT_NAME="${PERF_FIXTURE_ROOT_NAME:-perf}"
PHOTO_COUNT="${PERF_FIXTURE_PHOTO_COUNT:-120}"
TEXT_COUNT="${PERF_FIXTURE_TEXT_COUNT:-250}"
RANDOM_FILE_COUNT="${PERF_FIXTURE_RANDOM_FILE_COUNT:-24}"
RANDOM_FILE_SIZE_KB="${PERF_FIXTURE_RANDOM_FILE_SIZE_KB:-16}"

if [[ -z "$TARGET_DIR" ]]; then
  echo "missing target dir: pass PERF_FIXTURE_TARGET_DIR or the path as arg 1" >&2
  exit 1
fi

perf_dir="$TARGET_DIR/$FIXTURE_ROOT_NAME"
nested_dir="$perf_dir/nested"
mkdir -p "$nested_dir"

# Small deterministic JPEG fixture (8x8, encoded by Go's image/jpeg) reused
# across photo-oriented scenarios. It has to decode, or thumbnails return 500.
jpeg_base64="/9j/2wCEABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2MBERISGBUYLxoaL2NCOEJjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY//AABEIAAgACAMBIgACEQEDEQH/xAGiAAABBQEBAQEBAQAAAAAAAAAAAQIDBAUGBwgJCgsQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+gEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoLEQACAQIEBAMEBwUEBAABAncAAQIDEQQFITEGEkFRB2FxEyIygQgUQpGhscEJIzNS8BVictEKFiQ04SXxFxgZGiYnKCkqNTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqCg4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2dri4+Tl5ufo6ery8/T19vf4+fr/2gAMAwEAAhEDEQA/AINP0Lp8laP9h/7FaGn9q0a5quKqc25WAxlX2K1P/9k="
decode_flag="-d"
if base64 --help 2>/dev/null | grep -q -- '--decode'; then
  decode_flag="--decode"
fi

printf "%s" "$jpeg_base64" | base64 "$decode_flag" > "$perf_dir/sample-1.jpg"
cp "$perf_dir/sample-1.jpg" "$perf_dir/sample-2.jpg"
cp "$perf_dir/sample-1.jpg" "$nested_dir/sample-3.jpg"

for i in $(seq 1 "$PHOTO_COUNT"); do
  printf -v root_photo "%s/photo-%04d.jpg" "$perf_dir" "$i"
  printf -v nested_photo "%s/photo-%04d.jpg" "$nested_dir" "$i"
  cp "$perf_dir/sample-1.jpg" "$root_photo"
  cp "$perf_dir/sample-1.jpg" "$nested_photo"
done

for i in $(seq 1 "$TEXT_COUNT"); do
  printf "fixture-%04d\n" "$i" > "$nested_dir/file-$i.txt"
done

for i in $(seq 1 "$RANDOM_FILE_COUNT"); do
  dd if=/dev/urandom of="$perf_dir/blob-$i.bin" bs=1024 count="$RANDOM_FILE_SIZE_KB" status=none
done
