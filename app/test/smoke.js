'use strict';
// Route tests against an in-memory stand-in for MongoDB (the real database is
// exercised on the cluster). Covers every endpoint the assignment specifies.
const assert = require('assert');
const { createApp } = require('../app');

function fakeDb({ pingFails = false } = {}) {
  const docs = [];
  const coll = {
    insertOne: async (d) => { docs.push({ ...d }); return { insertedId: 'id' + docs.length }; },
    createIndex: async () => 'createdAt_-1',
    find: (q, opts) => {
      let out = docs.slice();
      const cursor = {
        sort: (s) => { const k = Object.keys(s)[0]; out.sort((a, b) => (a[k] < b[k] ? 1 : -1) * (s[k] === -1 ? 1 : -1)); return cursor; },
        limit: (n) => { out = out.slice(0, n); return cursor; },
        toArray: async () => out.map((d) => { const o = {}; for (const k of Object.keys(opts.projection)) if (opts.projection[k] && k in d) o[k] = d[k]; return o; }),
      };
      return cursor;
    },
  };
  return { docs, command: async () => { if (pingFails) throw new Error('no reachable servers'); return { ok: 1 }; }, collection: () => coll };
}

async function main() {
  const db = fakeDb();
  let current = null;
  const app = createApp({ getDb: () => current, podName: 'emi-web-test', podIp: '10.0.0.9', version: '1.0' });
  const server = app.listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  const post = (body, type = 'application/json') => fetch(base + '/api/emi', {
    method: 'POST', headers: { 'Content-Type': type }, body: type === 'application/json' ? JSON.stringify(body) : body,
  });

  // Not connected yet -> health 503, writes 503
  assert.strictEqual((await fetch(base + '/health')).status, 503);
  assert.strictEqual((await post({ principal: 1, rate: 1, months: 1 })).status, 503);

  current = db;
  let res = await fetch(base + '/health');
  assert.strictEqual(res.status, 200);
  assert.strictEqual((await res.json()).servedBy, 'emi-web-test');

  res = await post({ principal: 500000, rate: 12, months: 24 });
  assert.strictEqual(res.status, 200);
  const body = await res.json();
  assert.strictEqual(body.emi, 23536.74);
  assert.strictEqual(body.totalPayment, 564881.67);
  assert.strictEqual(body.totalInterest, 64881.67);
  assert.strictEqual(body.servedBy, 'emi-web-test');
  assert.strictEqual(body.podIp, '10.0.0.9');
  const saved = db.docs[0];
  assert.deepStrictEqual(Object.keys(saved).sort(), ['createdAt', 'emi', 'months', 'principal', 'rate', 'servedBy']);

  // form-encoded body (used by the httperf load test)
  res = await post('principal=250000&rate=9.5&months=36', 'application/x-www-form-urlencoded');
  assert.strictEqual(res.status, 200);

  // server-side validation
  res = await post({ principal: -5, rate: 12, months: 24 });
  assert.strictEqual(res.status, 400);
  assert.ok((await res.json()).details.length >= 1);
  res = await fetch(base + '/api/emi', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{bad json' });
  assert.strictEqual(res.status, 400);

  // history: newest first, max 10
  for (let i = 0; i < 12; i++) { await post({ principal: 1000 + i, rate: 10, months: 12 }); await new Promise((r) => setTimeout(r, 2)); }
  const hist = await (await fetch(base + '/api/history')).json();
  assert.strictEqual(hist.length, 10);
  assert.strictEqual(hist[0].principal, 1011);
  assert.ok(!('_id' in hist[0]));

  // static UI
  res = await fetch(base + '/');
  assert.strictEqual(res.status, 200);
  assert.ok((await res.text()).includes('Loan EMI Calculator'));

  // ping failure -> 503
  current = fakeDb({ pingFails: true });
  assert.strictEqual((await fetch(base + '/health')).status, 503);

  server.close();
  console.log('smoke tests passed');
}
main().catch((e) => { console.error(e); process.exit(1); });
