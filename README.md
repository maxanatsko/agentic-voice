# Agentic Voice

Local voice output for coding agents, backed by a local TTS bridge. The default backend ([`bridge/`](bridge/README.md)) runs Kokoro-82M — an open TTS model by [hexgrad](https://huggingface.co/hexgrad/Kokoro-82M), unrelated to NVIDIA — via [FluidAudio](https://github.com/FluidInference/FluidAudio)'s Apple Neural Engine runtime, entirely on-device.

The MVP exposes a single MCP tool, `speak`, and a small CLI. Both paths share the same application service, so agent-triggered speech and deterministic lifecycle hooks do not duplicate TTS or playback logic.

## Goals

- Let an agent speak short questions, blockers, and completion summaries.
- Keep detailed output in the normal text UI; voice is a concise attention layer.
- Run TTS locally or on another machine reachable over HTTP.
- Keep the implementation small enough to understand and modify without framework overhead.

## Non-goals

- Speech-to-text or full duplex conversation.
- An embedded LLM summarizer. The calling agent should summarize before invoking `speak`.
- Voice cloning, queues, persistence, web UI, telemetry, or multi-provider abstraction in the MVP.

## Architecture

```text
Agent / lifecycle hook
        |
        +-- MCP speak tool
        |        |
        +-- CLI -+
                 |
            VoiceService
           /            \
     TTS client        Audio player
          |                 |
 POST /v1/audio/synthesize  afplay/aplay/custom command
```

The HTTP endpoint above is served locally by the bundled [`bridge/`](bridge/README.md) by default; any HTTP service implementing the same contract (see "TTS HTTP contract" below) works.

Responsibilities are intentionally narrow:

- `src/server.ts` — MCP boundary only.
- `src/cli.ts` — command-line boundary only.
- `src/voice/voice-service.ts` — use-case orchestration and speech-length policy.
- `src/tts/tts-client.ts` — TTS HTTP client only.
- `src/audio/audio-player.ts` — local playback only.
- `src/config.ts` — environment configuration only.

See `AGENTS.md` for the design constraints used in this repository.

## Requirements

- Node.js 22+
- A running TTS backend at an HTTP endpoint. The default assumes `http://127.0.0.1:9000`, served by the bundled `bridge/`.
- To build/run the bundled bridge: Xcode 15+ / Swift 5.9+ (macOS, Apple Silicon).
- A local WAV player: `afplay` on macOS or `aplay` on Linux, unless overridden.

The TTS backend can run on a separate machine reachable over HTTP — set `TTS_URL` to that host.

## Configure

```bash
cp .env.example .env
```

Environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `TTS_URL` | `http://127.0.0.1:9000` | Base URL of the TTS backend |
| `TTS_VOICE` | `am_michael` | Voice id — see [`bridge/README.md`](bridge/README.md) for the full roster |
| `TTS_LANGUAGE` | `en-US` | Locale sent to TTS |
| `VOICE_SPEED` | `1.0` | Playback speed multiplier sent to TTS |
| `VOICE_MAX_CHARS` | `360` | Hard limit for spoken text |
| `VOICE_PLAYBACK_COMMAND` | auto | Optional playback executable |

## Install and run

```bash
npm run setup   # npm install + build the Node app + build the Swift bridge
npm test
```

Start the bridge (its own terminal/process — it's long-lived):

```bash
npm run bridge:start
```

Run the MCP server over stdio:

```bash
npm start
```

Try the CLI:

```bash
npm run speak -- "Review complete. Two blocking issues need your attention."
```

Or pipe text from a hook:

```bash
printf '%s' "The task finished successfully." | npm run speak
```

## TTS bridge (`bridge/`)

The bundled backend is a small Swift package (Vapor HTTP server + FluidAudio's Kokoro-ANE CoreML runtime) that implements the exact HTTP contract this repo's client speaks — see [`bridge/README.md`](bridge/README.md) for voice roster, the voice-conversion script, and model cache details.

Build/run it via the root npm scripts:

```bash
npm run bridge:build
npm run bridge:start
```

## MCP tool

The server exposes one tool:

```text
speak({ text, kind? })
```

`kind` is optional metadata: `question`, `completion`, `alert`, or `custom`. It currently does not change synthesis behavior; keeping it in the contract leaves room for small policy changes without creating separate tools.

Recommended agent instruction:

```text
Use the speak tool only when you need a user decision, hit a blocker that needs attention,
or finish a meaningful task. Summarize for listening; do not read code, paths, logs, or long
technical output aloud. Keep the spoken message to one or two short sentences.
```

## Lifecycle hooks

The `speak` MCP tool above already covers rich, context-aware notifications — the agent decides when to call it and summarizes for itself. The hooks in [`hooks/`](hooks/hooks.json) are a different, deterministic thing: a fixed-phrase backstop for the two moments an LLM isn't available to summarize anything — the turn just ended, or the tool is blocked waiting on you. They intentionally do **not** parse a transcript or try to be clever; that would duplicate what `speak` already does properly, and a shell hook has no LLM in the loop to summarize with.

Two events, two fixed phrases, one shared script (`hooks/speak-notify.sh`):

| Event | Phrase |
| --- | --- |
| Turn/task finished (Claude Code `Stop`, Codex CLI `Stop`) | "Task finished." |
| Waiting on you (Claude Code `Notification`, Codex CLI `PermissionRequest`) | "Needs your input." |

Both tools use the same JSON hook schema, so `hooks/hooks.json` works for either unchanged — each engine reads the keys it recognizes and ignores the rest.

**Install (nothing here happens automatically — copy/merge by hand):**

- **Claude Code**: merge the `hooks` object from `hooks/hooks.json` into `~/.claude/settings.json` (global — fires in every project) or `<project>/.claude/settings.json` (that project only). This must be a deep-merge alongside any existing keys in that file, never a wholesale replace.
- **Codex CLI**: copy the file into each project where you want it — `cp hooks/hooks.json /path/to/project/.codex/hooks.json` (Codex CLI hooks are per-project; there's no global equivalent).

Both files hardcode this repo's absolute path in the `command` field — adjust it if your clone lives elsewhere.

**Prerequisites**: `npm run build` (so `dist/src/cli.js` exists) and the bridge running (`npm run bridge:start`).

## TTS HTTP contract

The bridge (and any compatible backend) exposes this HTTP synthesis endpoint:

```text
POST {TTS_URL}/v1/audio/synthesize
```

The request is multipart form data containing `language`, `text`, `voice`, and `speed`; the response is written as WAV audio and played locally.

## Design principles

- **SoC:** protocol, TTS, playback, configuration, and orchestration live in separate modules.
- **KISS:** one tool, one provider, one playback path.
- **YAGNI:** no provider interfaces, DI container, queues, database, UI, or embedded summarizer until a real requirement exists.
- **DRY:** MCP and CLI call the same `VoiceService`; synthesis and playback logic exist once.
