# Agent Guidelines

## Purpose

This repository provides a minimal local voice-output capability for coding agents, speaking through a local TTS backend over a fixed HTTP contract. Everything is one Swift package in `bridge/`: the `agentic-voice` command (MCP server, CLI, client installer), the bundled backend `TTSBridge`, which wraps Kokoro-82M via FluidAudio (not an NVIDIA product) and speaks cloned (`clone_`) voices with FluidAudio's PocketTTS, and a macOS menu bar app (`bridge/Sources/AgenticVoice/`) that hosts that backend and offers settings, voice downloads and client installation. The only non-Swift code is the hook script (`hooks/`) and the opencode plugin shim (`opencode/`, plus the dependency-free `package.json` opencode needs to install it).

## Engineering principles

### Separation of concerns

Keep boundaries explicit:

- MCP code handles MCP concerns only.
- CLI code handles process input/output only.
- `VoiceService` owns the speak use case and user-facing speech policy.
- TTS backend HTTP details stay inside the TTS client (`AgenticVoiceKit/TTSClient.swift`).
- Audio playback stays inside `AudioPlayer`.
- Configuration parsing stays in `Config.swift`.
- `TTSBridgeCore` owns the HTTP routes, model preparation, voice installation (`VoiceStore`) and voice cloning (`ClonedVoiceStore`); the `TTSBridge` executable and the app only run it. Kokoro and PocketTTS are chosen by voice id in the synthesis route, with no provider abstraction.
- `AgenticVoiceKit` depends on the bridge only through the documented HTTP contract, never by importing `TTSBridgeCore` (keep Vapor and FluidAudio out of it). The `agentic-voice` command (`AgenticVoiceCLI`) and the app share it.
- The macOS app is presentation only. It hosts `TTSBridgeCore`, writes the shared settings file, and calls `AgenticVoiceKit` for client installation and voice previews; it never edits client files or calls the TTS backend itself.
- Client config editing stays in `AgenticVoiceKit/Clients/` (pure text edits in `ConfigEdit.swift`, file handling in `Clients.swift`).
- `~/Library/Application Support/AgenticVoice/config.json` is the only persisted setting that speech reads. The app's own display preferences (the speaking overlay's toggles, style and dragged positions) live in its `UserDefaults`, since only the app uses them; the command always announces speech and the app decides whether to show it. Cloned voices (`AgenticVoice/Voices/`) are voice data, like installed Kokoro voices, not settings. `Config.swift` defines its format; the app reads and writes only `voice` and `speed`, applying the same rules. The app speaks (voice preview) only through `VoiceService`, never by calling the synthesis endpoint itself; its only direct HTTP request is the health check in the bridge startup protocol.

Do not let transport-specific objects leak into application code.

### KISS

Prefer direct code over patterns. A small function or class is better than a framework, registry, factory hierarchy, or dependency injection container when there is only one implementation.

### YAGNI

Do not add capabilities without a concrete requirement. In particular, avoid adding:

- provider abstraction layers before a second TTS provider exists;
- persistence beyond the shared settings file and the app's display preferences, queues, retries, telemetry, or a web UI (the native app is the only UI); a busy speaker is reported to the caller, never queued;
- an embedded summarization LLM, including inside a hook — hooks (`hooks/`) stay fixed-phrase and deterministic, never transcript-parsing;
- speech-to-text or full-duplex audio.

### DRY

Share behavior, not coincidental syntax. MCP and CLI must use the same `VoiceService`. There should be one implementation each for TTS synthesis, speech-length policy, configuration, and audio playback.

Do not create generic helpers solely to remove two or three similar lines.

## Code conventions

- Swift 6 language mode, macOS 26+.
- Prefer Foundation and the standard library over dependencies.
- Validate external input at boundaries.
- Keep functions small and intention-revealing.
- Fail with actionable error messages; do not silently swallow synthesis or playback failures.
- Never write diagnostic output to stdout from the MCP process. stdout is reserved for MCP protocol traffic; use stderr for diagnostics.
- Tests should focus on deterministic application behavior. Do not mock implementation details merely to increase coverage.
- Verify with `swift build -c release --package-path bridge`, `swift test --package-path bridge` and, for app changes, `scripts/build-app.sh` (see `bridge/README.md`).

## Change checklist

Before adding a new abstraction, dependency, or subsystem, answer:

1. What current requirement needs it?
2. Which existing module should own the behavior?
3. Can the change be implemented more simply without weakening the boundary?
4. Does it duplicate behavior that already exists?

If the requirement is hypothetical, do not add it.
