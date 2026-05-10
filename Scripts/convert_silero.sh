#!/usr/bin/env bash
# Convert the Silero VAD ONNX model to Core ML.
# Output: Sources/José/Audio/VAD/SileroVAD.mlmodel
set -euo pipefail

cd "$(dirname "$0")/.."

VAD_DIR="Sources/José/Audio/VAD"
WORK_DIR="$VAD_DIR/.work"
VENV_DIR="$VAD_DIR/.venv"
JIT_PATH="$WORK_DIR/silero_vad.jit"
MLPACKAGE_PATH="$VAD_DIR/SileroVADModel.mlpackage"

mkdir -p "$WORK_DIR"

if [ ! -f "$JIT_PATH" ]; then
    echo "Downloading silero_vad.jit..."
    curl -fL -o "$JIT_PATH" \
        https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.jit
fi

# coremltools 8.x ships native libs for Python 3.10–3.12 only. 3.13 is
# missing libcoremlpython / libmilstoragepython at the time of writing,
# which makes mlmodel.save() blow up with "BlobWriter not loaded".
PY=python3.12
if ! command -v "$PY" >/dev/null 2>&1; then
    echo "error: python3.12 is required (coremltools 8.x has no native libs for 3.13 yet)." >&2
    echo "       brew install python@3.12" >&2
    exit 1
fi

# Sanity-check an existing venv is actually 3.12 — if we find one built with
# a different interpreter (likely a stale 3.13 from an earlier run), wipe it.
if [ -d "$VENV_DIR" ]; then
    venv_py=$("$VENV_DIR/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "broken")
    if [ "$venv_py" != "3.12" ]; then
        echo "Existing venv is python $venv_py — recreating with $PY..."
        rm -rf "$VENV_DIR"
    fi
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python 3.12 venv at $VENV_DIR..."
    "$PY" -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

echo "Installing coremltools + torch..."
pip install --quiet --upgrade pip
pip install --quiet "coremltools>=8.3,<9" "torch>=2.4,<2.6" "numpy<2.0"

echo "Converting torchscript → Core ML..."
python3 "$VAD_DIR/convert_silero.py" "$JIT_PATH" "$MLPACKAGE_PATH"

deactivate
echo
echo "Done. Wrote $MLPACKAGE_PATH"
