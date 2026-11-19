'use strict';
/**
 * Entry point: reads configuration from the environment, connects to MongoDB
 * (retrying until it succeeds), serves the Express app and shuts down
 * gracefully on SIGTERM so rolling updates do not drop requests.
 *
 * Environment:
 *   MONGO_URL    (required) MongoDB connection string, database name included
 *   PORT         (default 8080)
 *   HOSTNAME     set by Kubernetes to the pod name
 *   POD_IP       injected from the Downward API (falls back to the first IPv4)
 *   APP_VERSION  baked into the image at build time
 */
const os = require('os');
const { MongoClient } = require('mongodb');
const { createApp } = require('./app');

const MONGO_URL = process.env.MONGO_URL;
if (!MONGO_URL) {
  console.error('FATAL: MONGO_URL is not set. Refusing to start.');
  process.exit(1);
}
const PORT = parseInt(process.env.PORT || '8080', 10);
const POD_NAME = process.env.HOSTNAME || os.hostname();
const VERSION = process.env.APP_VERSION || 'dev';

function firstIPv4() {
  for (const list of Object.values(os.networkInterfaces())) {
    for (const a of list || []) {
      if (a.family === 'IPv4' && !a.internal) return a.address;
    }
  }
  return '127.0.0.1';
}
const POD_IP = process.env.POD_IP || firstIPv4();

// Never log the connection string itself (it may contain credentials).
const safeUrl = MONGO_URL.replace(/\/\/[^@/]*@/, '//***@');

let client = null;
let db = null;
let stopping = false;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function connectWithRetry() {
  for (let attempt = 1; !stopping; attempt++) {
    const c = new MongoClient(MONGO_URL, {
      appName: `emi-web/${POD_NAME}`,
      serverSelectionTimeoutMS: 15000, // ride out a PRIMARY election instead of failing
      maxPoolSize: 20,
    });
    try {
      await c.connect();
      client = c;
      db = c.db(); // database name comes from the connection string (emidb)
      console.log(`connected to MongoDB ${safeUrl} (attempt ${attempt})`);
      db.collection('calculations').createIndex({ createdAt: -1 })
        .catch((e) => console.warn(`createIndex skipped: ${e.message}`));
      return;
    } catch (err) {
      console.warn(`MongoDB not reachable yet (attempt ${attempt}): ${err.message}`);
      await c.close().catch(() => {});
      await sleep(3000);
    }
  }
}

const app = createApp({ getDb: () => db, podName: POD_NAME, podIp: POD_IP, version: VERSION });
const server = app.listen(PORT, () => {
  console.log(`emi-web ${VERSION} listening on :${PORT} as ${POD_NAME} (${POD_IP})`);
});
// Keep idle connections open longer than the NGINX ingress upstream keep-alive
// (60 s); otherwise the pod can close a connection just as NGINX reuses it.
server.keepAliveTimeout = 65000;
server.headersTimeout = 66000;

connectWithRetry();

function shutdown(signal) {
  if (stopping) return;
  stopping = true;
  console.log(`${signal} received: closing HTTP server, then MongoDB`);
  setTimeout(() => process.exit(0), 25000).unref(); // hard stop before the 30 s grace period ends
  server.close(async () => {
    if (client) await client.close().catch(() => {});
    process.exit(0);
  });
  server.closeIdleConnections();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
