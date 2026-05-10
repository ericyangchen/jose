#!/usr/bin/env bash
# One-time setup: install xcodegen and generate the Xcode project.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "error: Homebrew is required. Install from https://brew.sh first." >&2
        exit 1
    fi
    echo "Installing xcodegen via Homebrew..."
    brew install xcodegen
fi

if [ ! -f "Sources/José/Audio/VAD/SileroVAD.mlmodel" ]; then
    echo "warning: SileroVAD.mlmodel is missing. Run Scripts/convert_silero.sh to generate it."
fi

echo "Generating José.xcodeproj..."
xcodegen generate

echo "Done. Open José.xcodeproj in Xcode."
