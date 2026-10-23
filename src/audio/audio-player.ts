import { execFile } from 'node:child_process';
import { writeFile, unlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { randomUUID } from 'node:crypto';
import { release, tryBindExclusive } from '../port-lock.js';

const execFileAsync = promisify(execFile);

/** Held by whichever agentic-voice process is speaking, so sessions never talk over each other. */
export const SPEAKING_LOCK_PORT = 19001;

export class AudioPlayer {
  constructor(
    private readonly command = defaultPlaybackCommand(),
    private readonly lockPort = SPEAKING_LOCK_PORT,
  ) {}

  /** Claims the speaker across processes. Resolves a release function, or undefined if another session is speaking. */
  async claim(): Promise<(() => Promise<void>) | undefined> {
    let lock;
    try {
      lock = await tryBindExclusive(this.lockPort);
    } catch (error) {
      throw new Error(`Cannot claim the speaker on 127.0.0.1:${this.lockPort}`, { cause: error });
    }
    return lock && (() => release(lock));
  }

  async play(wav: Buffer): Promise<void> {
    const filePath = join(tmpdir(), `agentic-voice-${randomUUID()}.wav`);
    await writeFile(filePath, wav);

    try {
      await execFileAsync(this.command, [filePath]);
    } catch (error) {
      throw new Error(`Audio playback failed using '${this.command}'`, { cause: error });
    } finally {
      await unlink(filePath).catch(() => undefined);
    }
  }
}

function defaultPlaybackCommand(): string {
  if (process.platform === 'darwin') {
    return 'afplay';
  }

  if (process.platform === 'linux') {
    return 'aplay';
  }

  throw new Error(
    `No default audio player for platform '${process.platform}'. Set VOICE_PLAYBACK_COMMAND.`,
  );
}
