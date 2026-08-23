import { existsSync } from 'node:fs';
import process from 'node:process';

if (existsSync('.env')) {
  process.loadEnvFile('.env');
}

export type AppConfig = {
  ttsUrl: string;
  voice: string;
  language: string;
  maxChars: number;
  playbackCommand?: string;
};

function positiveInteger(value: string | undefined, fallback: number): number {
  if (value === undefined) {
    return fallback;
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`Expected a positive integer, received: ${value}`);
  }

  return parsed;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const playbackCommand = env.VOICE_PLAYBACK_COMMAND?.trim();

  return {
    ttsUrl: env.NVIDIA_TTS_URL?.trim() || 'http://127.0.0.1:9000',
    voice: env.NVIDIA_TTS_VOICE?.trim() || 'Magpie-Multilingual.EN-US.Aria',
    language: env.NVIDIA_TTS_LANGUAGE?.trim() || 'en-US',
    maxChars: positiveInteger(env.VOICE_MAX_CHARS, 360),
    ...(playbackCommand ? { playbackCommand } : {}),
  };
}
