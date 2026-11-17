import { buildApp } from './app.js';

const port = Number(process.env.PORT) || 3000;
const host = process.env.HOST || '0.0.0.0';

const app = buildApp({ logger: true });

// Graceful shutdown: Node.js running as PID 1 ignores SIGTERM unless a handler
// is installed, so `docker stop` and Kubernetes pod termination would otherwise
// wait for the full grace period before killing the process.
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.once(signal, async () => {
    app.log.info({ signal }, 'shutting down');
    await app.close();
    process.exit(0);
  });
}

try {
  await app.listen({ port, host });
} catch (err) {
  app.log.error(err);
  process.exit(1);
}
