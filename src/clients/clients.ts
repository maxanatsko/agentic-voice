import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { copyFile, mkdir, readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { pathToFileURL } from 'node:url';
import {
  readHookCommand, readJsonEntry, readTomlBlock, removeHook, removeJsonEntry, removeTomlBlock,
  tomlBlock, tomlString, upsertHook, upsertJsonEntry, upsertTomlBlock,
} from './config-edit.js';

const NAME = 'agentic-voice';

/** Where the installer runs from: the home directory, an absolute node, and the plugin root. */
export type InstallContext = { home: string; node: string; root: string };

export type ClientStatus = {
  id: ClientId;
  name: string;
  detected: boolean;
  installed: boolean;
  current: boolean;
  note?: string;
};

type Part =
  | { kind: 'json'; file: string; container: string; entry: unknown }
  | { kind: 'hook'; file: string; event: string; command: string }
  | { kind: 'toml'; file: string; table: string; body: string }
  | { kind: 'file'; file: string; content: string }
  | { kind: 'claude-cli'; file: string; entry: { command: string; args: string[] } };

type Client = { id: ClientId; name: string; directory: string; parts: Part[]; note?: string };

export const clientIds = ['claude-code', 'claude-desktop', 'codex', 'cursor', 'vscode', 'windsurf', 'opencode'] as const;
export type ClientId = typeof clientIds[number];

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

function clients({ home, node, root }: InstallContext): Client[] {
  const server = join(root, 'dist/src/server.js');
  const hook = `AGENTIC_VOICE_NODE=${shellQuote(node)} ${shellQuote(join(root, 'hooks/speak-notify.sh'))} input`;
  const appSupport = join(home, 'Library/Application Support');
  const opencodeDir = join(home, '.config/opencode');
  const opencodeJsonc = join(opencodeDir, 'opencode.jsonc');
  return [
    {
      id: 'claude-code', name: 'Claude Code', directory: join(home, '.claude'),
      parts: [
        { kind: 'claude-cli', file: join(home, '.claude.json'), entry: { command: node, args: [server] } },
        { kind: 'hook', file: join(home, '.claude/settings.json'), event: 'Notification', command: hook },
      ],
    },
    {
      id: 'claude-desktop', name: 'Claude Desktop', directory: join(appSupport, 'Claude'),
      parts: [{ kind: 'json', file: join(appSupport, 'Claude/claude_desktop_config.json'), container: 'mcpServers', entry: { command: node, args: [server] } }],
    },
    {
      id: 'codex', name: 'Codex CLI', directory: join(home, '.codex'),
      note: 'Restart Codex, then trust the new hook with /hooks.',
      parts: [
        {
          kind: 'toml', file: join(home, '.codex/config.toml'), table: `mcp_servers.${NAME}`,
          body: `command = ${tomlString(node)}\nargs = [${tomlString(server)}]\ntool_timeout_sec = 360\n`,
        },
        { kind: 'hook', file: join(home, '.codex/hooks.json'), event: 'PermissionRequest', command: hook },
      ],
    },
    {
      id: 'cursor', name: 'Cursor', directory: join(home, '.cursor'),
      parts: [{ kind: 'json', file: join(home, '.cursor/mcp.json'), container: 'mcpServers', entry: { command: node, args: [server] } }],
    },
    {
      id: 'vscode', name: 'VS Code', directory: join(appSupport, 'Code'),
      parts: [{ kind: 'json', file: join(appSupport, 'Code/User/mcp.json'), container: 'servers', entry: { type: 'stdio', command: node, args: [server] } }],
    },
    {
      id: 'windsurf', name: 'Windsurf', directory: join(home, '.codeium/windsurf'),
      parts: [{ kind: 'json', file: join(home, '.codeium/windsurf/mcp_config.json'), container: 'mcpServers', entry: { command: node, args: [server] } }],
    },
    {
      id: 'opencode', name: 'opencode', directory: opencodeDir,
      parts: [
        {
          kind: 'json', file: existsSync(opencodeJsonc) ? opencodeJsonc : join(opencodeDir, 'opencode.json'),
          container: 'mcp', entry: { type: 'local', command: [node, server], enabled: true },
        },
        {
          kind: 'file', file: join(opencodeDir, `plugins/${NAME}.js`),
          content: `// Managed by Agentic Voice: speaks when opencode finishes or needs your input.\n` +
            `process.env.AGENTIC_VOICE_NODE = ${JSON.stringify(node)};\n` +
            `export * from ${JSON.stringify(pathToFileURL(join(root, 'opencode/plugin.mjs')).href)};\n`,
        },
      ],
    },
  ];
}

async function read(file: string): Promise<string | undefined> {
  try {
    return await readFile(file, 'utf8');
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return undefined;
    throw error;
  }
}

/** Backs up the original once, then replaces the file atomically. */
async function write(file: string, next: string, previous: string | undefined): Promise<void> {
  if (next === previous) return;
  await mkdir(dirname(file), { recursive: true });
  const backup = `${file}.${NAME}-backup`;
  if (previous !== undefined && !existsSync(backup)) await copyFile(file, backup);
  const temporary = `${file}.${NAME}-tmp`;
  await writeFile(temporary, next);
  await rename(temporary, file);
}

function claude(args: string[]): void {
  try {
    execFileSync('claude', args, { stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    const detail = (error as { stderr?: Buffer }).stderr?.toString().trim();
    const reason = (error as NodeJS.ErrnoException).code === 'ENOENT'
      ? "the Claude Code CLI 'claude' was not found on PATH"
      : detail || String(error);
    throw new Error(`claude ${args.slice(0, 2).join(' ')} failed: ${reason}`, { cause: error });
  }
}

/** Returns [installed, current] for one part. */
async function inspect(part: Part): Promise<[boolean, boolean]> {
  const text = await read(part.file);
  if (text === undefined) return [false, false];
  switch (part.kind) {
    case 'json': {
      const entry = readJsonEntry(text, part.file, part.container, NAME);
      return [entry !== undefined, isDeepStrictEqual(entry, part.entry)];
    }
    case 'claude-cli': {
      const entry = readJsonEntry(text, part.file, 'mcpServers', NAME) as { command?: unknown; args?: unknown } | undefined;
      return [entry !== undefined, entry?.command === part.entry.command && isDeepStrictEqual(entry?.args, part.entry.args)];
    }
    case 'hook': {
      const command = readHookCommand(text, part.file, part.event);
      return [command !== undefined, command === part.command];
    }
    case 'toml': {
      const block = readTomlBlock(text);
      return [block !== undefined, block === tomlBlock(part.table, part.body)];
    }
    case 'file':
      return [true, text === part.content];
  }
}

async function install(part: Part): Promise<void> {
  const text = await read(part.file);
  switch (part.kind) {
    case 'json':
      return write(part.file, upsertJsonEntry(text ?? '', part.file, part.container, NAME, part.entry), text);
    case 'claude-cli':
      if (text !== undefined && readJsonEntry(text, part.file, 'mcpServers', NAME) !== undefined) claude(['mcp', 'remove', '-s', 'user', NAME]);
      return claude(['mcp', 'add-json', '-s', 'user', NAME, JSON.stringify({ type: 'stdio', ...part.entry })]);
    case 'hook':
      return write(part.file, upsertHook(text ?? '', part.file, part.event, part.command), text);
    case 'toml':
      return write(part.file, upsertTomlBlock(text ?? '', part.file, part.table, part.body), text);
    case 'file':
      return write(part.file, part.content, text);
  }
}

async function uninstall(part: Part): Promise<void> {
  const text = await read(part.file);
  if (text === undefined) return;
  switch (part.kind) {
    case 'json':
      return write(part.file, removeJsonEntry(text, part.file, part.container, NAME), text);
    case 'claude-cli':
      if (readJsonEntry(text, part.file, 'mcpServers', NAME) !== undefined) claude(['mcp', 'remove', '-s', 'user', NAME]);
      return;
    case 'hook':
      return write(part.file, removeHook(text, part.file, part.event), text);
    case 'toml':
      return write(part.file, removeTomlBlock(text), text);
    case 'file':
      return unlink(part.file);
  }
}

function find(context: InstallContext, id: ClientId): Client {
  const client = clients(context).find((candidate) => candidate.id === id);
  if (!client) throw new Error(`Unknown client '${id}'.`);
  return client;
}

/** An agentic-voice Claude Code plugin would register the same tool and hooks a second time. */
async function conflict(context: InstallContext, client: Client): Promise<string | undefined> {
  if (client.id !== 'claude-code') return undefined;
  const settings = await read(join(context.home, '.claude/settings.json'));
  const enabled = settings && (JSON.parse(settings) as { enabledPlugins?: Record<string, unknown> }).enabledPlugins;
  return enabled && Object.entries(enabled).some(([plugin, on]) => plugin.startsWith(`${NAME}@`) && on)
    ? 'The agentic-voice Claude Code plugin is also enabled; disable one of them to avoid speaking twice.'
    : undefined;
}

export async function status(context: InstallContext, id: ClientId): Promise<ClientStatus> {
  const client = find(context, id);
  let parts: [boolean, boolean][] = [];
  let note: string | undefined;
  try {
    parts = await Promise.all(client.parts.map(inspect));
    note = await conflict(context, client) ?? client.note;
  } catch (error) {
    parts = [[false, false]];
    note = error instanceof Error ? error.message : String(error);
  }
  return {
    id, name: client.name,
    detected: existsSync(client.directory),
    installed: parts.every(([installed]) => installed),
    current: parts.every(([, current]) => current),
    ...(note ? { note } : {}),
  };
}

export async function installClient(context: InstallContext, id: ClientId): Promise<void> {
  for (const part of find(context, id).parts) await install(part);
}

export async function uninstallClient(context: InstallContext, id: ClientId): Promise<void> {
  for (const part of find(context, id).parts) await uninstall(part);
}
