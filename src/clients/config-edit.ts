/** Pure text edits for client config files. Callers own reading, backups and writing. */

import { isDeepStrictEqual } from 'node:util';

type JsonObject = Record<string, unknown>;

const TOML_BEGIN = '# >>> agentic-voice (managed by Agentic Voice; edits inside this block are replaced)';
const TOML_END = '# <<< agentic-voice';

function isObject(value: unknown): value is JsonObject {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function parseObject(text: string, path: string, snippet: unknown): JsonObject {
  if (!text.trim()) return {};
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`${path} is not plain JSON (it may contain comments), so it was left unchanged. Add this manually:\n${JSON.stringify(snippet, null, 2)}`);
  }
  if (!isObject(parsed)) throw new Error(`${path} does not contain a JSON object, so it was left unchanged.`);
  return parsed;
}

function render(value: JsonObject): string {
  return `${JSON.stringify(value, null, 2)}\n`;
}

export function readJsonEntry(text: string, path: string, container: string, name: string): unknown {
  const root = parseObject(text, path, {});
  const servers = root[container];
  return isObject(servers) ? servers[name] : undefined;
}

export function upsertJsonEntry(text: string, path: string, container: string, name: string, entry: unknown): string {
  const root = parseObject(text, path, { [container]: { [name]: entry } });
  const servers = isObject(root[container]) ? root[container] : {};
  return render({ ...root, [container]: { ...servers, [name]: entry } });
}

export function removeJsonEntry(text: string, path: string, container: string, name: string): string {
  const root = parseObject(text, path, {});
  const servers = root[container];
  if (!isObject(servers) || !(name in servers)) return text;
  const { [name]: _removed, ...rest } = servers;
  return render({ ...root, [container]: rest });
}

/** Ours is a hook in the shape the installer writes: AGENTIC_VOICE_NODE=… …/hooks/speak-notify.sh. */
function isOurHook(hook: unknown): boolean {
  return isObject(hook) && typeof hook.command === 'string' &&
    hook.command.startsWith('AGENTIC_VOICE_NODE=') && hook.command.includes('/hooks/speak-notify.sh');
}

function hookGroups(root: JsonObject, event: string): unknown[] {
  const hooks = isObject(root.hooks) ? root.hooks : {};
  return Array.isArray(hooks[event]) ? hooks[event] : [];
}

/** Drops our hooks from every group, and any group left empty, keeping other commands. */
function withoutOurHooks(groups: unknown[]): unknown[] {
  return groups.flatMap((group) => {
    if (!isObject(group) || !Array.isArray(group.hooks) || !group.hooks.some(isOurHook)) return [group];
    const kept = group.hooks.filter((hook) => !isOurHook(hook));
    return kept.length ? [{ ...group, hooks: kept }] : [];
  });
}

export function readHookCommand(text: string, path: string, event: string): string | undefined {
  for (const group of hookGroups(parseObject(text, path, {}), event)) {
    const hook = isObject(group) && Array.isArray(group.hooks) ? group.hooks.find(isOurHook) : undefined;
    if (isObject(hook)) return hook.command as string;
  }
  return undefined;
}

export function upsertHook(text: string, path: string, event: string, command: string): string {
  const group = { hooks: [{ type: 'command', command, timeout: 10 }] };
  const root = parseObject(text, path, { hooks: { [event]: [group] } });
  const hooks = isObject(root.hooks) ? root.hooks : {};
  return render({ ...root, hooks: { ...hooks, [event]: [...withoutOurHooks(hookGroups(root, event)), group] } });
}

export function removeHook(text: string, path: string, event: string): string {
  const root = parseObject(text, path, {});
  const groups = hookGroups(root, event);
  const kept = withoutOurHooks(groups);
  if (isDeepStrictEqual(kept, groups)) return text;
  const hooks = isObject(root.hooks) ? root.hooks : {};
  const { [event]: _removed, ...otherEvents } = hooks;
  const remaining = kept.length ? { ...otherEvents, [event]: kept } : otherEvents;
  const { hooks: _hooks, ...withoutHooks } = root;
  return render(Object.keys(remaining).length ? { ...root, hooks: remaining } : withoutHooks);
}

/** A dotted TOML key without spacing or quotes: ` a . "b" ` → ['a', 'b']. */
function keyPath(key: string): string[] {
  return key.split('.').map((part) => part.trim().replace(/^(["'])(.*)\1$/, '$2'));
}

/**
 * True when the text defines the table as a header, dotted key or inline-table key, however quoted.
 * Tracks the current table so a same-named key elsewhere (such as [marketplaces.agentic-voice]) is not a match.
 */
function definesTomlTable(text: string, table: string): boolean {
  const target = keyPath(table);
  let current: string[] = [];
  for (const line of text.split('\n')) {
    const code = line.replace(/#.*$/, '').trim();
    const header = /^\[\[?([^[\]]+)\]\]?$/.exec(code);
    const assignment = /^([^=]+)=(.*)$/.exec(code);
    let path: string[];
    let value = '';
    if (header) path = current = keyPath(header[1]!);
    else if (assignment) [path, value] = [[...current, ...keyPath(assignment[1]!)], assignment[2]!];
    else continue;
    if (target.every((part, index) => path[index] === part)) return true;
    // An inline table one level up, such as mcp_servers = { agentic-voice = { … } }.
    if (path.length === target.length - 1 && path.every((part, index) => target[index] === part) &&
      new RegExp(`[{,]\\s*["']?${target.at(-1)}["']?\\s*[.=]`).test(value)) return true;
  }
  return false;
}

function tomlBlockRange(text: string): [number, number] | undefined {
  const begin = text.indexOf(TOML_BEGIN);
  if (begin < 0) return undefined;
  const end = text.indexOf(TOML_END, begin);
  if (end < 0) throw new Error(`Found the start of the agentic-voice block without its end marker '${TOML_END}'; fix the file manually.`);
  return [begin, end + TOML_END.length];
}

export function readTomlBlock(text: string): string | undefined {
  const range = tomlBlockRange(text);
  return range && text.slice(...range);
}

export function tomlBlock(table: string, body: string): string {
  return `${TOML_BEGIN}\n[${table}]\n${body}${TOML_END}`;
}

/** Appends a managed block; a table at the end of a TOML file is always valid. */
export function upsertTomlBlock(text: string, path: string, table: string, body: string): string {
  const stripped = removeTomlBlock(text);
  const key = table.split('.').at(-1)!;
  if (definesTomlTable(stripped, table)) {
    throw new Error(`${path} already defines ${key} outside the agentic-voice block (for example [${table}]); remove it, then install again.`);
  }
  const base = stripped.trimEnd();
  return `${base ? `${base}\n\n` : ''}${tomlBlock(table, body)}\n`;
}

export function removeTomlBlock(text: string): string {
  const range = tomlBlockRange(text);
  if (!range) return text;
  const kept = [text.slice(0, range[0]).trimEnd(), text.slice(range[1]).trim()].filter(Boolean).join('\n\n');
  return kept ? `${kept}\n` : '';
}

export function tomlString(value: string): string {
  return JSON.stringify(value); // JSON string escapes are valid TOML basic-string escapes.
}
