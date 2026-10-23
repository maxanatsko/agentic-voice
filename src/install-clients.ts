import { homedir } from 'node:os';
import { clientIds, installClient, status, uninstallClient, type ClientId, type ClientStatus } from './clients/clients.js';
import { pluginRoot } from './runtime-paths.js';

const usage = `usage: install-clients <status|install|uninstall> [client...]\nclients: ${clientIds.join(', ')}`;

function parseClients(values: string[]): ClientId[] {
  for (const value of values) {
    if (!clientIds.includes(value as ClientId)) throw new Error(`Unknown client '${value}'.\n${usage}`);
  }
  return values.length ? values as ClientId[] : [...clientIds];
}

/** Prints one JSON status per client on stdout; failures carry an error and set the exit code. */
async function main(): Promise<void> {
  const [command, ...rest] = process.argv.slice(2);
  const actions = { status: undefined, install: installClient, uninstall: uninstallClient };
  if (!command || !(command in actions)) throw new Error(usage);
  const action = actions[command as keyof typeof actions];
  if (action && rest.length === 0) throw new Error(`Name the clients to ${command}.\n${usage}`);

  const context = { home: homedir(), node: process.execPath, root: pluginRoot };
  const results: (ClientStatus & { error?: string })[] = [];
  for (const id of parseClients(rest)) {
    let error: string | undefined;
    try {
      await action?.(context, id);
    } catch (failure) {
      error = failure instanceof Error ? failure.message : String(failure);
      process.exitCode = 1;
    }
    results.push({ ...await status(context, id), ...(error ? { error } : {}) });
  }
  console.log(JSON.stringify(results, null, 2));
}

main().catch((error: unknown) => {
  console.error(`agentic-voice: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
});
