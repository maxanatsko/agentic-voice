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

- `src/server.ts` — MCP boundary and startup/shutdown wiring.
- `src/cli.ts` — command-line boundary only.
- `src/voice/voice-service.ts` — use-case orchestration and speech-length policy.
- `src/tts/tts-client.ts` — TTS HTTP client only.
- `src/tts/bridge-process.ts` — readiness and ownership of the separate bridge process.
- `src/audio/audio-player.ts` — local playback only.
- `src/config.ts` — environment configuration only.

## Requirements

- Node.js 22+
- A built bundled bridge, or an externally managed TTS backend. MCP automatically starts the bundled bridge at `http://127.0.0.1:9000` when needed.
- To build/run the bundled bridge: Xcode 15+ / Swift 5.9+ (macOS, Apple Silicon).
- A local WAV player: `afplay` on macOS or `aplay` on Linux, unless overridden.

The TTS backend can run on a separate machine reachable over HTTP — set `TTS_URL` to that host.

## Configure

```bash
cp .env.example .env
```

Create `.env` in the plugin/repository root. MCP and CLI resolve it from their installed module location, independently of the calling project's working directory. Existing environment variables take precedence over `.env`.

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

Run the MCP server over stdio:

```bash
npm start
```

MCP reuses a healthy bundled bridge or launches the already-built `bridge/.build/debug/TTSBridge` as a separate process. No separate terminal is needed. Startup never installs dependencies or compiles code. The bridge's first model initialization can download missing FluidAudio assets; later starts reuse its cache. MCP initialization and tool listing remain available during initialization, and `speak` waits for readiness (up to five minutes). If the bridge fails to become ready, MCP stays connected and each `speak` call returns the startup error; restart MCP after fixing the cause. Bridge output and actionable startup failures go to stderr; stdout contains only MCP protocol messages.

Automatic bridge management applies only to HTTP loopback URLs (`127.0.0.1`, `localhost`, or `::1`) on port 9000 without a base path, query, credentials, or fragment. These aliases use the bundled bridge's IPv4 listener. Remote URLs and other custom endpoints are externally managed: MCP connects through the existing synthesis contract and never starts a local bridge for them.

When MCP closes or receives SIGINT/SIGTERM, it stops only the child it started. Reused bridges survive that MCP instance's shutdown. With multiple instances, a borrowed bridge can disappear when its owner exits; restart the borrowing MCP instance if needed. There is no ownership transfer.

MCP instances coordinate startup by exclusively binding `127.0.0.1:19000` before spawning the bridge. This reserved coordination port prevents concurrent model downloads/loading while port 9000 is still closed. The owner holds it until its child exits; other instances wait for readiness and reuse the bridge. The OS releases the coordination socket if its owner exits, with no persistent lock files. Keep port 19000 available; an unrelated listener there causes startup to time out with diagnostics.

If the executable is missing, run `npm run setup` explicitly. If startup times out or model initialization fails, run `npm run bridge:start` to inspect diagnostics and finish first-use initialization, then restart MCP. If another service occupies port 9000, free the port or configure `TTS_URL` for your backend.

The CLI and lifecycle hooks do not start the bridge. To try the CLI without an active MCP server, start a backend explicitly:

```bash
npm run bridge:start
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

The `speak` MCP tool above already covers rich, context-aware notifications — the agent decides when to call it and summarizes for itself. The hooks below are a different, deterministic thing: a fixed-phrase backstop for the two moments an LLM isn't available to summarize anything — the turn just ended, or the tool is blocked waiting on you. They intentionally do **not** parse a transcript or try to be clever; that would duplicate what `speak` already does properly, and a shell hook has no LLM in the loop to summarize with.

Two events, two fixed phrase templates, one shared script (`hooks/speak-notify.sh`). The script prefixes each phrase with the calling project's directory name (`basename "$PWD"`, the hook's own `cwd`) so overlapping sessions across projects are distinguishable — it's still fully deterministic, just reading a directory name, not summarizing anything:

| Event | Phrase |
| --- | --- |
| Turn/task finished (Claude Code `Stop`, Codex CLI `Stop`, opencode `session.idle`) | `"<project> finished."` |
| Waiting on you (Claude Code `Notification`, Codex CLI `PermissionRequest`, opencode `permission.ask`) | `"<project> needs your input."` |

For example, running in this repo: "agentic-voice finished." / "agentic-voice needs your input."

Claude Code and Codex CLI both consume the same declarative JSON hook schema, so [`hooks/hooks.json`](hooks/hooks.json) works for either unchanged — each engine reads the keys it recognizes and ignores the rest. Its `command` fields use `${CLAUDE_PLUGIN_ROOT}`, a variable both engines substitute at execution time when a hook is loaded via the plugin system below — no hardcoded path, portable to wherever the repo is cloned. opencode's plugin model is different — real JS event callbacks, not declarative config — so [`opencode/plugin.mjs`](opencode/plugin.mjs) maps the same two events to the same shared script directly.

### Install as a plugin (recommended — nothing happens automatically until you run these)

**Claude Code and Codex CLI** — this repo is itself a valid plugin for both (`.claude-plugin/` + `.codex-plugin/` + `.agents/plugins/marketplace.json`), installable straight from a local clone, no publishing required (note the trailing slash — `claude plugin marketplace add .` without it is rejected as an invalid source format):

```bash
# Claude Code — installs at user scope (fires in every project)
claude plugin marketplace add ./
claude plugin install agentic-voice@agentic-voice -y

# Codex CLI
codex plugin marketplace add ./
codex plugin add agentic-voice@agentic-voice
```

Check it loaded cleanly: `claude plugin details agentic-voice` / `codex plugin list --json`. To remove: `claude plugin uninstall agentic-voice && claude plugin marketplace remove agentic-voice`, `codex plugin remove agentic-voice@agentic-voice && codex plugin marketplace remove agentic-voice`.

The Codex plugin registers the stdio MCP server as well as hooks. After installation, run setup in the installed plugin copy if its build artifacts are missing, then reload Codex so it loads the new manifest and built files. Codex can omit the Swift `.build` directory when copying a local plugin, even if you already built the source checkout. The `speak` tool then becomes available and MCP manages the local bridge. Claude Code's plugin registration remains hooks-only.

For an existing installation from this local marketplace, reinstall:

```bash
codex plugin remove agentic-voice@agentic-voice
codex plugin add agentic-voice@agentic-voice --json
```

The JSON result includes `installedPath`. Run `npm run setup --prefix /absolute/installedPath` using that value to install dependencies and build both components in the installed copy. This is an explicit installation step, not MCP startup behavior. Repeat it after reinstalling if the build artifacts were omitted. Then reload Codex. Check startup stderr if the tool fails to load or speak.

**opencode** — `opencode plugin` installs directly from a GitHub `owner/repo` spec, no npm publish or local clone required:

```bash
opencode plugin maxanatsko/agentic-voice -g   # -g installs in global config (fires in every project)
```

To remove, delete the `"maxanatsko/agentic-voice"` entry opencode added to your plugin config (global config unless you omitted `-g`).

### Fallback: manual merge (Claude Code / Codex CLI, no plugin install)

Copy the `hooks` object out of `hooks/hooks.json` into `~/.claude/settings.json` (deep-merge alongside any existing keys, never a wholesale replace) or a project's `.codex/hooks.json`, replacing `${CLAUDE_PLUGIN_ROOT}` with this repo's absolute path — that variable is only substituted for plugin-loaded hooks.

**Prerequisites**: `npm run build` (so `dist/src/cli.js` exists) and the bridge running (`npm run bridge:start`).

An active MCP-owned bridge can also serve hooks. The hook script currently redirects output and suppresses errors with `|| true`, so hook failures are silent; MCP startup diagnostics remain visible on stderr.

## TTS HTTP contract

The bridge (and any compatible backend) exposes this HTTP synthesis endpoint:

```text
POST {TTS_URL}/v1/audio/synthesize
```

The request is multipart form data containing `language`, `text`, `voice`, and `speed`; the response is written as WAV audio and played locally.

For automatic management at the bundled loopback URL, backends must also expose `GET {TTS_URL}/v1/audio/health`: HTTP 200 with JSON `{"status":"ready"}` when synthesis is available, or HTTP 503 with JSON `{"status":"initializing"}` while loading. The bundled bridge starts HTTP only after model initialization and returns ready immediately. Readiness does not synthesize audio and does not depend on the response at `/`. Remote/custom URLs remain externally managed and only require the synthesis endpoint. Rebuild the bridge after updating its health endpoint.

## Contributing

See [`AGENTS.md`](AGENTS.md) for the engineering principles and conventions this codebase follows.

## Author

[Maxim Anatsko](https://maxanatsko.com)

## License

[MIT](LICENSE)
