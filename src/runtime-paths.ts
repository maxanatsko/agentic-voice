import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// Source files live in src/; compiled files live in dist/src/.
const sourceRoot = new URL('../', import.meta.url);
export const pluginRoot = fileURLToPath(
  existsSync(new URL('package.json', sourceRoot)) ? sourceRoot : new URL('../../', import.meta.url),
);
