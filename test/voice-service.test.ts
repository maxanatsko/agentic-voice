import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { createServer as createHttpServer } from 'node:http';
import { createServer as createNetServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import test from 'node:test';
import { AudioPlayer } from '../src/audio/audio-player.js';
import { release, tryBindExclusive } from '../src/port-lock.js';
import { TtsClient } from '../src/tts/tts-client.js';
import { prepareSpeechText, VoiceService } from '../src/voice/voice-service.js';

test('normalizes whitespace before speaking', () => {
  assert.equal(prepareSpeechText('  Review\ncomplete.   Two issues.  ', 100), 'Review complete. Two issues.');
});

test('rejects empty speech', () => {
  assert.throws(() => prepareSpeechText('   ', 100), /cannot be empty/i);
});

test('rejects text above the configured limit', () => {
  assert.throws(() => prepareSpeechText('123456', 5), /Summarize before speaking/);
});

async function freePort(): Promise<number> {
  const server = createNetServer();
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  assert(address && typeof address !== 'string');
  await new Promise<void>((resolve) => server.close(() => resolve()));
  return address.port;
}

/** A real TTS endpoint and a real player whose command blocks until the test lets it finish. */
async function speakingFixture(playerExitCode = 0) {
  const directory = await mkdtemp(join(tmpdir(), 'voice-service-test-'));
  const playing = join(directory, 'playing');
  const finish = join(directory, 'finish');
  const player = join(directory, 'player');
  await writeFile(player, `#!${process.execPath}
const fs = require('node:fs');
fs.writeFileSync(${JSON.stringify(playing)}, '');
const timer = setInterval(() => {
  if (fs.existsSync(${JSON.stringify(finish)})) { clearInterval(timer); process.exit(${playerExitCode}); }
}, 10);
`, { mode: 0o755 });

  let synthesized = 0;
  const tts = createHttpServer((req, res) => {
    req.resume();
    req.on('end', () => { synthesized++; res.setHeader('Content-Type', 'audio/wav'); res.end('RIFF'); });
  });
  await new Promise<void>((resolve) => tts.listen(0, '127.0.0.1', resolve));
  const address = tts.address();
  assert(address && typeof address !== 'string');

  const lockPort = await freePort();
  const voice = () => new VoiceService(
    new TtsClient({ baseUrl: `http://127.0.0.1:${address.port}`, voice: 'am_michael', language: 'en-US', speed: 1 }),
    new AudioPlayer(player, lockPort),
    100,
  );
  return {
    voice,
    lockPort,
    synthesized: () => synthesized,
    playing: async () => { while (!existsSync(playing)) await delay(10); },
    finish: () => writeFile(finish, ''),
    dispose: async () => {
      tts.closeAllConnections();
      await new Promise<void>((resolve) => tts.close(() => resolve()));
      await rm(directory, { recursive: true, force: true });
    },
  };
}

test('reports busy without synthesizing while another session is speaking', async () => {
  const fixture = await speakingFixture();
  try {
    const first = fixture.voice().speak('First message.');
    await fixture.playing();
    assert.equal(await fixture.voice().speak('Second message.'), 'busy');
    assert.equal(fixture.synthesized(), 1);
    await fixture.finish();
    assert.equal(await first, 'spoken');
    assert.equal(await fixture.voice().speak('Third message.'), 'spoken');
    assert.equal(fixture.synthesized(), 2);
  } finally {
    await fixture.dispose();
  }
});

test('releases the speaker after a playback failure', async () => {
  const fixture = await speakingFixture(1);
  try {
    await fixture.finish();
    await assert.rejects(fixture.voice().speak('Failing message.'), /Audio playback failed/);
    const lock = await tryBindExclusive(fixture.lockPort);
    assert(lock, 'speaker lock should be free after a failure');
    await release(lock);
  } finally {
    await fixture.dispose();
  }
});

test('an exclusive port lock is free again once released', async () => {
  const port = await freePort();
  const held = await tryBindExclusive(port);
  assert(held);
  assert.equal(await tryBindExclusive(port), undefined);
  await release(held);
  const again = await tryBindExclusive(port);
  assert(again);
  await release(again);
});
