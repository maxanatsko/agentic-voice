import { execFile } from 'node:child_process';
import { writeFile, unlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { randomUUID } from 'node:crypto';

const execFileAsync = promisify(execFile);

export class AudioPlayer {
  constructor(private readonly command = defaultPlaybackCommand()) {}

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
