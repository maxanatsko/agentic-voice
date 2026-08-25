import { existsSync } from 'node:fs';
import process from 'node:process';

if (existsSync('.env')) {
  process.loadEnvFile('.env');
}

export type AppConfig = {
  ttsUrl: string;
  voice: string;
  language: string;
  speed: number;
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

function positiveNumber(value: string | undefined, fallback: number): number {
  if (value === undefined) {
    return fallback;
  }

  const parsed = Number.parseFloat(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`Expected a positive number, received: ${value}`);
  }

  return parsed;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const playbackCommand = env.VOICE_PLAYBACK_COMMAND?.trim();

  return {
    ttsUrl: env.TTS_URL?.trim() || 'http://127.0.0.1:9000',
    voice: env.TTS_VOICE?.trim() || 'am_michael',
    language: env.TTS_LANGUAGE?.trim() || 'en-US',
    speed: positiveNumber(env.VOICE_SPEED, 1.0),
    maxChars: positiveInteger(env.VOICE_MAX_CHARS, 360),
    ...(playbackCommand ? { playbackCommand } : {}),
  };
}
