# Silero VAD — Core ML conversion notes

The Silero VAD model ([snakers4/silero-vad](https://github.com/snakers4/silero-vad)) is shipped here as a `.mlmodel` so José can run on-device speech-activity detection without any extra runtime.

To regenerate the `.mlmodel` from the upstream ONNX:

```bash
./Scripts/convert_silero.sh
```

This downloads `silero_vad.onnx`, sets up a venv with `coremltools` + `onnx`, runs `convert_silero.py`, and writes `SileroVAD.mlmodel` next to this README.

## Model contract

- **Input chunk size**: 512 samples at 16 kHz (Silero v5 default — ~32 ms)
- **LSTM state**: shape `(2, 1, 128)`, float32; thread output back into next call's input
- **Output**: speech probability scalar; threshold `> 0.5` for speech

The Swift inference wrapper (`SileroVAD.swift`) is responsible for:

1. Buffering the upstream 30 ms / 480-sample audio chunks into 512-sample windows
2. Maintaining the LSTM state between inferences
3. Smoothing the boolean speech flag over a small sliding window

If `SileroVAD.mlmodel` is missing at runtime, `SileroVAD` falls back to a simple RMS-energy threshold so the build never breaks — you'll see a warning in the log.
