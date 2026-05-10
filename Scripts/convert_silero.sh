#!/usr/bin/env bash
# Convert the Silero VAD ONNX model to Core ML.
# Output: Sources/José/Audio/VAD/SileroVAD.mlmodel
set -euo pipefail

cd "$(dirname "$0")/.."

VAD_DIR="Sources/José/Audio/VAD"
WORK_DIR="$VAD_DIR/.work"
VENV_DIR="$VAD_DIR/.venv"
JIT_PATH="$WORK_DIR/silero_vad.jit"
MLMODEL_PATH="$VAD_DIR/SileroVAD.mlmodel"

mkdir -p "$WORK_DIR"

if [ ! -f "$JIT_PATH" ]; then
    echo "Downloading silero_vad.jit..."
    curl -fL -o "$JIT_PATH" \
        https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.jit
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python venv at $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

echo "Installing coremltools + torch..."
pip install --quiet --upgrade pip
pip install --quiet "coremltools>=8.3,<9" "torch>=2.0" "numpy<2.0" "ml_dtypes>=0.5.0"

echo "Converting torchscript → Core ML..."
python3 "$VAD_DIR/convert_silero.py" "$JIT_PATH" "$MLMODEL_PATH"

deactivate
echo
echo "Done. Wrote $MLMODEL_PATH"
