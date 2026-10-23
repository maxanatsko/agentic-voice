import { createServer, type Server } from 'node:net';

/**
 * Binds an exclusive loopback port as a cross-process lock. The OS releases it when the
 * holder exits, so a crashed holder never leaves a stale lock. Resolves undefined when held.
 */
export function tryBindExclusive(port: number): Promise<Server | undefined> {
  const server = createServer((socket) => socket.destroy());
  return new Promise((resolve, reject) => {
    server.once('error', (error: NodeJS.ErrnoException) => {
      if (error.code === 'EADDRINUSE') resolve(undefined);
      else reject(error);
    });
    server.listen({ host: '127.0.0.1', port, exclusive: true }, () => resolve(server));
  });
}

export function release(server: Server): Promise<void> {
  return new Promise((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
}
