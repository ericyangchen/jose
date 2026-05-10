#!/usr/bin/env bash
# Build a release zip and create a GitHub release with it attached.
#
# Usage:
#     ./Scripts/publish.sh [tag]
#
# - With no argument: uses MARKETING_VERSION from project.yml as the tag (e.g. v0.1.0).
# - Refuses to overwrite existing tags — bump MARKETING_VERSION first.
# - Requires `gh` (GitHub CLI) authenticated to your account.
#
# This is the unsigned-build flow: zip the .app, attach to a GitHub release,
# users download → drag to /Applications → run xattr to bypass Gatekeeper.

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh (GitHub CLI) not found." >&2
    echo "       brew install gh && gh auth login" >&2
    exit 1
fi

VERSION=$(grep -A1 'MARKETING_VERSION' project.yml | head -1 | awk '{print $2}' | tr -d '"')
TAG="${1:-v$VERSION}"

# Refuse to clobber an existing tag — bump MARKETING_VERSION first.
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "error: release $TAG already exists. Bump MARKETING_VERSION in project.yml and try again." >&2
    exit 1
fi

echo "Building $TAG..."
./Scripts/release.sh

ZIP_PATH=".build/release/José-${VERSION}.zip"
SHA=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')

NOTES=$(cat <<EOF
## Install

1. Download \`José-${VERSION}.zip\` below.
2. Unzip and drag \`José.app\` into \`/Applications/\`.
3. Bypass Gatekeeper (one-time, unsigned build):

\`\`\`bash
xattr -d com.apple.quarantine /Applications/José.app
\`\`\`

4. Launch José from /Applications. The first-run window will ask for an [OpenAI API key](https://platform.openai.com/api-keys).

## Verify

\`\`\`
SHA-256: ${SHA}
\`\`\`

## What's new

_Edit me — \`gh release edit ${TAG}\` to update notes._
EOF
)

echo "Creating GitHub release $TAG..."
gh release create "$TAG" \
    "$ZIP_PATH" \
    --title "$TAG" \
    --notes "$NOTES"

echo
echo "Done. https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')/releases/tag/$TAG"
