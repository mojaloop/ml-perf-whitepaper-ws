// Seed MSISDN parties into ONE mojaloop-simulator backend pod via its local
// test-api. The backend keeps parties in a per-process in-memory sqlite, so
// with >1 replica every pod must be seeded individually — this script is run
// per-pod (kubectl exec -i <pod> -c backend -- env ... node < this-file).
//
// Env:
//   SEED_BASE         first MSISDN of the sequential range
//   SEED_COUNT        how many sequential MSISDNs (0 = extras only)
//   SEED_EXTRA        comma-separated extra MSISDNs (e.g. the FSP's primary)
//   SEED_CONCURRENCY  parallel POSTs per batch (default 25)
//   SEED_PORT         backend test-api port (default 3003)
//
// Idempotent: a duplicate POST hits the party unique index and returns
// 500 ID_NOT_UNIQUE, which counts as "already seeded". Exits non-zero if any
// POST fails otherwise or the pod's party count ends below the expected set.
const http = require('http');

const BASE = Number(process.env.SEED_BASE || 0);
const COUNT = Number(process.env.SEED_COUNT || 0);
const EXTRA = (process.env.SEED_EXTRA || '').split(',').filter(Boolean);
const CONCURRENCY = Number(process.env.SEED_CONCURRENCY || 25);
const PORT = Number(process.env.SEED_PORT || 3003);

const request = (method, path, body) => new Promise((resolve, reject) => {
  const req = http.request(
    { host: '127.0.0.1', port: PORT, path, method,
      headers: { 'Content-Type': 'application/json' } },
    (res) => {
      let data = '';
      res.on('data', (d) => { data += d; });
      res.on('end', () => resolve({ status: res.statusCode, data }));
    });
  req.on('error', reject);
  req.end(body ? JSON.stringify(body) : undefined);
});

// The test-api OpenAPI schema requires ALL of displayName, firstName,
// middleName, lastName, dateOfBirth, idType, idValue.
const party = (msisdn) => ({
  idType: 'MSISDN',
  idValue: msisdn,
  displayName: `perf ${msisdn}`,
  firstName: 'perf',
  middleName: 'seed',
  lastName: msisdn,
  dateOfBirth: '1970-01-01',
});

(async () => {
  const msisdns = [...EXTRA];
  for (let i = 0; i < COUNT; i++) msisdns.push(String(BASE + i));

  let created = 0, duplicate = 0, failed = 0;
  let failureSample = null;
  for (let i = 0; i < msisdns.length; i += CONCURRENCY) {
    const batch = msisdns.slice(i, i + CONCURRENCY);
    const results = await Promise.all(
      batch.map((m) => request('POST', '/repository/parties', party(m))
        .catch((e) => ({ status: 0, data: String(e) })))
    );
    for (const r of results) {
      if (r.status === 204) created++;
      else if (r.status === 500) duplicate++; // ID_NOT_UNIQUE => already there
      else {
        failed++;
        if (!failureSample) failureSample = { status: r.status, body: String(r.data).slice(0, 300) };
      }
    }
  }

  const all = await request('GET', '/repository/parties');
  const totalInDb = JSON.parse(all.data).length;
  console.log(JSON.stringify({ created, duplicate, failed, expected: msisdns.length, totalInDb, ...(failureSample && { failureSample }) }));
  if (failed > 0 || totalInDb < msisdns.length) process.exit(1);
})().catch((e) => { console.error(e); process.exit(1); });
