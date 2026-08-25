import { fileURLToPath } from "node:url";
import path from "node:path";

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "hooks", "speak-notify.sh");

export const server = async ({ $ }) => {
  const notify = async (reason) => {
    await $`${SCRIPT} ${reason}`.quiet().nothrow();
  };
  return {
    event: async ({ event }) => {
      if (event.type === "session.idle") await notify("finished");
    },
    "permission.ask": async () => {
      await notify("input");
    },
  };
};
