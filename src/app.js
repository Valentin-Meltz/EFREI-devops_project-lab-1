import Fastify from 'fastify';
import { readFileSync } from 'node:fs';
import { hostname } from 'node:os';

const { version } = JSON.parse(
  readFileSync(new URL('../package.json', import.meta.url), 'utf8'),
);

export function buildApp(opts = {}) {
  const app = Fastify(opts);

  app.get('/health', async () => 'OK');

  // Release information: which version, commit, environment and pod served the request.
  // The API key value is never returned, only whether one is configured.
  app.get('/', async () => ({
    service: 'myapp',
    version,
    commit: process.env.GIT_SHA || 'unknown',
    environment: process.env.APP_ENV || 'unknown',
    apiKeyConfigured: Boolean(process.env.API_KEY),
    pod: hostname(),
  }));

  return app;
}
