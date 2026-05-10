import Foundation

// Worker B2 (feat/audio) owns this file — Core ML inference loop with LSTM
// state carryover (spec §6.3.2). Falls back to RMS-pseudo-VAD if the
// .mlmodelc fails to load.
