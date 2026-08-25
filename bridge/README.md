# TTS bridge

A small local stand-in for a real TTS backend, implementing the same HTTP contract the root [`agentic-voice`](../README.md) app speaks: `POST /v1/audio/synthesize` (multipart `language`/`text`/`voice`/`speed`) → WAV bytes.

It exists because a real NVIDIA TTS NIM needs a Linux box with an NVIDIA GPU (Compute Capability ≥8.0, 16GB+ VRAM) — hardware an Apple Silicon Mac doesn't have. Instead, this wraps [FluidAudio](https://github.com/FluidInference/FluidAudio)'s Kokoro-ANE backend, which runs entirely on-device via the Apple Neural Engine.

**Attribution**: the model is [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) by hexgrad — an open TTS model, not an NVIDIA product. FluidAudio (FluidInference) provides the CoreML/ANE conversion and runtime. The HTTP server itself is [Vapor](https://vapor.codes).

## Build / run

From the repo root:

```bash
npm run bridge:build
npm run bridge:start
```

Or directly:

```bash
swift build --package-path bridge
swift run --package-path bridge TTSBridge
```

First run downloads the model from HuggingFace (roughly a minute) and caches it outside this repo at `~/.cache/fluidaudio/Models/` — that cache is FluidAudio's own convention, not something this repo controls.

The server listens on `127.0.0.1:9000` and preloads one voice at startup (`am_michael`, set in `Sources/TTSBridge/main.swift`).

## Voice roster

Kokoro-82M ships 54 official voices, but this backend's English text frontend (Misaki lexicon + BART G2P) only pairs correctly with the ~20 US/UK English ones — prefixes `af_`/`am_` (US female/male) and `bf_`/`bm_` (UK female/male). The other prefixes (`zf_`/`zm_` Mandarin, `jf_`/`jm_` Japanese, etc.) are different languages and won't sound right read as English text.

Converted on this machine so far: `af_heart`, `af_bella`, `af_nicole`, `af_sarah`, `bf_emma`, `bm_george`, `am_adam`, `am_echo`, `am_eric`, `am_fenrir`, `am_liam`, `am_michael`, `am_onyx`, `am_puck`, `am_santa`.

**This list is this-machine-specific, not repo state.** The voice cache lives outside the repo (`~/.cache/fluidaudio/...`), so a fresh clone only has `am_michael` (the one preloaded at startup) — any other voice needs re-converting on that machine:

```bash
bridge/scripts/convert-voice.sh af_bella
```

The script needs no Python/torch: a Kokoro `.pt` voice file is an uncompressed zip, and the raw tensor bytes at `<voice>/data/0` are already byte-identical (little-endian float32, flat `[510,256]`) to what FluidAudio reads. The script downloads, unzips, validates the payload is exactly 522,240 bytes, and writes it to the cache path FluidAudio expects.

## Extending

`speed` (a positive float multiplier, default `1.0`) and `voice` are both accepted as multipart fields per the request contract in `Sources/TTSBridge/main.swift`. `language` is accepted but currently unused — the English variant has no runtime language switch.
