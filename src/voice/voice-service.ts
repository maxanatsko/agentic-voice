import { AudioPlayer } from '../audio/audio-player.js';
import { TtsClient } from '../tts/tts-client.js';

export class VoiceService {
  constructor(
    private readonly tts: TtsClient,
    private readonly player: AudioPlayer,
    private readonly maxChars: number,
  ) {}

  /** Speaks, or returns 'busy' without synthesizing when another session holds the speaker. */
  async speak(text: string): Promise<'spoken' | 'busy'> {
    const preparedText = prepareSpeechText(text, this.maxChars);
    const release = await this.player.claim();
    if (!release) return 'busy';
    try {
      // Holding the claim through synthesis keeps another session from cutting in before playback.
      const wav = await this.tts.synthesize(preparedText);
      await this.player.play(wav);
      return 'spoken';
    } finally {
      await release();
    }
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
