import { spawn, type ChildProcess } from 'node:child_process';
import { access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { dirname, join } from 'node:path';
import { createServer, type Server } from 'node:net';
import { setTimeout as delay } from 'node:timers/promises';
import { pluginRoot } from '../runtime-paths.js';
import { TtsClient } from './tts-client.js';

type BridgeOptions = {
  executable?: string;
  startupTimeoutMs?: number;
  pollIntervalMs?: number;
  shutdownTimeoutMs?: number;
  startupLockPort?: number;
};

/** Owns only the child it launches. An already-running bridge is never signalled. */
export class BridgeProcess {
  private child?: ChildProcess;
  private readonly abort = new AbortController();
  private stopping?: Promise<void>;
  private readonly executable: string;
  private startupLock: Server | undefined;
  private unlocking?: Promise<void>;

  constructor(private readonly url: string, private readonly options: BridgeOptions = {}) {
    this.executable = options.executable ?? join(pluginRoot, 'bridge/.build/debug/TTSBridge');
  }

  private acquireStartupLock(): Promise<boolean> {
    const server = createServer((socket) => socket.destroy());
    return new Promise((resolve, reject) => {
      server.once('error', (error: NodeJS.ErrnoException) => {
        if (error.code === 'EADDRINUSE') resolve(false);
        else reject(new Error(`Cannot coordinate TTSBridge startup: ${error.message}`, { cause: error }));
      });
      server.listen({ host: '127.0.0.1', port: this.options.startupLockPort ?? 19000, exclusive: true }, () => {
        if (this.abort.signal.aborted) {
          server.close();
          reject(this.abort.signal.reason);
          return;
        }
        this.startupLock = server;
        resolve(true);
      });
    });
  }

  private releaseStartupLock(): Promise<void> {
    const server = this.startupLock;
    if (!server) return this.unlocking ?? Promise.resolve();
    this.startupLock = undefined;
    return this.unlocking = new Promise((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
  }

  async start(): Promise<void> {
    const deadline = Date.now() + (this.options.startupTimeoutMs ?? 300_000);
    let failure: string | undefined;
    while (Date.now() < deadline) {
      this.abort.signal.throwIfAborted();
      const health = await TtsClient.checkReadiness(this.url, this.abort.signal);
      this.abort.signal.throwIfAborted();
      if (health === 'ready') {
        if (!this.child) await this.releaseStartupLock();
        console.error(`agentic-voice: ${this.child ? 'bridge ready' : 'reusing bridge'} at ${this.url}`);
        return;
      }
      if (health === 'occupied') {
        throw new Error(`TTS endpoint ${this.url} does not implement GET /v1/audio/health readiness. Free port 9000 or provide the documented health endpoint; use a remote/custom TTS_URL for an externally managed backend.`);
      }
      if (failure) {
        throw new Error(`TTSBridge ${this.executable} failed before readiness at ${this.url}: ${failure}. Check the bridge diagnostics above; run npm run bridge:start in ${pluginRoot} to diagnose model initialization or port conflicts.`);
      }
      if (health === 'unavailable' && !this.child) {
        if (!this.startupLock) {
          if (await this.acquireStartupLock()) continue; // Recheck readiness after gaining ownership.
        } else {
          this.child = await this.spawnBridge((message) => { failure = message; });
        }
      }
      await delay(this.options.pollIntervalMs ?? 500, undefined, { signal: this.abort.signal });
    }
    throw new Error(`Timed out waiting for TTSBridge ${this.executable} at ${this.url} or startup coordination on 127.0.0.1:${this.options.startupLockPort ?? 19000}. Another MCP instance may be initializing; ensure the coordination port is available. First-use model downloads may need more time; run npm run bridge:start in ${pluginRoot} to initialize the cache and inspect its diagnostics, then restart MCP.`);
  }

  private async spawnBridge(onfailure: (message: string) => void): Promise<ChildProcess> {
    this.abort.signal.throwIfAborted();
    try {
      await access(this.executable, constants.X_OK);
    } catch (error) {
      throw new Error(`Cannot execute TTSBridge at ${this.executable}. Run npm run setup in ${pluginRoot} before starting MCP.`, { cause: error });
    }
    this.abort.signal.throwIfAborted();
    console.error(`agentic-voice: starting ${this.executable}; waiting for ${this.url} (first use may download model assets; later starts use the cache)`);
    const child = spawn(this.executable, [], {
      cwd: dirname(this.executable),
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    // Store ownership before yielding, so concurrent shutdown always sees this child.
    this.child = child;
    child.stdout?.pipe(process.stderr, { end: false });
    child.stderr?.pipe(process.stderr, { end: false });
    child.once('error', (error) => { onfailure(error.message); });
    child.once('exit', (code, signal) => {
      onfailure(`exit code ${code}, signal ${signal ?? 'none'}`);
      void this.releaseStartupLock().catch((error: unknown) => console.error('agentic-voice: startup lock cleanup failed', error));
    });
    return child;
  }

  stop(): Promise<void> {
    return this.stopping ??= this.stopChild();
  }

  private async stopChild(): Promise<void> {
    this.abort.abort();
    try {
      const child = this.child;
      if (!child || child.exitCode !== null || child.signalCode !== null || !child.pid) return;
      const exited = new Promise<void>((resolve) => child.once('exit', () => resolve()));
      child.kill('SIGTERM');
      const timer = setTimeout(() => child.kill('SIGKILL'), this.options.shutdownTimeoutMs ?? 5000);
      try {
        await exited;
      } finally {
        clearTimeout(timer);
      }
    } finally {
      await this.releaseStartupLock();
    }
  }
}
