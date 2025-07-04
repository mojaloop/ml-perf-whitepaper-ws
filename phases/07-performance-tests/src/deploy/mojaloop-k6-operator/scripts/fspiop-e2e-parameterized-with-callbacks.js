// fspiop-e2e-parameterized-with-callbacks.js
// K6 test with WebSocket callback validation for true end-to-end validation

import http from 'k6/http';
import { check } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';
import { WebSocket } from 'k6/experimental/websockets';
import { setTimeout, clearTimeout } from 'k6/timers';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js';
import crypto from "k6/crypto";
import { vu } from 'k6/execution';
import { randomString } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';
import exec from 'k6/execution';

// Validate environment variables
function validateEnv() {
  let isValid = true;
  const errors = [];

  const txnCount = parseInt(__ENV.TARGET_TXN_COUNT || '100000');
  if (isNaN(txnCount) || txnCount <= 0) {
    errors.push(`Invalid TARGET_TXN_COUNT: ${__ENV.TARGET_TXN_COUNT} (must be a positive integer)`);
    isValid = false;
  }

  const tps = parseInt(__ENV.TARGET_TPS || '1000');
  if (isNaN(tps) || tps <= 0) {
    errors.push(`Invalid TARGET_TPS: ${__ENV.TARGET_TPS} (must be a positive integer)`);
    isValid = false;
  }

  const validFspModes = ['2-DFSP', '4-DFSP', '4-DFSP-MIXED', 'PERF-FSP', '8-DFSP'];
  const fspMode = __ENV.FSP_MODE || '2-DFSP';
  if (!validFspModes.includes(fspMode)) {
    errors.push(`Invalid FSP_MODE: ${fspMode} (must be one of ${validFspModes.join(', ')})`);
    isValid = false;
  }


  const callbackTimeout = parseInt(__ENV.CALLBACK_TIMEOUT_MS || '10000');
  if (isNaN(callbackTimeout) || callbackTimeout <= 0) {
    errors.push(`Invalid CALLBACK_TIMEOUT_MS: ${__ENV.CALLBACK_TIMEOUT_MS} (must be a positive integer)`);
    isValid = false;
  }

  const transferAmount = __ENV.TRANSFER_AMOUNT || '100';
  if (isNaN(parseFloat(transferAmount)) || parseFloat(transferAmount) <= 0) {
    errors.push(`Invalid TRANSFER_AMOUNT: ${transferAmount} (must be a positive number)`);
    isValid = false;
  }

  const currency = __ENV.CURRENCY || 'USD';
  if (!currency.match(/^[A-Z]{3}$/)) {
    errors.push(`Invalid CURRENCY: ${currency} (must be a 3-letter ISO currency code)`);
    isValid = false;
  }

  const fspPairsJson = __ENV.FSP_PAIRS_JSON;
  errors.push(fspPairsJson);
  if (!fspPairsJson) {
    errors.push('Missing FSP_PAIRS_JSON (must be a valid JSON array of FSP pairs)');
    isValid = false;
  } else {
    try {
      const pairs = JSON.parse(fspPairsJson);
      if (!Array.isArray(pairs) || pairs.length === 0) {
        errors.push('FSP_PAIRS_JSON must be a non-empty array');
        isValid = false;
      }
      for (const pair of pairs) {
        if (!pair.source || !pair.dest || (fspMode === '8-DFSP' && !pair.weight)) {
          errors.push('Invalid FSP_PAIRS_JSON: each pair must have source, dest, and weight (for 8-DFSP)');
          isValid = false;
          break;
        }
      }
    } catch (e) {
      errors.push(`Invalid FSP_PAIRS_JSON: ${e.message}`);
      isValid = false;
    }
  }

  if (!isValid) {
    console.error('Environment variable validation failed:');
    errors.forEach(error => console.error(`- ${error}`));
    if (__ENV.K6_SCRIPT_ABORT_ON_ERROR === 'true') {
      console.error('Aborting test due to invalid environment variables');
      exec.test.abort();
    }
  } else {
    console.log('Environment variables validated successfully.');
  }
}



// Test parameters from environment
const TARGET_TXN_COUNT = parseInt(__ENV.TARGET_TXN_COUNT || '100000');
const TARGET_TPS = parseInt(__ENV.TARGET_TPS || '1000');
const FSP_MODE = __ENV.FSP_MODE || '2-DFSP';
const abortOnError = __ENV.K6_SCRIPT_ABORT_ON_ERROR === 'true' || false;

// Custom metrics
const completedTxns = new Counter('completed_transactions');
const successRate = new Rate('success_rate');
const e2eTime = new Trend('e2e_time', true);
const discoveryTime = new Trend('discovery_time', true);
const quoteTime = new Trend('quote_time', true);
const transferTime = new Trend('transfer_time', true);
const callbackTime = new Trend('callback_time', true);
const failures = new Counter('failed_transactions');

// Simple duration calculation
const testDuration = Math.ceil(TARGET_TXN_COUNT / TARGET_TPS) + 10;

export const options = {
  scenarios: {
    load_test: {
      executor: 'constant-arrival-rate',
      rate: TARGET_TPS,
      timeUnit: '1s',
      duration: testDuration + 's',
      // preAllocatedVUs: Math.max(Math.ceil(TARGET_TPS * 2), 100),
      preAllocatedVUs: 10,
      // maxVUs: Math.max(Math.ceil(TARGET_TPS * 4), 200),
      maxVUs: 20,
    },
  },
  thresholds: {
    'completed_transactions': [`count>=${TARGET_TXN_COUNT * 0.95}`],
    'success_rate': ['rate>0.95'],
    'http_req_duration': ['p(95)<5000'],
    'e2e_time': ['p(95)<15000'],
    'discovery_time': ['p(95)<3000'],
    'quote_time': ['p(95)<3000'],
    'transfer_time': ['p(95)<3000'],
    'callback_time': ['p(95)<10000'],
    'checks': ['rate>0.95'],
  },
  noConnectionReuse: true
};

// Environment configuration
const ENV = {
  ALS_ENDPOINT: __ENV.ALS_ENDPOINT || 'http://moja-account-lookup-service',
  QUOTES_ENDPOINT: __ENV.QUOTES_ENDPOINT || 'http://moja-quoting-service',
  TRANSFERS_ENDPOINT: __ENV.TRANSFERS_ENDPOINT || 'http://moja-ml-api-adapter-service',
  USE_PERF_FSP: __ENV.USE_PERF_FSP === 'true' || FSP_MODE === 'PERF-FSP',
  CALLBACK_TIMEOUT_MS: parseInt(__ENV.CALLBACK_TIMEOUT_MS || '10000'),
  TRANSFER_AMOUNT: __ENV.TRANSFER_AMOUNT || '100',
  CURRENCY: __ENV.CURRENCY || 'USD',
};

// FSP configurations with WebSocket URLs for the FSP backends
const FSPS = {
  perffsp1: { id: 'perffsp-1', msisdn: '19012345001', wsUrl: 'ws://perf-perffsp-1:3002' },
  perffsp2: { id: 'perffsp-2', msisdn: '19012345002', wsUrl: 'ws://perf-perffsp-2:3002' },
  perffsp3: { id: 'perffsp-3', msisdn: '19012345003', wsUrl: 'ws://perf-perffsp-3:3002' },
  perffsp4: { id: 'perffsp-4', msisdn: '19012345004', wsUrl: 'ws://perf-perffsp-4:3002' },
  perffsp5: { id: 'perffsp-5', msisdn: '19012345005', wsUrl: 'ws://perf-perffsp-5:3002' },
  perffsp6: { id: 'perffsp-6', msisdn: '19012345006', wsUrl: 'ws://perf-perffsp-6:3002' },
  perffsp7: { id: 'perffsp-7', msisdn: '19012345007', wsUrl: 'ws://perf-perffsp-7:3002' },
  perffsp8: { id: 'perffsp-8', msisdn: '19012345008', wsUrl: 'ws://perf-perffsp-8:3002' },
};

function getUUIDS() {
  const random = len => randomString(len, '0123456789abcdef');
  const t = Date.now().toString(16).padStart(12, '0');
  const uuid = `${t.substring(0,8)}-${t.substring(8,12)}-4${random(3)}-9${random(3)}-${random(12)}`;
  const ulid = `${t}${random(14)}`.toUpperCase();
  return { uuid, ulid };
}

function generateTraceparent() {
  const byteToHex = [];
  let prevTrace = 0;

  for (let n = 0; n <= 0xff; ++n) {
    const hexOctet = n.toString(16).padStart(2, "0");
    byteToHex.push(hexOctet);
  }

  function hex(arrayBuffer) {
    const buff = new Uint8Array(arrayBuffer);
    const hexOctets = [];
    for (let i = 0; i < buff.length; ++i) {
      hexOctets.push(byteToHex[buff[i]]);
    }
    return hexOctets.join("");
  }

  const traceId = hex(crypto.randomBytes(16));
  const parentId = hex(crypto.randomBytes(8));
  const now = Date.now();
  let traceFlags = '00';

  if (vu.idInTest === 1 && (now - prevTrace > 10000)) {
    traceFlags = '01';
    prevTrace = now;
  }

  const traceparent = `00-${traceId}-${parentId}-${traceFlags}`;
  return { traceparent, traceId };
}

function getFspiopHeaders(source, destination, resourceType) {
  return {
    'Content-Type': `application/vnd.interoperability.${resourceType}+json;version=1.1`,
    'Accept': `application/vnd.interoperability.${resourceType}+json;version=1.1`,
    'Date': new Date().toUTCString(),
    'FSPIOP-Source': source,
    'FSPIOP-Destination': destination || '',
  };
}

function selectWeightedFspPair() {
  if (FSP_MODE !== '8-DFSP') {
    return FSP_PAIRS[Math.floor(Math.random() * FSP_PAIRS.length)];
  }

  // Calculate cumulative weights for 8-DFSP mode
  const totalWeight = FSP_PAIRS.reduce((sum, pair) => sum + (pair.weight || 0), 0);
  let random = Math.random() * totalWeight;
  for (const pair of FSP_PAIRS) {
    random -= pair.weight;
    if (random <= 0) {
      return pair;
    }
  }
  return FSP_PAIRS[FSP_PAIRS.length - 1]; // Fallback to last pair
}

function executeFspiopTransactionWithCallbacks(sourceFsp, destFsp) {
  const startTime = Date.now();
  const { traceparent, traceId } = generateTraceparent();
  const wsBaseUrl = sourceFsp.wsUrl;
  const { uuid, ulid } = getUUIDS();
  const transactionId = ulid;
  const quoteId = uuid;

  let partyWs, quoteWs, transferWs;

  try {
    // Phase 1: Party Lookup with Callback
    const discoveryStartTime = Date.now();
    const partyCallbackChannel = `${traceId}/PUT/parties/MSISDN/${destFsp.msisdn}`;
    const partyWsUrl = `${wsBaseUrl}/${partyCallbackChannel}`;
    console.log(`Connecting to Party Lookup WebSocket: ${partyWsUrl}`);

    partyWs = new WebSocket(partyWsUrl, null, { tags: { name: 'party_callback_ws' } });

    partyWs.onopen = () => {
      console.log(`Getting Party: ${ENV.ALS_ENDPOINT}/parties/MSISDN/${destFsp.msisdn}`);
      const params = {
        tags: { payerFspId: sourceFsp.id, payeeFspId: destFsp.id },
        headers: {
          'Accept': 'application/vnd.interoperability.parties+json;version=1.1',
          'Content-Type': 'application/vnd.interoperability.parties+json;version=1.1',
          'FSPIOP-Source': sourceFsp.id,
          'Date': new Date().toUTCString(),
          'traceparent': traceparent,
          'tracestate': `tx_end2end_start_ts=${discoveryStartTime}`
        },
      };

      const res = http.get(`${ENV.ALS_ENDPOINT}/parties/MSISDN/${destFsp.msisdn}`, params);
      const partyCheck = check(res, { 'ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_202': (r) => r.status === 202 });

      if (!partyCheck) {
        console.error(traceId, `Party lookup failed with status: ${res.status}`);
        failures.add(1);
        successRate.add(0);
        partyWs.close();
        if (abortOnError) {
          exec.test.abort();
        }
        return;
      }

      const wsTimeoutId = setTimeout(() => {
        console.error(traceId, `WebSocket timed out on URL: ${partyWsUrl}`);
        check(null, { 'ALS_E2E_FSPIOP_GET_PARTIES_SUCCESS': () => false });
        failures.add(1);
        successRate.add(0);
        partyWs.close();
        if (abortOnError) {
          exec.test.abort();
        }
      }, ENV.CALLBACK_TIMEOUT_MS);

      partyWs.onmessage = (event) => {
        const partySuccess = check(event.data, { 'ALS_E2E_FSPIOP_GET_PARTIES_SUCCESS': (cbMessage) => cbMessage === 'SUCCESS_CALLBACK_RECEIVED' });
        clearTimeout(wsTimeoutId);
        if (partySuccess) {
          discoveryTime.add(Date.now() - discoveryStartTime);
          partyWs.close();
          executeQuotePhase();
        } else {
          failures.add(1);
          successRate.add(0);
          partyWs.close();
        }
      };

      partyWs.onclose = () => {
        clearTimeout(wsTimeoutId);
      };

      partyWs.onerror = (err) => {
        console.error(traceId, `Party WebSocket error: ${err}`);
        check(null, { 'ALS_E2E_FSPIOP_GET_PARTIES_SUCCESS': () => false });
        clearTimeout(wsTimeoutId);
        failures.add(1);
        successRate.add(0);
        partyWs.close();
      };
    };
  } catch (err) {
    console.error(traceId, `Party WebSocket initialization failed: ${err}`);
    failures.add(1);
    successRate.add(0);
    if (partyWs) partyWs.close();
    if (abortOnError) {
      exec.test.abort();
    }
    return;
  }

  function executeQuotePhase() {
    try {
      const quoteStartTime = Date.now();
      const quoteCallbackChannel = `${traceId}/PUT/quotes/${quoteId}`;
      const quoteWsUrl = `${wsBaseUrl}/${quoteCallbackChannel}`;
      console.log(`Connecting to Quote WebSocket: ${quoteWsUrl}`);

      quoteWs = new WebSocket(quoteWsUrl, null, { tags: { name: 'quote_callback_ws' } });

      quoteWs.onopen = () => {
        const params = {
          tags: { payerFspId: sourceFsp.id, payeeFspId: destFsp.id },
          headers: {
            'Accept': 'application/vnd.interoperability.quotes+json;version=1.1',
            'Content-Type': 'application/vnd.interoperability.quotes+json;version=1.1',
            'FSPIOP-Source': sourceFsp.id,
            'FSPIOP-Destination': destFsp.id,
            'Date': new Date().toUTCString(),
            'traceparent': traceparent,
            'tracestate': `tx_end2end_start_ts=${quoteStartTime}`
          },
        };

        const body = {
          quoteId,
          transactionId,
          payer: {
            partyIdInfo: { partyIdType: 'MSISDN', partyIdentifier: sourceFsp.msisdn, fspId: sourceFsp.id }
          },
          payee: {
            partyIdInfo: { partyIdType: 'MSISDN', partyIdentifier: destFsp.msisdn, fspId: destFsp.id }
          },
          amountType: 'SEND',
          amount: { amount: ENV.TRANSFER_AMOUNT, currency: ENV.CURRENCY },
          transactionType: { scenario: 'TRANSFER', initiator: 'PAYER', initiatorType: 'CONSUMER' }
        };

        const res = http.post(`${ENV.QUOTES_ENDPOINT}/quotes`, JSON.stringify(body), params);
        const quoteCheck = check(res, { 'QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_202': (r) => r.status === 202 });

        if (!quoteCheck) {
          console.error(traceId, `Quote request failed with status: ${res.status}`);
          failures.add(1);
          successRate.add(0);
          quoteWs.close();
          if (abortOnError) {
            exec.test.abort();
          }
          return;
        }

        const quoteTimeoutId = setTimeout(() => {
          console.error(traceId, `WebSocket timed out on URL: ${quoteWsUrl}`);
          check(null, { 'QUOTES_E2E_FSPIOP_POST_QUOTES_SUCCESS': () => false });
          failures.add(1);
          successRate.add(0);
          quoteWs.close();
          if (abortOnError) {
            exec.test.abort();
          }
        }, ENV.CALLBACK_TIMEOUT_MS);

        quoteWs.onmessage = (event) => {
          const quoteSuccess = check(event.data, { 'QUOTES_E2E_FSPIOP_POST_QUOTES_SUCCESS': (cbMessage) => cbMessage === 'SUCCESS_CALLBACK_RECEIVED' });
          clearTimeout(quoteTimeoutId);
          if (quoteSuccess) {
            quoteTime.add(Date.now() - quoteStartTime);
            quoteWs.close();
            executeTransferPhase();
          } else {
            failures.add(1);
            successRate.add(0);
            quoteWs.close();
          }
        };

        quoteWs.onclose = () => {
          clearTimeout(quoteTimeoutId);
        };

        quoteWs.onerror = (err) => {
          console.error(traceId, `Quote WebSocket error: ${err}`);
          check(null, { 'QUOTES_E2E_FSPIOP_POST_QUOTES_SUCCESS': () => false });
          clearTimeout(quoteTimeoutId);
          failures.add(1);
          successRate.add(0);
          quoteWs.close();
        };
      };
    } catch (err) {
      console.error(traceId, `Quote WebSocket initialization failed: ${err}`);
      failures.add(1);
      successRate.add(0);
      if (quoteWs) quoteWs.close();
      if (abortOnError) {
        exec.test.abort();
      }
    }
  }

  function executeTransferPhase() {
    try {
      const transferStartTime = Date.now();
      const transferId = transactionId;
      const transferCallbackChannel = `${traceId}/PUT/transfers/${transferId}`;
      const transferWsUrl = `${wsBaseUrl}/${transferCallbackChannel}`;
      console.log(`Connecting to Transfer WebSocket: ${transferWsUrl}`);

      transferWs = new WebSocket(transferWsUrl, null, { tags: { name: 'transfer_callback_ws' } });

      transferWs.onopen = () => {
        const params = {
          tags: { payerFspId: sourceFsp.id, payeeFspId: destFsp.id },
          headers: {
            'Accept': 'application/vnd.interoperability.transfers+json;version=1.1',
            'Content-Type': 'application/vnd.interoperability.transfers+json;version=1.1',
            'FSPIOP-Source': sourceFsp.id,
            'FSPIOP-Destination': destFsp.id,
            'Date': new Date().toUTCString(),
            'traceparent': traceparent,
            'tracestate': `tx_end2end_start_ts=${transferStartTime}`
          },
        };

        const body = {
          transferId,
          payerFsp: sourceFsp.id,
          payeeFsp: destFsp.id,
          amount: { amount: ENV.TRANSFER_AMOUNT, currency: ENV.CURRENCY },
          ilpPacket: 'DIICtgAAAAAAD0JAMjAyNDEyMDUxNjA4MDM5MDcYjF3nFyiGSaedeiWlO_87HCnJof_86Krj0lO8KjynIApnLm1vamFsb29wggJvZXlKeGRXOTBaVWxrSWpvaU1ERktSVUpUTmpsV1N6WkJSVUU0VkVkQlNrVXpXa0U1UlVnaUxDSjBjbUZ1YzJGamRHbHZia2xrSWpvaU1ERktSVUpUTmpsV1N6WkJSVUU0VkVkQlNrVXpXa0U1UlVvaUxDSjBjbUZ1YzJGamRHbHZibFI1Y0dVaU9uc2ljMk5sYm1GeWFXOGlPaUpVVWtGT1UwWkZVaUlzSW1sdWFYUnBZWFJ2Y2lJNklsQkJXVVZTSWl3aWFXNXBkR2xoZEc5eVZIbHdaU0k2SWtKVlUwbE9SVk5USW4wc0luQmhlV1ZsSWpwN0luQmhjblI1U1dSSmJtWnZJanA3SW5CaGNuUjVTV1JVZVhCbElqb2lUVk5KVTBST0lpd2ljR0Z5ZEhsSlpHVnVkR2xtYVdWeUlqb2lNamMzTVRNNE1ETTVNVElpTENKbWMzQkpaQ0k2SW5CaGVXVmxabk53SW4xOUxDSndZWGxsY2lJNmV5SndZWEowZVVsa1NXNW1ieUk2ZXlKd1lYSjBlVWxrVkhsd1pTSTZJazFUU1ZORVRpSXNJbkJoY25SNVNXUmxiblJwWm1sbGNpSTZJalEwTVRJek5EVTJOemc1SWl3aVpuTndTV1FpT2lKMFpYTjBhVzVuZEc9dmJHdHBkR1JtYzNBaWZYMHNJbVY0Y0dseVlYUnBiMjRpT2lJeU1ESTBMVEV5TFRBMVZERTJPakE0T2pBekxqa3dOMW9pTENKaGJXOTFiblFpT25zaVlXMXZkVzUwSWpvaU1UQXdJaXdpWTNWeWNtVnVZM2tpT2lKWVdGZ2lmWDA',
          condition: 'GIxd5xcohkmnnXolpTv_OxwpyaH__Oiq49JTvCo8pyA',
          expiration: new Date(Date.now() + 60000).toISOString()
        };

        const res = http.post(`${ENV.TRANSFERS_ENDPOINT}/transfers`, JSON.stringify(body), params);
        const transferCheck = check(res, { 'TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_202': (r) => r.status === 202 });

        if (!transferCheck) {
          console.error(traceId, `Transfer request failed with status: ${res.status}`);
          failures.add(1);
          successRate.add(0);
          transferWs.close();
          if (abortOnError) {
            exec.test.abort();
          }
          return;
        }

        const transferTimeoutId = setTimeout(() => {
          console.error(traceId, `WebSocket timed out on URL: ${transferWsUrl}`);
          check(null, { 'TRANSFERS_E2E_FSPIOP_POST_TRANSFERS_SUCCESS': () => false });
          failures.add(1);
          successRate.add(0);
          transferWs.close();
          if (abortOnError) {
            exec.test.abort();
          }
        }, ENV.CALLBACK_TIMEOUT_MS);

        transferWs.onmessage = (event) => {
          const transferSuccess = check(event.data, { 'TRANSFERS_E2E_FSPIOP_POST_TRANSFERS_SUCCESS': (cbMessage) => cbMessage === 'SUCCESS_CALLBACK_RECEIVED' });
          clearTimeout(transferTimeoutId);
          if (transferSuccess) {
            transferTime.add(Date.now() - transferStartTime);
            callbackTime.add(Date.now() - startTime);
            e2eTime.add(Date.now() - startTime);
            successRate.add(1);
            completedTxns.add(1);
            transferWs.close();
          } else {
            failures.add(1);
            successRate.add(0);
            transferWs.close();
          }
        };

        transferWs.onclose = () => {
          clearTimeout(transferTimeoutId);
        };

        transferWs.onerror = (err) => {
          console.error(traceId, `Transfer WebSocket error: ${err}`);
          check(null, { 'TRANSFERS_E2E_FSPIOP_POST_TRANSFERS_SUCCESS': () => false });
          clearTimeout(transferTimeoutId);
          failures.add(1);
          successRate.add(0);
          transferWs.close();
        };
      };
    } catch (err) {
      console.error(traceId, `Transfer WebSocket initialization failed: ${err}`);
      failures.add(1);
      successRate.add(0);
      if (transferWs) transferWs.close();
      if (abortOnError) {
        exec.test.abort();
      }
    }
  }
}

let FSP_PAIRS = []; 

export default function() {
  validateEnv();

  if (FSP_PAIRS.length === 0) {
    FSP_PAIRS = JSON.parse(__ENV.FSP_PAIRS_JSON).map(pair => ({
      source: FSPS[pair.source],
      dest: FSPS[pair.dest],
      weight: pair.weight,
    }));
  }

  const pair = selectWeightedFspPair();
  executeFspiopTransactionWithCallbacks(pair.source, pair.dest);
}

export function handleSummary(data) {
  const completed = (
    data.metrics &&
    data.metrics.completed_transactions &&
    data.metrics.completed_transactions.values &&
    data.metrics.completed_transactions.values.count
  ) || 0;

  const successRateValue = (
    data.metrics &&
    data.metrics.success_rate &&
    data.metrics.success_rate.values &&
    data.metrics.success_rate.values.rate
  ) || 0;

  const actualTPS = completed / testDuration;

  const customSummary = {
    test_config: {
      target_transactions: TARGET_TXN_COUNT,
      target_tps: TARGET_TPS,
      fsp_mode: FSP_MODE,
      duration: testDuration,
      fsp_pairs: JSON.parse(__ENV.FSP_PAIRS_JSON),
    },
    results: {
      completed_transactions: completed,
      success_rate: successRateValue * 100,
      actual_tps: actualTPS,
      e2e_time_p95: (
        data.metrics &&
        data.metrics.e2e_time &&
        data.metrics.e2e_time.values &&
        data.metrics.e2e_time.values['p(95)']
      ) || 0,
      callback_time_p95: (
        data.metrics &&
        data.metrics.callback_time &&
        data.metrics.callback_time.values &&
        data.metrics.callback_time.values['p(95)']
      ) || 0,
      http_req_duration_p95: (
        data.metrics &&
        data.metrics.http_req_duration &&
        data.metrics.http_req_duration.values &&
        data.metrics.http_req_duration.values['p(95)']
      ) || 0,
    },
    status: completed >= TARGET_TXN_COUNT * 0.95 ? 'PASSED' : 'FAILED',
  };

  const k6Summary = textSummary(data, { indent: ' ', enableColors: false });
  console.log('\n=== WS-PERF CALLBACK SUMMARY ===');
  console.log(JSON.stringify(customSummary, null, 2));

  return {
    'stdout': k6Summary + '\n\n=== WS-PERF CALLBACK SUMMARY ===\n' + JSON.stringify(customSummary, null, 2) + '\n',
  };
}
