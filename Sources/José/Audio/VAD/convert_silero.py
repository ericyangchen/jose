"""Convert Silero VAD to a Core ML model.

Usage:
    python3 convert_silero.py <silero_vad.{onnx,jit}> <output.mlmodel>

coremltools 8.x dropped direct ONNX conversion, so we prefer the
torchscript (.jit) path that Silero also publishes:

    https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.jit

Inputs:
    audio_chunk : float32 tensor [1, 512]   16kHz mono audio chunk
    state       : float32 tensor [2, 1, 128]  prior LSTM h+c (zero on first call)
    sr          : int64                       sample rate (16000)
Outputs:
    speech_prob : float32 tensor [1, 1]    speech probability
    next_state  : float32 tensor [2, 1, 128]  next LSTM state

If `.jit` fails (e.g. ScriptModule contains ops the converter doesn't
support), we fall back to RMS-pseudo-VAD at runtime — see
`SileroVAD.swift`.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np


def convert_jit(jit_path: Path, mlmodel_path: Path) -> None:
    import torch
    import coremltools as ct

    print(f"Loading torchscript from {jit_path}...")
    model = torch.jit.load(str(jit_path))
    model.eval()

    chunk_samples = 512
    example_audio = torch.zeros(1, chunk_samples, dtype=torch.float32)
    example_state = torch.zeros(2, 1, 128, dtype=torch.float32)
    example_sr = torch.tensor(16000, dtype=torch.int64)

    print("Tracing with example inputs...")
    with torch.no_grad():
        traced = torch.jit.trace(
            model, (example_audio, example_state, example_sr), strict=False
        )

    print("Running coremltools converter...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="audio_chunk", shape=(1, chunk_samples), dtype=np.float32),
            ct.TensorType(name="state", shape=(2, 1, 128), dtype=np.float32),
            ct.TensorType(name="sr", shape=(1,), dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="speech_prob"),
            ct.TensorType(name="next_state"),
        ],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.macOS14,
    )

    mlmodel.short_description = (
        "Silero VAD v5 — speech-activity detection. "
        "Inputs: 16 kHz audio chunk (512 samples), prior LSTM state, sample rate. "
        "Outputs: speech probability, next LSTM state."
    )
    mlmodel.author = "Silero Team — converted for José"
    mlmodel.license = "MIT"

    print(f"Saving {mlmodel_path}...")
    mlmodel.save(str(mlmodel_path))
    print("Done.")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    if not src.exists():
        print(f"error: {src} does not exist", file=sys.stderr)
        return 1
    dst.parent.mkdir(parents=True, exist_ok=True)

    if src.suffix.lower() != ".jit":
        print(f"error: only .jit (torchscript) input is supported by this script.", file=sys.stderr)
        print(f"hint:  curl -fL -o silero_vad.jit \\", file=sys.stderr)
        print(f"          https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.jit", file=sys.stderr)
        return 1

    try:
        convert_jit(src, dst)
    except Exception as exc:
        import traceback
        traceback.print_exc()
        print(f"error: conversion failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
