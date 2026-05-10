#!/usr/bin/env bash
# Convert the Silero VAD ONNX model to Core ML.
# Output: Sources/José/Audio/VAD/SileroVAD.mlmodel
set -euo pipefail

cd "$(dirname "$0")/.."

VAD_DIR="Sources/José/Audio/VAD"
WORK_DIR="$VAD_DIR/.work"
VENV_DIR="$VAD_DIR/.venv"
ONNX_PATH="$WORK_DIR/silero_vad.onnx"
MLMODEL_PATH="$VAD_DIR/SileroVAD.mlmodel"

mkdir -p "$WORK_DIR"

if [ ! -f "$ONNX_PATH" ]; then
    echo "Downloading silero_vad.onnx..."
    curl -fL -o "$ONNX_PATH" \
        https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python venv at $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

echo "Installing coremltools + onnx..."
pip install --quiet --upgrade pip
pip install --quiet "coremltools>=7.2" "onnx>=1.16" "onnxruntime>=1.18" "numpy<2.0"

echo "Converting ONNX → Core ML..."
python3 "$VAD_DIR/convert_silero.py" "$ONNX_PATH" "$MLMODEL_PATH"

deactivate
echo
echo "Done. Wrote $MLMODEL_PATH"
