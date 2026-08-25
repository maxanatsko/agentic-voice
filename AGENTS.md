# Agent Guidelines

## Purpose

This repository provides a minimal local voice-output capability for coding agents, speaking through a local TTS backend over a fixed HTTP contract. The bundled backend (`bridge/`) wraps Kokoro-82M via FluidAudio; it is not an NVIDIA product.

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

Do not let transport-specific objects leak into application code.

### KISS

Prefer direct code over patterns. A small function or class is better than a framework, registry, factory hierarchy, or dependency injection container when there is only one implementation.

### YAGNI

Do not add capabilities without a concrete requirement. In particular, avoid adding:

- provider abstraction layers before a second TTS provider exists;
- persistence, queues, retries, telemetry, or a web UI;
- an embedded summarization LLM, including inside a hook — hooks (`hooks/`) stay fixed-phrase and deterministic, never transcript-parsing;
- speech-to-text or full-duplex audio.

### DRY

Share behavior, not coincidental syntax. MCP and CLI must use the same `VoiceService`. There should be one implementation each for TTS synthesis, speech-length policy, configuration, and audio playback.

Do not create generic helpers solely to remove two or three similar lines.

## Code conventions

- TypeScript, ESM, strict mode.
- Prefer the Node.js standard library over dependencies.
- Validate external input at boundaries.
- Keep functions small and intention-revealing.
- Fail with actionable error messages; do not silently swallow synthesis or playback failures.
- Never write diagnostic output to stdout from the MCP process. stdout is reserved for MCP protocol traffic; use stderr for diagnostics.
- Tests should focus on deterministic application behavior. Do not mock implementation details merely to increase coverage.
- Swift code in `bridge/` is not built or tested by the root `tsc`/`node --test` pipeline — verify it with `swift build --package-path bridge` (see `bridge/README.md`).

## Change checklist

Before adding a new abstraction, dependency, or subsystem, answer:

1. What current requirement needs it?
2. Which existing module should own the behavior?
3. Can the change be implemented more simply without weakening the boundary?
4. Does it duplicate behavior that already exists?

If the requirement is hypothetical, do not add it.
