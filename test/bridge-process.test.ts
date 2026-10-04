import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import test from 'node:test';
import { BridgeProcess } from '../src/tts/bridge-process.js';
import { isBundledTtsUrl } from '../src/config.js';

const identity = 'TTSBridge (FluidAudio Kokoro-ANE) is running.\n';

async function listen(server: Server): Promise<string> {
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  assert(address && typeof address !== 'string');
  return `http://127.0.0.1:${address.port}`;
}

async function close(server: Server): Promise<void> {
  server.closeAllConnections();
  await new Promise<void>((resolve) => server.close(() => resolve()));
}

async function fixture(url: string, mode = 'serve') {
  const directory = await mkdtemp(join(tmpdir(), 'voice-bridge-test-'));
  const executable = join(directory, 'bridge');
  const pidFile = join(directory, 'pid');
  await writeFile(executable, `#!${process.execPath}
const http = require('node:http');
require('node:fs').writeFileSync(${JSON.stringify(pidFile)}, String(process.pid));
${mode === 'exit' ? 'process.exit(23);' : mode === 'hang' || mode === 'stubborn' ? `${mode === 'stubborn' ? "process.on('SIGTERM', () => {});" : ''}setInterval(() => {}, 1000);` : `
const server = http.createServer((req, res) => res.end(${JSON.stringify(identity)}));
server.on('error', () => process.exit(24));
server.listen(${new URL(url).port}, '127.0.0.1');`}
`, { mode: 0o755 });
  const bridge = new BridgeProcess(url, {
    executable, startupTimeoutMs: 2000, pollIntervalMs: 20, shutdownTimeoutMs: 100,
  });
  return {
    bridge,
    executable,
    pid: async () => {
      for (let attempt = 0; attempt < 100; attempt++) {
        const pid = await readFile(pidFile, 'utf8').catch(() => undefined);
        if (pid) return Number(pid);
        await delay(10);
      }
      throw new Error('Fixture did not write its PID');
    },
    dispose: async () => { await bridge.stop(); await rm(directory, { recursive: true, force: true }); },
  };
}

async function unusedUrl(): Promise<string> {
  const server = createServer();
  const url = await listen(server);
  await close(server);
  return url;
}

function alive(pid: number): boolean {
  try { process.kill(pid, 0); return true; } catch { return false; }
}

test('only the bundled loopback endpoint is automatically managed', () => {
  for (const url of ['http://127.0.0.1:9000', 'http://localhost:9000/', 'http://[::1]:9000']) assert(isBundledTtsUrl(url));
  for (const url of ['https://127.0.0.1:9000', 'http://example.com:9000', 'http://127.0.0.1:9001', 'http://localhost:9000/tts']) {
    assert.equal(isBundledTtsUrl(url), false);
  }
});

test('reuses a healthy external bridge and leaves it running on shutdown', async () => {
  const server = createServer((req, res) => res.end(identity));
  const url = await listen(server);
  const bridge = new BridgeProcess(url, { executable: '/missing/build' });
  try {
    await bridge.start();
    await bridge.stop();
    assert.equal(await (await fetch(url)).text(), identity);
  } finally { await close(server); }
});

test('starts a child, waits for readiness, and cleans up only that child', async () => {
  const url = await unusedUrl();
  const owned = await fixture(url);
  const borrower = new BridgeProcess(url, { executable: '/missing/build' });
  try {
    await owned.bridge.start();
    const pid = await owned.pid();
    assert(alive(pid));
    await borrower.start();
    await borrower.stop();
    assert(alive(pid));
    await Promise.all([owned.bridge.stop(), owned.bridge.stop()]);
    assert.equal(alive(pid), false);
  } finally { await owned.dispose(); }
});

test('missing executable and occupied endpoint have actionable errors', async () => {
  const missing = new BridgeProcess(await unusedUrl(), { executable: '/missing/TTSBridge' });
  await assert.rejects(missing.start(), /Cannot execute.*npm run setup/);
  await missing.stop();
  const server = createServer((req, res) => res.end('different service'));
  const url = await listen(server);
  const occupied = new BridgeProcess(url);
  try {
    await assert.rejects(occupied.start(), /occupied.*Free port 9000/);
  } finally { await occupied.stop(); await close(server); }
});

test('premature exit and readiness timeout include bridge diagnostics guidance', async () => {
  const failed = await fixture(await unusedUrl(), 'exit');
  try {
    await assert.rejects(failed.bridge.start(), /exit code 23.*bridge:start/);
  } finally { await failed.dispose(); }
  const hung = await fixture(await unusedUrl(), 'hang');
  try {
    await assert.rejects(hung.bridge.start(), /Timed out.*model downloads.*bridge:start/);
    const pid = await hung.pid();
    await hung.bridge.stop();
    assert.equal(alive(pid), false);
  } finally { await hung.dispose(); }
});

test('spawn errors are reported and an unresponsive owned child is forcibly stopped', async () => {
  const invalid = await fixture(await unusedUrl());
  try {
    await writeFile(invalid.executable, '#!/missing/interpreter\n');
    await assert.rejects(invalid.bridge.start(), /failed before readiness.*ENOENT.*bridge:start/);
  } finally { await invalid.dispose(); }
  const stubborn = await fixture(await unusedUrl(), 'stubborn');
  const starting = stubborn.bridge.start();
  const rejected = assert.rejects(starting, /abort/i);
  try {
    const pid = await stubborn.pid();
    await stubborn.bridge.stop();
    await rejected;
    assert.equal(alive(pid), false);
  } finally { await stubborn.dispose(); }
});

test('shutdown cancels startup and removes the initializing child', async () => {
  const hung = await fixture(await unusedUrl(), 'hang');
  const starting = hung.bridge.start();
  const rejected = assert.rejects(starting, /abort/i);
  try {
    const pid = await hung.pid();
    await hung.bridge.stop();
    await rejected;
    assert.equal(alive(pid), false);
  } finally { await hung.dispose(); }
});

test('simultaneous starts can reuse the winner without killing its bridge', async () => {
  const url = await unusedUrl();
  const first = await fixture(url);
  const second = await fixture(url);
  try {
    await Promise.all([first.bridge.start(), second.bridge.start()]);
    const firstPid = await first.pid();
    const secondPid = await second.pid();
    // The losing child eventually exits after its bind fails.
    for (let attempt = 0; attempt < 100 && alive(firstPid) && alive(secondPid); attempt++) await delay(10);
    assert.notEqual(alive(firstPid), alive(secondPid));
    const winner = alive(firstPid) ? first : second;
    const loser = winner === first ? second : first;
    await loser.bridge.stop();
    assert.equal(await (await fetch(url)).text(), identity);
    assert(alive(await winner.pid()));
  } finally { await first.dispose(); await second.dispose(); }
});
