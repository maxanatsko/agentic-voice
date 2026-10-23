import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import process from 'node:process';
import { join } from 'node:path';
import { pluginRoot } from './runtime-paths.js';

const envPath = join(pluginRoot, '.env');
if (existsSync(envPath)) {
  process.loadEnvFile(envPath);
}

export function isBundledTtsUrl(value: string): boolean {
  const url = new URL(value);
  return url.protocol === 'http:' &&
    ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname) &&
    url.port === '9000' && url.pathname === '/' && !url.search && !url.hash &&
    !url.username && !url.password;
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

/** Written by the Agentic Voice macOS app; environment variables and .env override it. */
export const settingsPath = join(homedir(), 'Library', 'Application Support', 'AgenticVoice', 'config.json');

export type Settings = {
  voice?: string;
  speed?: number;
};

export function readSettings(path = settingsPath): Settings {
  let text: string;
  try {
    text = readFileSync(path, 'utf8');
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return {};
    throw error;
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (error) {
    throw new Error(`Settings file ${path} is not valid JSON. Fix or delete it.`, { cause: error });
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    throw new Error(`Settings file ${path} must contain a JSON object.`);
  }

  const { voice, speed } = parsed as Record<string, unknown>;
  if (voice !== undefined && (typeof voice !== 'string' || !voice.trim())) {
    throw new Error(`Settings file ${path}: "voice" must be a non-empty string.`);
  }
  if (speed !== undefined && (typeof speed !== 'number' || !Number.isFinite(speed) || speed <= 0)) {
    throw new Error(`Settings file ${path}: "speed" must be a positive number.`);
  }

  return {
    ...(voice !== undefined ? { voice: voice.trim() } : {}),
    ...(speed !== undefined ? { speed } : {}),
  };
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env, settings: Settings = readSettings()): AppConfig {
  const playbackCommand = env.VOICE_PLAYBACK_COMMAND?.trim();

  return {
    ttsUrl: env.TTS_URL?.trim() || 'http://127.0.0.1:9000',
    voice: env.TTS_VOICE?.trim() || settings.voice || 'am_michael',
    language: env.TTS_LANGUAGE?.trim() || 'en-US',
    speed: positiveNumber(env.VOICE_SPEED, settings.speed ?? 1.0),
    maxChars: positiveInteger(env.VOICE_MAX_CHARS, 360),
    ...(playbackCommand ? { playbackCommand } : {}),
  };
}
