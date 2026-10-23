# Agent Guidelines

## Purpose

This repository provides a minimal local voice-output capability for coding agents, speaking through a local TTS backend over a fixed HTTP contract. The bundled backend (`bridge/`) wraps Kokoro-82M via FluidAudio; it is not an NVIDIA product. A macOS menu bar app (`bridge/Sources/AgenticVoice/`) hosts that backend and offers settings, voice downloads and client installation.

## Engineering principles

### Separation of concerns

Keep boundaries explicit:

- MCP code handles MCP concerns only.
- CLI code handles process input/output only.
- `VoiceService` owns the speak use case and user-facing speech policy.
- TTS backend HTTP details stay inside the TTS client (`src/tts/tts-client.ts`).
- Audio playback stays inside the audio module.
- Configuration parsing stays in `config.ts`.
- `bridge/` is a separate Swift package with its own toolchain; Node code must depend on it only through the documented HTTP contract, never by assuming its internals.
- In `bridge/`, `TTSBridgeCore` owns the HTTP routes, model preparation and voice installation; the `TTSBridge` executable and the app only run it.
- The macOS app is presentation only. It hosts `TTSBridgeCore`, writes the shared settings file, and runs `install-clients` for client config; it never parses config or edits client files itself.
- Client config editing stays in `src/clients/` (pure text edits in `config-edit.ts`, file handling in `clients.ts`).
- `~/Library/Application Support/AgenticVoice/config.json` is the only persisted setting. `config.ts` defines its format; the app reads and writes only `voice` and `speed`, applying the same rules. The app speaks (voice preview) only through the bundled CLI, never by calling the synthesis endpoint itself; its only HTTP request is the health check in the bridge startup protocol.

Do not let transport-specific objects leak into application code.

### KISS

Prefer direct code over patterns. A small function or class is better than a framework, registry, factory hierarchy, or dependency injection container when there is only one implementation.

### YAGNI

Do not add capabilities without a concrete requirement. In particular, avoid adding:

- provider abstraction layers before a second TTS provider exists;
- persistence beyond the shared settings file, queues, retries, telemetry, or a web UI (the native app is the only UI); a busy speaker is reported to the caller, never queued;
- an embedded summarization LLM, including inside a hook — hooks (`hooks/`) stay fixed-phrase and deterministic, never transcript-parsing;
- speech-to-text or full-duplex audio.

### DRY

Share behavior, not coincidental syntax. MCP and CLI must use the same `VoiceService`. There should be one implementation each for TTS synthesis, speech-length policy, configuration, and audio playback.

Do not create generic helpers solely to remove two or three similar lines.

## Code conventions

- TypeScript, ESM, strict mode, Node 26+.
- Prefer the Node.js standard library over dependencies.
- Validate external input at boundaries.
- Keep functions small and intention-revealing.
- Fail with actionable error messages; do not silently swallow synthesis or playback failures.
- Never write diagnostic output to stdout from the MCP process. stdout is reserved for MCP protocol traffic; use stderr for diagnostics.
- Tests should focus on deterministic application behavior. Do not mock implementation details merely to increase coverage.
- Swift code in `bridge/` is not built or tested by the root `tsc`/`node --test` pipeline — verify it with `swift build -c release --package-path bridge` and `npm run app:build` (see `bridge/README.md`).

## Change checklist

Before adding a new abstraction, dependency, or subsystem, answer:

1. What current requirement needs it?
2. Which existing module should own the behavior?
3. Can the change be implemented more simply without weakening the boundary?
4. Does it duplicate behavior that already exists?

If the requirement is hypothetical, do not add it.
