#!/bin/sh
# Compile the AppKit host into a headless executable and exercise the real
# binary cell-grid decoder, CoreText raster path, and retained raster cache.
set -eu

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/native-cell-grid-host.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

xcrun clang \
  -fobjc-arc \
  -fno-sanitize=builtin \
  -ObjC \
  -mmacosx-version-min=11.0 \
  -o "$tmp_dir/cell-grid-host-test" \
  "$repo_root/src/platform/macos/cell_grid_host_test.m" \
  -framework Foundation \
  -framework AppKit \
  -framework Metal \
  -framework QuartzCore \
  -framework CoreText \
  -framework CoreGraphics \
  -framework ImageIO \
  -framework AVFoundation \
  -framework UniformTypeIdentifiers \
  -framework WebKit \
  -framework Security \
  -framework ScreenCaptureKit \
  -framework CoreMedia \
  -framework CoreVideo \
  -framework IOKit \
  -framework Carbon \
  -framework Accelerate \
  -framework MediaToolbox

"$tmp_dir/cell-grid-host-test"
