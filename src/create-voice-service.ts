import { AudioPlayer } from './audio/audio-player.js';
import { loadConfig } from './config.js';
import { NvidiaTtsClient } from './tts/nvidia-tts-client.js';
import { VoiceService } from './voice/voice-service.js';

export function createVoiceService(): VoiceService {
  const config = loadConfig();
  const tts = new NvidiaTtsClient({
    baseUrl: config.ttsUrl,
    voice: config.voice,
    language: config.language,
  });
  const player = new AudioPlayer(config.playbackCommand);

  return new VoiceService(tts, player, config.maxChars);
}
