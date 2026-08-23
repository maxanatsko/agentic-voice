import { readFileSync } from 'node:fs';
import { createVoiceService } from './create-voice-service.js';

function readText(): string {
  const argumentText = process.argv.slice(2).join(' ').trim();
  if (argumentText) {
    return argumentText;
  }

  if (!process.stdin.isTTY) {
    return readFileSync(0, 'utf8').trim();
  }

  throw new Error('Provide text as arguments or pipe it through stdin.');
}

async function main(): Promise<void> {
  const voice = createVoiceService();
  await voice.speak(readText());
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`agentic-voice: ${message}`);
  process.exitCode = 1;
});
