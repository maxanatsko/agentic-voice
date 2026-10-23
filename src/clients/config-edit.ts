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

/** Ours is the hook whose command runs speak-notify.sh. */
function isOurHook(hook: unknown): boolean {
  return isObject(hook) && typeof hook.command === 'string' && hook.command.includes('speak-notify.sh');
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
  return render({ ...root, hooks: kept.length ? { ...otherEvents, [event]: kept } : otherEvents });
}

/** Normalizes a TOML table header line to its dotted key, so quoting, spacing and comments compare equal. */
function tomlTableName(line: string): string | undefined {
  const header = /^\s*\[([^\[\]]+)\]\s*(#.*)?$/.exec(line);
  return header?.[1]!.split('.').map((part) => part.trim().replace(/^(["'])(.*)\1$/, '$2')).join('.');
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
  if (stripped.split('\n').some((line) => tomlTableName(line) === table)) {
    throw new Error(`${path} already defines [${table}] outside the agentic-voice block; remove it, then install again.`);
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
