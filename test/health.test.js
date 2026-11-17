import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';

test('GET /health returns 200 OK', async (t) => {
  const app = buildApp();
  t.after(() => app.close());

  const res = await app.inject({ method: 'GET', url: '/health' });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body, 'OK');
});
