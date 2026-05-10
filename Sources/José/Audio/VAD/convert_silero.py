"""Convert silero_vad.onnx to a Core ML model.

Usage:
    python3 convert_silero.py <silero_vad.onnx> <output.mlmodel>

The Silero VAD ONNX exposes:
    inputs:
        input  : float32 tensor [batch=1, samples=N]   audio waveform
        state  : float32 tensor [2, batch=1, 128]      previous LSTM h+c
        sr     : int64                                  sample rate (16000)
    outputs:
        output : float32 tensor [batch=1, 1]           speech probability
        stateN : float32 tensor [2, batch=1, 128]      next LSTM h+c

We expose them as fixed-shape inputs/outputs so the Swift inference loop can
thread the LSTM state across calls without dynamic-shape gymnastics.

Tested with coremltools 8.x. If the converter emits warnings about ONNX op
versions, that's expected — Silero uses a small enough op set that the
default conversion pipeline handles it.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np


def convert(onnx_path: Path, mlmodel_path: Path) -> None:
    import coremltools as ct
    import onnx

    print(f"Loading ONNX from {onnx_path}...")
    onnx_model = onnx.load(str(onnx_path))
    onnx.checker.check_model(onnx_model)

    # The model expects an audio chunk of 512 samples at 16kHz (Silero v5 default).
    # We fix the shape so Core ML can compile to a static graph.
    chunk_samples = 512

    # coremltools >= 7 supports ONNX via the unified converter (`ct.convert`)
    # using the ONNX frontend. Shape inference is needed for the LSTM state.
    inputs = [
        ct.TensorType(name="input", shape=(1, chunk_samples), dtype=np.float32),
        ct.TensorType(name="state", shape=(2, 1, 128), dtype=np.float32),
        ct.TensorType(name="sr", shape=(1,), dtype=np.int64),
    ]

    print("Running coremltools converter...")
    mlmodel = ct.convert(
        onnx_model,
        inputs=inputs,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS14,
    )

    mlmodel.short_description = (
        "Silero VAD v5 — speech-activity detection. "
        "Inputs: 16 kHz audio chunk (512 samples), prior LSTM state, sample rate. "
        "Outputs: speech probability, next LSTM state."
    )
    mlmodel.author = "Silero Team — converted for José by Eric Chen"
    mlmodel.license = "MIT"

    print(f"Saving {mlmodel_path}...")
    mlmodel.save(str(mlmodel_path))
    print("Done.")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    onnx_path = Path(sys.argv[1])
    mlmodel_path = Path(sys.argv[2])
    if not onnx_path.exists():
        print(f"error: {onnx_path} does not exist", file=sys.stderr)
        return 1
    mlmodel_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        convert(onnx_path, mlmodel_path)
    except Exception as exc:
        print(f"error: conversion failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
