import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { chmod, mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { clientIds, installClient, status, uninstallClient, type InstallContext } from '../src/clients/clients.js';
import { upsertTomlBlock } from '../src/clients/config-edit.js';

const root = '/Applications/Agentic Voice.app/Contents/Resources/agentic-voice';
const node = '/opt/homebrew/bin/node';
const server = `${root}/dist/src/server.js`;

/** A temp home with a fake `claude` CLI that edits ~/.claude.json like the real one. */
async function fixture() {
  const home = await mkdtemp(join(tmpdir(), 'voice-clients-test-'));
  const bin = join(home, 'bin');
  await mkdir(bin);
  await writeFile(join(bin, 'claude'), `#!${process.execPath}
const fs = require('node:fs');
const file = ${JSON.stringify(join(home, '.claude.json'))};
const config = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
const [, , name, json] = process.argv.slice(2).filter((arg) => arg !== '-s' && arg !== 'user');
config.mcpServers ??= {};
if (process.argv[3] === 'add-json') config.mcpServers[name] = JSON.parse(json);
else delete config.mcpServers[name];
fs.writeFileSync(file, JSON.stringify(config));
`, { mode: 0o755 });
  const previousPath = process.env.PATH;
  process.env.PATH = `${bin}:${previousPath}`;
  const context: InstallContext = { home, node, root };
  const file = (path: string) => join(home, path);
  const put = async (path: string, content: string) => {
    await mkdir(dirname(file(path)), { recursive: true });
    await writeFile(file(path), content);
  };
  return {
    context, file, put,
    read: (path: string) => readFile(file(path), 'utf8'),
    json: async (path: string) => JSON.parse(await readFile(file(path), 'utf8')),
    dispose: async () => {
      process.env.PATH = previousPath;
      await rm(home, { recursive: true, force: true });
    },
  };
}

const existing = {
  '.cursor/mcp.json': JSON.stringify({ mcpServers: { other: { command: 'other' } }, theme: 'dark' }),
  '.claude/settings.json': JSON.stringify({ hooks: { Notification: [{ hooks: [{ type: 'command', command: 'say hi' }] }] }, model: 'opus' }),
  '.codex/config.toml': 'model = "gpt"\n\n[mcp_servers.other]\ncommand = "other"\n',
};

test('installs every client, keeping existing entries, and reports them current', async () => {
  const f = await fixture();
  try {
    for (const [path, content] of Object.entries(existing)) await f.put(path, content);
    for (const id of clientIds) await installClient(f.context, id);

    for (const id of clientIds) {
      const result = await status(f.context, id);
      assert.equal(result.installed, true, id);
      assert.equal(result.current, true, id);
    }

    const cursor = await f.json('.cursor/mcp.json');
    assert.deepEqual(cursor.mcpServers.other, { command: 'other' });
    assert.deepEqual(cursor.mcpServers['agentic-voice'], { command: node, args: [server] });
    assert.equal(cursor.theme, 'dark');

    const claude = await f.json('.claude.json');
    assert.deepEqual(claude.mcpServers['agentic-voice'], { type: 'stdio', command: node, args: [server] });
    const settings = await f.json('.claude/settings.json');
    assert.equal(settings.model, 'opus');
    assert.equal(settings.hooks.Notification.length, 2);
    assert.equal(settings.hooks.Notification[1].hooks[0].command,
      `AGENTIC_VOICE_NODE='${node}' '${root}/hooks/speak-notify.sh' input`);

    const toml = await f.read('.codex/config.toml');
    assert(toml.startsWith(existing['.codex/config.toml'].trimEnd()));
    assert.match(toml, /\[mcp_servers\.agentic-voice\]\ncommand = "\/opt\/homebrew\/bin\/node"\nargs = \[".*server\.js"\]\ntool_timeout_sec = 360\n/);
    assert.deepEqual((await f.json('.codex/hooks.json')).hooks.PermissionRequest.length, 1);

    assert.deepEqual((await f.json('Library/Application Support/Code/User/mcp.json')).servers['agentic-voice'].type, 'stdio');
    assert.deepEqual((await f.json('.config/opencode/opencode.json')).mcp['agentic-voice'].command, [node, server]);
    assert.match(await f.read('.config/opencode/plugins/agentic-voice.js'), /AGENTIC_VOICE_NODE = "\/opt\/homebrew\/bin\/node"/);
  } finally {
    await f.dispose();
  }
});

test('reinstalling changes nothing and backs up the original only once', async () => {
  const f = await fixture();
  try {
    for (const [path, content] of Object.entries(existing)) await f.put(path, content);
    for (const id of clientIds) await installClient(f.context, id);
    const first = await f.read('.cursor/mcp.json');
    const firstToml = await f.read('.codex/config.toml');
    for (const id of clientIds) await installClient(f.context, id);

    assert.equal(await f.read('.cursor/mcp.json'), first);
    assert.equal(await f.read('.codex/config.toml'), firstToml);
    assert.equal(await f.read('.cursor/mcp.json.agentic-voice-backup'), existing['.cursor/mcp.json']);
    assert.equal(await f.read('.codex/config.toml.agentic-voice-backup'), existing['.codex/config.toml']);
    assert.equal(existsSync(f.file('.codeium/windsurf/mcp_config.json.agentic-voice-backup')), false);
  } finally {
    await f.dispose();
  }
});

test('reinstalling with a new node path updates outdated entries', async () => {
  const f = await fixture();
  try {
    await installClient(f.context, 'cursor');
    const moved = { ...f.context, node: '/usr/local/bin/node' };
    assert.equal((await status(moved, 'cursor')).current, false);
    await installClient(moved, 'cursor');
    assert.equal((await status(moved, 'cursor')).current, true);
  } finally {
    await f.dispose();
  }
});

test('uninstalling removes only agentic-voice entries', async () => {
  const f = await fixture();
  try {
    for (const [path, content] of Object.entries(existing)) await f.put(path, content);
    for (const id of clientIds) await installClient(f.context, id);
    for (const id of clientIds) await uninstallClient(f.context, id);

    for (const id of clientIds) assert.equal((await status(f.context, id)).installed, false, id);
    assert.deepEqual(await f.json('.cursor/mcp.json'), JSON.parse(existing['.cursor/mcp.json']));
    assert.deepEqual(await f.json('.claude/settings.json'), JSON.parse(existing['.claude/settings.json']));
    assert.equal(await f.read('.codex/config.toml'), existing['.codex/config.toml']);
    assert.deepEqual((await f.json('.claude.json')).mcpServers, {});
    assert.equal(existsSync(f.file('.config/opencode/plugins/agentic-voice.js')), false);
  } finally {
    await f.dispose();
  }
});

test('refuses a codex table defined outside the managed block, however it is written', () => {
  for (const header of [
    '[mcp_servers.agentic-voice]', '[mcp_servers."agentic-voice"] # mine', "[ mcp_servers . 'agentic-voice' ]",
    'mcp_servers.agentic-voice.command = "node"', 'mcp_servers = { agentic-voice = { command = "node" } }',
    '[mcp_servers."agentic\\u002Dvoice"]', 'mcp_servers."agentic\\u002Dvoice".command = "node"',
  ]) {
    assert.throws(
      () => upsertTomlBlock(`${header}\ncommand = "node"\n`, 'config.toml', 'mcp_servers.agentic-voice', 'command = "x"\n'),
      /already defines agentic-voice/,
      header,
    );
  }
  for (const header of ['[mcp_servers]\nagentic-voice = { command = "node" }', '[mcp_servers]\n"agentic-voice".command = "node"']) {
    assert.throws(
      () => upsertTomlBlock(`${header}\n`, 'config.toml', 'mcp_servers.agentic-voice', 'command = "x"\n'),
      /already defines agentic-voice/,
      header,
    );
  }
});

test('refuses to replace a config container that is not an object', async () => {
  const f = await fixture();
  try {
    const cursor = JSON.stringify({ mcpServers: [{ name: 'mine' }] });
    const claude = JSON.stringify({ hooks: { Notification: { command: 'say hi' } } });
    await f.put('.cursor/mcp.json', cursor);
    await f.put('.claude/settings.json', claude);
    await assert.rejects(installClient(f.context, 'cursor'), /"mcpServers" is not an object/);
    await assert.rejects(installClient(f.context, 'claude-code'), /"Notification" is not an array/);
    assert.equal(await f.read('.cursor/mcp.json'), cursor);
    assert.equal(await f.read('.claude/settings.json'), claude);
    assert.deepEqual((await f.json('.claude.json').catch(() => ({}))).mcpServers ?? {}, {});
  } finally {
    await f.dispose();
  }
});

test('accepts agentic-voice keys outside mcp_servers, such as a Codex plugin marketplace', () => {
  const codex = [
    '[marketplaces.agentic-voice]', 'source = "/Users/me/agentic-voice"', '',
    '[plugins."agentic-voice@agentic-voice"]', 'enabled = true', '',
    '[mcp_servers.other]', 'command = "other"', 'agentic-voice = "not a server"', '',
  ].join('\n');
  assert.match(
    upsertTomlBlock(codex, 'config.toml', 'mcp_servers.agentic-voice', 'command = "x"\n'),
    /\[mcp_servers\.agentic-voice\]\ncommand = "x"\n/,
  );
});

test('uninstalling the only hook leaves no empty hooks object behind', async () => {
  const f = await fixture();
  try {
    await f.put('.claude/settings.json', JSON.stringify({ model: 'opus' }));
    await installClient(f.context, 'claude-code');
    await uninstallClient(f.context, 'claude-code');
    assert.deepEqual(await f.json('.claude/settings.json'), { model: 'opus' });
  } finally {
    await f.dispose();
  }
});

test('keeps other commands that share a hook group with ours', async () => {
  const f = await fixture();
  try {
    const shared = { hooks: { Notification: [{ hooks: [
      { type: 'command', command: "AGENTIC_VOICE_NODE='/old/node' '/old/hooks/speak-notify.sh' input" },
      { type: 'command', command: '/Users/me/bin/speak-notify.sh' },
      { type: 'command', command: 'say hi' },
    ] }] } };
    await f.put('.claude/settings.json', JSON.stringify(shared));
    await installClient(f.context, 'claude-code');
    const groups = (await f.json('.claude/settings.json')).hooks.Notification;
    const theirs = [{ type: 'command', command: '/Users/me/bin/speak-notify.sh' }, { type: 'command', command: 'say hi' }];
    assert.deepEqual(groups[0].hooks, theirs);
    assert.match(groups[1].hooks[0].command, /AGENTIC_VOICE_NODE=/);

    await uninstallClient(f.context, 'claude-code');
    assert.deepEqual((await f.json('.claude/settings.json')).hooks.Notification, [{ hooks: theirs }]);
  } finally {
    await f.dispose();
  }
});

test('keeps the permissions of a replaced config file', async () => {
  const f = await fixture();
  try {
    await f.put('.codex/config.toml', 'model = "gpt"\n');
    await chmod(f.file('.codex/config.toml'), 0o600);
    await installClient(f.context, 'codex');
    assert.equal((await stat(f.file('.codex/config.toml'))).mode & 0o777, 0o600);
    await uninstallClient(f.context, 'codex');
    assert.equal((await stat(f.file('.codex/config.toml'))).mode & 0o777, 0o600);
  } finally {
    await f.dispose();
  }
});

test('leaves a config with comments unchanged and shows the entry to add', async () => {
  const f = await fixture();
  try {
    const jsonc = '{\n  // my servers\n  "mcpServers": {}\n}\n';
    await f.put('.cursor/mcp.json', jsonc);
    await assert.rejects(installClient(f.context, 'cursor'), /not plain JSON[\s\S]*Add this manually[\s\S]*"agentic-voice"/);
    assert.equal(await f.read('.cursor/mcp.json'), jsonc);
    const result = await status(f.context, 'cursor');
    assert.equal(result.installed, false);
    assert.match(result.note ?? '', /not plain JSON/);
  } finally {
    await f.dispose();
  }
});

test('warns when the agentic-voice Claude Code plugin is also enabled', async () => {
  const f = await fixture();
  try {
    await f.put('.claude/settings.json', JSON.stringify({ enabledPlugins: { 'agentic-voice@agentic-voice': true } }));
    assert.match((await status(f.context, 'claude-code')).note ?? '', /plugin is also enabled/);
  } finally {
    await f.dispose();
  }
});

test('leaves an opencode plugin it did not write alone', async () => {
  const f = await fixture();
  try {
    await f.put('.config/opencode/plugins/agentic-voice.js', 'export const mine = 1;\n');
    await assert.rejects(installClient(f.context, 'opencode'), /not written by Agentic Voice/);
    assert.equal(existsSync(f.file('.config/opencode/opencode.json')), false, 'no MCP entry from a refused install');
    assert.equal((await status(f.context, 'opencode')).installed, false);
    await uninstallClient(f.context, 'opencode');
    assert.equal(await f.read('.config/opencode/plugins/agentic-voice.js'), 'export const mine = 1;\n');
  } finally {
    await f.dispose();
  }
});
