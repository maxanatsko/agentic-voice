import { spawn, type ChildProcess } from 'node:child_process';
import { access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { dirname, join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { pluginRoot } from '../runtime-paths.js';

const bridgeIdentity = 'TTSBridge (FluidAudio Kokoro-ANE) is running.';

type BridgeOptions = {
  executable?: string;
  startupTimeoutMs?: number;
  pollIntervalMs?: number;
  shutdownTimeoutMs?: number;
};

/** Owns only the child it launches. An already-running bridge is never signalled. */
export class BridgeProcess {
  private child?: ChildProcess;
  private readonly abort = new AbortController();
  private stopping?: Promise<void>;
  private readonly executable: string;

  constructor(private readonly url: string, private readonly options: BridgeOptions = {}) {
    this.executable = options.executable ?? join(pluginRoot, 'bridge/.build/debug/TTSBridge');
  }

  private async probe(): Promise<'ready' | 'unavailable' | 'occupied'> {
    try {
      const response = await fetch(this.url, {
        signal: AbortSignal.any([this.abort.signal, AbortSignal.timeout(1000)]),
        redirect: 'error',
      });
      return response.ok && (await response.text()).trim() === bridgeIdentity ? 'ready' : 'occupied';
    } catch {
      return 'unavailable';
    }
  }

  async start(): Promise<void> {
    this.abort.signal.throwIfAborted();
    const initial = await this.probe();
    this.abort.signal.throwIfAborted();
    if (initial === 'ready') {
      console.error(`agentic-voice: reusing bridge at ${this.url}`);
      return;
    }
    if (initial === 'occupied') {
      throw new Error(`TTS endpoint ${this.url} is occupied by a service other than TTSBridge. Free port 9000 or configure TTS_URL for your backend.`);
    }

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
    this.child = child;
    child.stdout?.pipe(process.stderr, { end: false });
    child.stderr?.pipe(process.stderr, { end: false });
    let failure: string | undefined;
    child.once('error', (error) => { failure = error.message; });
    child.once('exit', (code, signal) => { failure = `exit code ${code}, signal ${signal ?? 'none'}`; });
    const deadline = Date.now() + (this.options.startupTimeoutMs ?? 300_000);

    while (Date.now() < deadline) {
      this.abort.signal.throwIfAborted();
      const health = await this.probe();
      this.abort.signal.throwIfAborted();
      if (health === 'ready') {
        console.error(`agentic-voice: bridge ready at ${this.url}`);
        return;
      }
      if (failure) {
        // A simultaneous MCP start may have won the bind while our child exited.
        if (await this.probe() === 'ready') return;
        throw new Error(`TTSBridge ${this.executable} failed before readiness at ${this.url}: ${failure}. Check the bridge diagnostics above; run npm run bridge:start in ${pluginRoot} to diagnose model initialization or port conflicts.`);
      }
      if (health === 'occupied') {
        throw new Error(`TTS endpoint ${this.url} is occupied by another service while starting ${this.executable}. Free port 9000 or configure TTS_URL.`);
      }
      await delay(this.options.pollIntervalMs ?? 500, undefined, { signal: this.abort.signal });
    }
    throw new Error(`Timed out waiting for TTSBridge ${this.executable} at ${this.url}. First-use model downloads may need more time; run npm run bridge:start in ${pluginRoot} to initialize the cache and inspect its diagnostics, then restart MCP.`);
  }

  stop(): Promise<void> {
    return this.stopping ??= this.stopChild();
  }

  private async stopChild(): Promise<void> {
    this.abort.abort();
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
  }
}
