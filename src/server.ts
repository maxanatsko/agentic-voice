import { McpServer } from '@modelcontextprotocol/server';
import { serveStdio } from '@modelcontextprotocol/server/stdio';
import * as z from 'zod/v4';
import { createVoiceService } from './create-voice-service.js';

const speakInput = z.object({
  text: z
    .string()
    .describe('One or two short sentences written for listening, not a copy of detailed text output.'),
  kind: z
    .enum(['question', 'completion', 'alert', 'custom'])
    .optional()
    .describe('Optional reason for speaking. Metadata only in the MVP.'),
});

function buildServer(): McpServer {
  const server = new McpServer({ name: 'agentic-voice', version: '0.1.0' });
  const voice = createVoiceService();

  server.registerTool(
    'speak',
    {
      title: 'Speak a short message',
      description:
        'Speak a concise question, blocker, alert, or completion summary through local NVIDIA TTS. Do not send code, logs, paths, or long output.',
      inputSchema: speakInput,
    },
    async ({ text }) => {
      try {
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

void serveStdio(buildServer);
console.error('agentic-voice MCP server running on stdio');
