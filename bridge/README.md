# TTS bridge

A small local stand-in for a real TTS backend, implementing the same HTTP contract the root [`agentic-voice`](../README.md) app speaks: `POST /v1/audio/synthesize` (multipart `language`/`text`/`voice`/`speed`) → WAV bytes.

It exists because a real NVIDIA TTS NIM needs a Linux box with an NVIDIA GPU (Compute Capability ≥8.0, 16GB+ VRAM) — hardware an Apple Silicon Mac doesn't have. Instead, this wraps [FluidAudio](https://github.com/FluidInference/FluidAudio)'s Kokoro-ANE backend, which runs entirely on-device via the Apple Neural Engine.

**Attribution**: the model is [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) by hexgrad — an open TTS model, not an NVIDIA product. Cloned voices use [Pocket TTS](https://huggingface.co/kyutai/pocket-tts) by Kyutai (CC-BY-4.0). FluidAudio (FluidInference) provides the CoreML/ANE conversion and runtime. The HTTP server itself is [Vapor](https://vapor.codes).

## Build / run

Build/install is a prerequisite. Once built, the `agentic-voice` MCP server launches this executable automatically when no healthy local bridge exists, waits for the model to initialize, and stops only the bridge child it owns. Swift remains a separate process. Manual startup is still useful for standalone CLI/hooks and diagnosing first-use initialization:

From the repo root:

```bash
swift build -c release --package-path bridge --product TTSBridge
swift run -c release --package-path bridge TTSBridge
```

The package holds the whole project. `TTSBridgeCore` (HTTP routes, model preparation, voice installation and cloning, in `Sources/TTSBridgeCore/`) is run by the thin `TTSBridge` executable and by the Agentic Voice macOS app, so there is one implementation of each. `AgenticVoiceKit` (`Sources/AgenticVoiceKit/`) holds speaking, the bridge startup protocol and client installation; it reaches the bridge only over HTTP and is shared by the `agentic-voice` command (`Sources/AgenticVoiceCLI/`: MCP server, CLI, client installer) and the app. Tests: `swift test --package-path bridge`.

First run downloads the model from HuggingFace (roughly a minute) and caches it outside this repo at `~/.cache/fluidaudio/Models/` — that cache is FluidAudio's own convention, not something this repo controls.

Before loading, the bridge also installs the default voice if it is missing (FluidAudio's own repository hosts only `af_heart`). Later runs load cached assets; they do not reinstall or rebuild anything. HTTP starts only after `manager.initialize` completes. The documented `GET /v1/audio/health` endpoint returns HTTP 200 and JSON `{"status":"ready"}` once synthesis is available; `/` is only a welcome page. MCP waits up to five minutes; if first-use downloads take longer, complete initialization manually and restart MCP. MCP startup coordination reserves `127.0.0.1:19000` to prevent multiple bridge children from initializing concurrently.

The server listens on `127.0.0.1:9000` and preloads one voice at startup (`am_michael`, `VoiceCatalog.defaultVoice` in `Sources/TTSBridgeCore/VoiceCatalog.swift`). A request for a voice that isn't installed gets HTTP 400 naming the voice.

## Voice roster

Kokoro-82M ships 54 official voices, but this backend's English text frontend (Misaki lexicon + BART G2P) only pairs correctly with the ~20 US/UK English ones — prefixes `af_`/`am_` (US female/male) and `bf_`/`bm_` (UK female/male). The other prefixes (`zf_`/`zm_` Mandarin, `jf_`/`jm_` Japanese, etc.) are different languages and won't sound right read as English text.

`Sources/TTSBridgeCore/VoiceCatalog.swift` lists those 28 voices. Installed voices live in FluidAudio's cache outside the repo (`~/.cache/fluidaudio/Models/kokoro-82m-coreml/ANE/<voice>.bin`), so each machine installs its own. Install one from the Agentic Voice app's Settings, or:

```bash
bridge/.build/release/TTSBridge install-voice af_bella
```

No Python or torch is needed: a Kokoro `.pt` voice file is an uncompressed zip, and the raw tensor bytes at `<voice>/data/0` are already byte-identical (little-endian float32, flat `[510,256]`) to what FluidAudio reads. The installer downloads the official file from `hexgrad/Kokoro-82M`, extracts that entry with `/usr/bin/unzip`, checks it is exactly 522,240 bytes, and writes it atomically to the cache path.

## Voice cloning

Voices whose id starts with `clone_` are cloned from a recording and spoken by FluidAudio's PocketTTS backend instead of Kokoro. PocketTTS loads on the first request for a cloned voice, so a bridge that never speaks one never loads it. It has no speed control: cloned voices ignore `speed` and speak at their natural pace.

Clone from the Agentic Voice app's Settings (Voices → Clone a Voice…), or:

```bash
bridge/.build/release/TTSBridge clone-voice max sample.m4a   # prints clone_max
```

The sample can be any format AVFoundation reads, and must be at least 3 seconds long. Only its first 10 seconds are used, so record yourself speaking naturally in a quiet room for about that long. The name keeps only its ASCII letters and digits (`Max Müller` → `clone_maxmuller`). The first clone downloads the PocketTTS model (about 300 MB) into FluidAudio's cache. Cloned voices are stored in `~/Library/Application Support/AgenticVoice/Voices/<id>.bin`; the recording itself isn't kept. Delete a voice in Settings or by removing its file. Only clone your own voice, or a voice you have permission to use.

## Extending

`speed` (a positive float multiplier, default `1.0`, ignored for cloned voices) and `voice` are both accepted as multipart fields per the request contract in `Sources/TTSBridgeCore/BridgeServer.swift`. `language` is accepted but currently unused — the English variant has no runtime language switch.
