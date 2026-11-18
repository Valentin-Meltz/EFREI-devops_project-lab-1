import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildApp } from '../src/app.js';

const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

// Sets environment variables for the duration of an async call, then restores them.
async function withEnv(vars, fn) {
  const saved = Object.fromEntries(Object.keys(vars).map((k) => [k, process.env[k]]));
  Object.assign(process.env, vars);
  try {
    return await fn();
  } finally {
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  }
}

test('GET / returns release information as JSON', async (t) => {
  const app = buildApp();
  t.after(() => app.close());

  const res = await withEnv(
    { GIT_SHA: 'abc123', APP_ENV: 'test', API_KEY: 'fake-key' },
    () => app.inject({ method: 'GET', url: '/' }),
  );

  assert.equal(res.statusCode, 200);
  assert.match(res.headers['content-type'], /^application\/json/);
  const body = res.json();
  assert.equal(body.service, 'myapp');
  assert.equal(body.version, pkg.version);
  assert.equal(body.commit, 'abc123');
  assert.equal(body.environment, 'test');
  assert.equal(body.apiKeyConfigured, true);
  assert.equal(typeof body.pod, 'string');
});

test('GET / never exposes the API key value', async (t) => {
  const app = buildApp();
  t.after(() => app.close());

  const res = await withEnv({ API_KEY: 'super-secret-value' }, () =>
    app.inject({ method: 'GET', url: '/' }),
  );

  assert.ok(!res.body.includes('super-secret-value'));
});
