import { McpServer } from '@modelcontextprotocol/server';
import { serveStdio } from '@modelcontextprotocol/server/stdio';
import * as z from 'zod/v4';
import { createVoiceService } from './create-voice-service.js';
import { isBundledTtsUrl, loadConfig } from './config.js';
import { BridgeProcess } from './tts/bridge-process.js';
import type { VoiceService } from './voice/voice-service.js';

const speakInput = z.object({
  text: z
    .string()
    .describe('One or two short sentences written for listening, not a copy of detailed text output.'),
  kind: z
    .enum(['question', 'completion', 'alert', 'custom'])
    .optional()
    .describe('Optional reason for speaking. Metadata only in the MVP.'),
});

function buildServer(voice: VoiceService, ready: Promise<void>, onclose: () => void): McpServer {
  const server = new McpServer({ name: 'agentic-voice', version: '0.1.0' });
  server.server.onclose = onclose;

  server.registerTool(
    'speak',
    {
      title: 'Speak a short message',
      description:
        'Speak a concise question, blocker, alert, or completion summary through local TTS. Do not send code, logs, paths, or long output.',
      inputSchema: speakInput,
    },
    async ({ text }) => {
      try {
        await ready;
        await voice.speak(text);
        return {
          content: [{ type: 'text', text: 'Spoken successfully.' }],
        };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return {
          content: [{ type: 'text', text: message }],
          isError: true,
        };
      }
    },
  );

  return server;
}

function main(): void {
  const config = loadConfig();
  const local = isBundledTtsUrl(config.ttsUrl);
  // The bundled bridge binds IPv4 only; localhost may resolve to IPv6 first.
  if (local) config.ttsUrl = 'http://127.0.0.1:9000';
  const voice = createVoiceService(config);
  const bridge = local ? new BridgeProcess(config.ttsUrl) : undefined;
  let handle: ReturnType<typeof serveStdio> | undefined;
  let shutdown: Promise<void> | undefined;
  const close = (): void => {
    shutdown ??= (async () => {
      await bridge?.stop();
      await handle?.close();
    })().finally(() => process.exit(process.exitCode ?? 0));
  };
  process.stdin.once('end', close);
  process.stdin.once('close', close);
  process.once('SIGINT', close);
  process.once('SIGTERM', close);
  const ready = bridge?.start() ?? Promise.resolve();
  // Stay connected after a bridge failure: speak reports the error to the client,
  // which otherwise sees only a dropped connection after a successful handshake.
  void ready.catch((error: unknown) => {
    if (shutdown) return;
    console.error(`agentic-voice: bridge startup failed: ${error instanceof Error ? error.message : String(error)}`);
    void bridge?.stop();
  });
  handle = serveStdio(() => buildServer(voice, ready, close), {
    onerror: (error) => console.error(`agentic-voice MCP: ${error.message}`),
  });
  console.error('agentic-voice MCP server running on stdio');
}

try {
  main();
} catch (error) {
  console.error(`agentic-voice: startup failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
}
