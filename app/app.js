'use strict';
/**
 * Express application. Database access is injected so the routes can be
 * tested without a running MongoDB (see test/smoke.js).
 *
 *   deps.getDb()        -> a connected mongodb Db, or null while not connected
 *   deps.podName        -> HOSTNAME of the pod
 *   deps.podIp          -> pod IP address
 *   deps.version        -> application version shown in the UI
 */
const path = require('path');
const express = require('express');
const { validateInput, computeEmi } = require('./emi');

const HEALTH_TIMEOUT_MS = 2000;

function withTimeout(promise, ms, what) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${what} timed out after ${ms} ms`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function createApp(deps) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '10kb' }));
  app.use(express.urlencoded({ extended: false, limit: '10kb' }));

  const identity = () => ({ servedBy: deps.podName, podIp: deps.podIp, version: deps.version });

  // 200 only when MongoDB answers. Used by the readiness and liveness probes.
  // primaryPreferred: during a PRIMARY election a SECONDARY still answers, so
  // the web pods stay Ready instead of all dropping out of the Service at once.
  app.get('/health', async (req, res) => {
    const db = deps.getDb();
    if (!db) return res.status(503).json({ status: 'down', reason: 'not connected to MongoDB', ...identity() });
    try {
      await withTimeout(db.command({ ping: 1 }, { readPreference: 'primaryPreferred' }), HEALTH_TIMEOUT_MS, 'ping');
      return res.json({ status: 'ok', ...identity() });
    } catch (err) {
      return res.status(503).json({ status: 'down', reason: err.message, ...identity() });
    }
  });

  app.get('/api/info', (req, res) => res.json(identity()));

  app.post('/api/emi', async (req, res) => {
    const check = validateInput(req.body);
    if (!check.ok) return res.status(400).json({ error: 'invalid input', details: check.errors, ...identity() });

    const { principal, rate, months } = check.value;
    const result = computeEmi(principal, rate, months);
    const doc = {
      principal,
      rate,
      months,
      emi: result.emi,
      servedBy: deps.podName,
      createdAt: new Date(),
    };

    const db = deps.getDb();
    if (!db) return res.status(503).json({ error: 'database not connected', ...identity() });
    try {
      const ins = await db.collection('calculations').insertOne(doc);
      return res.json({
        principal, rate, months, ...result,
        id: String(ins.insertedId),
        createdAt: doc.createdAt,
        ...identity(),
      });
    } catch (err) {
      return res.status(503).json({ error: 'could not save calculation', reason: err.message, ...identity() });
    }
  });

  app.get('/api/history', async (req, res) => {
    const db = deps.getDb();
    if (!db) return res.status(503).json({ error: 'database not connected', ...identity() });
    try {
      const rows = await db.collection('calculations')
        .find({}, { projection: { _id: 0, principal: 1, rate: 1, months: 1, emi: 1, servedBy: 1, createdAt: 1 } })
        .sort({ createdAt: -1 })
        .limit(10)
        .toArray();
      return res.json(rows);
    } catch (err) {
      return res.status(503).json({ error: 'could not read history', reason: err.message, ...identity() });
    }
  });

  app.use(express.static(path.join(__dirname, 'public'), { maxAge: 0 }));

  // Malformed JSON and similar client errors.
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    const status = err.status || err.statusCode || 500;
    res.status(status).json({ error: status === 400 ? 'malformed request body' : 'internal error', ...identity() });
  });

  return app;
}

module.exports = { createApp };
