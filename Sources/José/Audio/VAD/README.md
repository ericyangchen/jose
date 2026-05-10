# Silero VAD — Core ML conversion notes

The Silero VAD v5 model ([snakers4/silero-vad](https://github.com/snakers4/silero-vad)) is shipped here as `SileroVADModel.mlpackage` so José can run on-device speech-activity detection without any extra runtime.

To regenerate the `.mlpackage` from the upstream torchscript:

```bash
./Scripts/convert_silero.sh
```

This downloads `silero_vad.jit`, sets up a Python 3.12 venv with `coremltools` + `torch`, runs `convert_silero.py`, and writes `SileroVADModel.mlpackage` next to this README.

> **Why Python 3.12?** coremltools 8.x ships native libs (`libcoremlpython`, `libmilstoragepython`) for Python 3.10–3.12 only. On 3.13 `mlmodel.save()` fails with `BlobWriter not loaded`. `brew install python@3.12` if needed.

## Why the script doesn't just convert the JIT directly

The Silero JIT trips two coremltools 8.x limitations:

1. **STFT layer** — its `Conv1d` strides come through the script graph as a string-indirected attribute, failing type validation:

   ```
   ValueError: Op "forward_transform.1" (op_type: conv) Input strides=...
   expects tensor or scalar of dtype from type domain ['int32']
   but got tensor[1,str]
   ```

2. **`nn.LSTMCell`** — its forward emits `aten::unsafe_chunk`, which has no converter in coremltools 8.x.

The conversion script sidesteps both by rebuilding the model in eager PyTorch with mathematically identical replacements (verified bit-for-bit against the JIT before tracing):

- **STFT** → `F.pad(audio, (0, 64), 'reflect')` + `F.conv1d(..., basis, stride=128)` using the JIT's `forward_basis_buffer`. Silero pads asymmetrically — 64 samples on the right only.
- **LSTMCell** → explicit matmul + 4-way `split` + sigmoid/tanh, weights loaded from the JIT.
- **Encoder + decoder-post Sequential** → unchanged (clean Conv1d / ReLU / Sigmoid all convert directly).

## Model contract

- **Inputs**: `audio` `(1, 576)` float32 — 64-sample context + 512 new samples; `h_in` and `c_in` `(1, 128)` float32 — prior LSTM state.
- **Outputs**: `speech_prob` `(1, 1)` — sigmoid speech probability; `h_out` and `c_out` `(1, 128)` — next LSTM state.

The Swift inference wrapper ([SileroVAD.swift](SileroVAD.swift)) is responsible for:

1. Buffering the upstream 30 ms / 480-sample audio chunks into 512-sample hops.
2. Maintaining the 64-sample audio context across hops (matches Silero's own `_context = x1[-context_size:]`).
3. Threading `(h, c)` LSTM state across inferences.
4. Smoothing the boolean speech flag over a small sliding window for the "no speech detected" gate.

If the `.mlmodelc` fails to load at runtime, `SileroVAD` falls back to a simple RMS-energy threshold so the app stays useful — you'll see a warning in the log.
