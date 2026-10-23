import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { loadConfig, readSettings } from '../src/config.js';

async function settingsFile(content: string): Promise<{ path: string; dispose: () => Promise<void> }> {
  const directory = await mkdtemp(join(tmpdir(), 'voice-config-test-'));
  const path = join(directory, 'config.json');
  await writeFile(path, content);
  return { path, dispose: () => rm(directory, { recursive: true, force: true }) };
}

test('a missing settings file means no settings', () => {
  assert.deepEqual(readSettings(join(tmpdir(), 'agentic-voice-missing', 'config.json')), {});
});

test('reads voice and speed and ignores unknown keys', async () => {
  const file = await settingsFile(JSON.stringify({ voice: ' af_bella ', speed: 1.25, theme: 'dark' }));
  try {
    assert.deepEqual(readSettings(file.path), { voice: 'af_bella', speed: 1.25 });
  } finally {
    await file.dispose();
  }
});

test('rejects malformed or invalid settings with the file path', async () => {
  for (const content of ['{not json', '[]', '{"voice": ""}', '{"voice": 3}', '{"speed": 0}', '{"speed": "fast"}']) {
    const file = await settingsFile(content);
    try {
      assert.throws(() => readSettings(file.path), (error: Error) => error.message.includes(file.path));
    } finally {
      await file.dispose();
    }
  }
});

test('settings override defaults', () => {
  const config = loadConfig({}, { voice: 'bf_emma', speed: 1.5 });
  assert.equal(config.voice, 'bf_emma');
  assert.equal(config.speed, 1.5);
  assert.equal(loadConfig({}, {}).voice, 'am_michael');
  assert.equal(loadConfig({}, {}).speed, 1.0);
});

test('environment overrides settings', () => {
  const config = loadConfig({ TTS_VOICE: 'am_adam', VOICE_SPEED: '0.8' }, { voice: 'bf_emma', speed: 1.5 });
  assert.equal(config.voice, 'am_adam');
  assert.equal(config.speed, 0.8);
});
