# Agentic Voice

Local voice output for coding agents, backed by NVIDIA Speech NIM.

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
   NVIDIA TTS client   Audio player
          |                 |
 POST /v1/audio/synthesize  afplay/aplay/custom command
```

Responsibilities are intentionally narrow:

- `src/server.ts` — MCP boundary only.
- `src/cli.ts` — command-line boundary only.
- `src/voice/voice-service.ts` — use-case orchestration and speech-length policy.
- `src/tts/nvidia-tts-client.ts` — NVIDIA HTTP API only.
- `src/audio/audio-player.ts` — local playback only.
- `src/config.ts` — environment configuration only.

See `AGENTS.md` for the design constraints used in this repository.

## Requirements

- Node.js 22+
- An NVIDIA TTS NIM endpoint. The default assumes `http://127.0.0.1:9000`.
- A local WAV player: `afplay` on macOS or `aplay` on Linux, unless overridden.

NVIDIA TTS NIM can run on a separate NVIDIA machine. For example, an agent running on macOS can call a TTS NIM hosted on a DGX Spark or Linux workstation by setting `NVIDIA_TTS_URL` to that host.

## Configure

```bash
cp .env.example .env
```

Environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `NVIDIA_TTS_URL` | `http://127.0.0.1:9000` | Base URL of NVIDIA TTS NIM |
| `NVIDIA_TTS_VOICE` | `Magpie-Multilingual.EN-US.Aria` | NVIDIA voice id |
| `NVIDIA_TTS_LANGUAGE` | `en-US` | Locale sent to TTS |
| `VOICE_MAX_CHARS` | `360` | Hard limit for spoken text |
| `VOICE_PLAYBACK_COMMAND` | auto | Optional playback executable |

## Install and run

```bash
npm install
npm run build
npm test
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

For deterministic completion notifications, invoke the CLI from an agent's completion/stop hook. The hook should pass a short summary, not the entire transcript.

The repository deliberately does not implement host-specific hook adapters yet. Add one only when there is a concrete target host and its hook payload is known.

## NVIDIA endpoint

This MVP uses NVIDIA Speech NIM's HTTP synthesis endpoint:

```text
POST {NVIDIA_TTS_URL}/v1/audio/synthesize
```

The request is multipart form data containing `language`, `text`, and `voice`; the response is written as WAV audio and played locally.

## Design principles

- **SoC:** protocol, TTS, playback, configuration, and orchestration live in separate modules.
- **KISS:** one tool, one provider, one playback path.
- **YAGNI:** no provider interfaces, DI container, queues, database, UI, or embedded summarizer until a real requirement exists.
- **DRY:** MCP and CLI call the same `VoiceService`; synthesis and playback logic exist once.
