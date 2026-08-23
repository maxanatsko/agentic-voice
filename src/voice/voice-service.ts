import { AudioPlayer } from '../audio/audio-player.js';
import { NvidiaTtsClient } from '../tts/nvidia-tts-client.js';

export class VoiceService {
  constructor(
    private readonly tts: NvidiaTtsClient,
    private readonly player: AudioPlayer,
    private readonly maxChars: number,
  ) {}

  async speak(text: string): Promise<void> {
    const preparedText = prepareSpeechText(text, this.maxChars);
    const wav = await this.tts.synthesize(preparedText);
    await this.player.play(wav);
  }
}

export function prepareSpeechText(text: string, maxChars: number): string {
  const normalized = text.replace(/\s+/g, ' ').trim();

  if (!normalized) {
    throw new Error('Spoken text cannot be empty.');
  }

  if (normalized.length > maxChars) {
    throw new Error(
      `Spoken text is ${normalized.length} characters; limit is ${maxChars}. Summarize before speaking.`,
    );
  }

  return normalized;
}
