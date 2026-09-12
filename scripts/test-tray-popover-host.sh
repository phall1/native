#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
sdk="$(env -u SDKROOT /usr/bin/xcrun --sdk macosx --show-sdk-path)"
mkdir -p .zig-cache/tray-popover-host
SDKROOT="$sdk" /usr/bin/xcrun clang -fobjc-arc -fno-sanitize=builtin -mmacosx-version-min=11.0 \
  -Wno-deprecated-declarations -Wno-unguarded-availability-new \
  src/platform/macos/tray_popover_test.m -o .zig-cache/tray-popover-host/test \
  -framework AppKit -framework WebKit -framework AVFoundation -framework CoreMedia \
  -framework ScreenCaptureKit -framework CoreVideo -framework MediaToolbox \
  -framework Accelerate -framework Foundation -framework CoreText \
  -framework UniformTypeIdentifiers -framework Security -framework Metal \
  -framework QuartzCore -framework ImageIO -framework CoreGraphics
.zig-cache/tray-popover-host/test
