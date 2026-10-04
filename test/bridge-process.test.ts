import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import test from 'node:test';
import { BridgeProcess } from '../src/tts/bridge-process.js';
import { isBundledTtsUrl } from '../src/config.js';
import { TtsClient } from '../src/tts/tts-client.js';

const healthBody = JSON.stringify({ status: 'ready' });
const lockPorts = new Map<string, number>();

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
  if (!lockPorts.has(url)) lockPorts.set(url, Number(new URL(await unusedUrl()).port));
  await writeFile(executable, `#!${process.execPath}
const http = require('node:http');
require('node:fs').writeFileSync(${JSON.stringify(pidFile)}, String(process.pid));
${mode === 'exit' ? 'process.exit(23);' : mode === 'hang' || mode === 'stubborn' ? `${mode === 'stubborn' ? "process.on('SIGTERM', () => {});" : ''}setInterval(() => {}, 1000);` : `
const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.end(req.url === '/v1/audio/health' ? ${JSON.stringify(healthBody)} : 'arbitrary welcome page');
});
server.on('error', () => process.exit(24));
setTimeout(() => server.listen(${new URL(url).port}, '127.0.0.1'), ${mode === 'cold' ? 300 : 0});`}
`, { mode: 0o755 });
  const bridge = new BridgeProcess(url, {
    executable, startupTimeoutMs: 2000, pollIntervalMs: 20, shutdownTimeoutMs: 100,
    startupLockPort: lockPorts.get(url)!,
  });
  return {
    bridge,
    executable,
    pidFile,
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

test('reuses a backend through documented health regardless of its welcome page', async () => {
  const server = createServer((req, res) => res.end(req.url === '/v1/audio/health' ? healthBody : 'different backend'));
  const url = await listen(server);
  const bridge = new BridgeProcess(url, { executable: '/missing/build' });
  try {
    await bridge.start();
    await bridge.stop();
    assert.equal(await (await fetch(url)).text(), 'different backend');
  } finally { await close(server); }
});

test('waits for a backend reporting initialization without spawning a bridge', async () => {
  let requests = 0;
  const server = createServer((req, res) => {
    assert.equal(req.url, '/v1/audio/health');
    requests++;
    res.statusCode = requests === 1 ? 503 : 200;
    res.end(JSON.stringify({ status: requests === 1 ? 'initializing' : 'ready' }));
  });
  const url = await listen(server);
  const bridge = new BridgeProcess(url, { executable: '/missing/build', pollIntervalMs: 20 });
  try { await bridge.start(); assert.equal(requests, 2); }
  finally { await bridge.stop(); await close(server); }
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
    const replacement = await fixture(url);
    try { await replacement.bridge.start(); }
    finally { await replacement.dispose(); }
  } finally { await owned.dispose(); }
});

test('missing executable and occupied endpoint have actionable errors', async () => {
  const missing = new BridgeProcess(await unusedUrl(), {
    executable: '/missing/TTSBridge', startupLockPort: Number(new URL(await unusedUrl()).port),
  });
  await assert.rejects(missing.start(), /Cannot execute.*npm run setup/);
  await missing.stop();
  const server = createServer((req, res) => res.end('different service'));
  const url = await listen(server);
  const occupied = new BridgeProcess(url);
  try {
    await assert.rejects(occupied.start(), /does not implement GET.*health.*Free port 9000/);
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

test('cold startup is serialized before spawning while the model initializes', async () => {
  const url = await unusedUrl();
  const first = await fixture(url, 'cold');
  const second = await fixture(url);
  const starting = first.bridge.start();
  try {
    const firstPid = await first.pid();
    assert.equal(await TtsClient.checkReadiness(url, new AbortController().signal), 'unavailable');
    await Promise.all([starting, second.bridge.start()]);
    await assert.rejects(readFile(second.pidFile), { code: 'ENOENT' });
    await second.bridge.stop();
    assert.equal(await TtsClient.checkReadiness(url, new AbortController().signal), 'ready');
    assert(alive(firstPid));
  } finally { await first.dispose(); await second.dispose(); }
});

test('cancelling a startup waiter does not stop the owner or launch another child', async () => {
  const url = await unusedUrl();
  const first = await fixture(url, 'hang');
  const second = await fixture(url);
  const ownerStarting = assert.rejects(first.bridge.start(), /abort/i);
  try {
    const pid = await first.pid();
    const waiting = assert.rejects(second.bridge.start(), /abort/i);
    await delay(80);
    await assert.rejects(readFile(second.pidFile), { code: 'ENOENT' });
    await second.bridge.stop();
    await waiting;
    assert(alive(pid));
    await first.bridge.stop();
    await ownerStarting;
  } finally { await first.dispose(); await second.dispose(); }
});

test('an occupied coordination port times out without spawning', async () => {
  const lockServer = createServer();
  const lockUrl = await listen(lockServer);
  const bridge = new BridgeProcess(await unusedUrl(), {
    executable: '/missing/build', startupLockPort: Number(new URL(lockUrl).port),
    startupTimeoutMs: 100, pollIntervalMs: 20,
  });
  try {
    await assert.rejects(bridge.start(), /startup coordination.*coordination port is available/);
    assert(lockServer.listening);
  } finally { await bridge.stop(); await close(lockServer); }
});
