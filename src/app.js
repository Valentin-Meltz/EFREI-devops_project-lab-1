import Fastify from 'fastify';

export function buildApp(opts = {}) {
  const app = Fastify(opts);

  app.get('/health', async () => 'OK');

  return app;
}
