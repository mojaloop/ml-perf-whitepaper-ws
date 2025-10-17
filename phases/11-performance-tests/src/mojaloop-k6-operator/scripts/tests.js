/*****
 License
 --------------
 Copyright © 2020-2025 Mojaloop Foundation
 The Mojaloop files are made available by the Mojaloop Foundation under the Apache License, Version 2.0 (the "License") and you may not use these files except in compliance with the License. You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, the Mojaloop files are distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

 Contributors
 --------------
 This is the official list of the Mojaloop project contributors for this file.
 Names of the original copyright holders (individuals or organizations)
 should be listed with a '*' in the first column. People who have
 contributed from an organization can be listed under the organization
 that actually holds the copyright for their contributions (see the
 Mojaloop Foundation for an example). Those individuals should have
 their names indented and be marked with a '-'. Email address can be added
 optionally within square brackets <email>.

 * Mojaloop Foundation
 - Name Surname <name.surname@mojaloop.io>

 * Shashikant Hirugade <shashi.mojaloop@gmail.com>

 --------------
 ******/

import http from 'k6/http';
import { check } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js';
import crypto from "k6/crypto";
import { vu } from 'k6/execution';
import { randomString } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';
import exec from 'k6/execution';

// Validate environment variables
function validateEnv() {
  let isValid = true;
  const errors = [];

  const txnCount = parseInt(__ENV.TARGET_TXN_COUNT || '100');
  if (isNaN(txnCount) || txnCount <= 0) {
    errors.push(`Invalid TARGET_TXN_COUNT: ${__ENV.TARGET_TXN_COUNT} (must be a positive integer)`);
    isValid = false;
  }

  const tps = parseInt(__ENV.TARGET_TPS || '10');
  if (isNaN(tps) || tps <= 0) {
    errors.push(`Invalid TARGET_TPS: ${__ENV.TARGET_TPS} (must be a positive integer)`);
    isValid = false;
  }

  const transferAmount = __ENV.TRANSFER_AMOUNT || '1';
  if (isNaN(parseFloat(transferAmount)) || parseFloat(transferAmount) <= 0) {
    errors.push(`Invalid TRANSFER_AMOUNT: ${transferAmount} (must be a positive number)`);
    isValid = false;
  }

  const currency = __ENV.CURRENCY || 'XXX';
  if (!currency.match(/^[A-Z]{3}$/)) {
    errors.push(`Invalid CURRENCY: ${currency} (must be a 3-letter ISO currency code)`);
    isValid = false;
  }

  const fspPairsJson = __ENV.FSP_PAIRS_JSON;
  // errors.push(fspPairsJson);
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
        if (!pair.source || !pair.dest || !pair.weight) {
          errors.push('Invalid FSP_PAIRS_JSON: each pair must have source, dest, and weight');
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
  }
}


// Custom metrics
const completedTxns = new Counter('completed_transactions');
const successRate = new Rate('success_rate');
const e2eTime = new Trend('e2e_time', true);
const discoveryTime = new Trend('discovery_time', true);
const quoteTime = new Trend('quote_time', true);
const transferTime = new Trend('transfer_time', true);
const failures = new Counter('failed_transactions');



// Test parameters from environment
const TARGET_TXN_COUNT = parseInt(__ENV.TARGET_TXN_COUNT || '100');
// TODO: for large scale tests uncomment below line and comment above line since the Math.ceil calculation gives weird results
// const TARGET_TXN_COUNT = 1000000//parseInt(__ENV.TARGET_TXN_COUNT || '100');

const TARGET_TPS = parseInt(__ENV.TARGET_TPS || '10');
const abortOnError = __ENV.K6_SCRIPT_ABORT_ON_ERROR === 'true' || false;
// Environment configuration
const ENV = {
  TRANSFER_AMOUNT: __ENV.TRANSFER_AMOUNT || '1',
  CURRENCY: __ENV.CURRENCY || 'XXX',
  FSP_CONFIG: JSON.parse(__ENV.FSP_CONFIG || '[]'),
};


// Simple duration calculation
const testDuration = Math.ceil(TARGET_TXN_COUNT / TARGET_TPS);

export const options = {
  scenarios: {
    load_test: {
      executor: 'constant-arrival-rate',
      rate: TARGET_TPS,
      timeUnit: '1s',
      duration: testDuration + 's',
      // preAllocatedVUs: Math.max(Math.ceil(TARGET_TPS * 2), 100),
      preAllocatedVUs: 3000,
      // maxVUs: Math.max(Math.ceil(TARGET_TPS * 4), 200),
      maxVUs: 8000,
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
    'checks': ['rate>0.95'],
  },
  noConnectionReuse: true
};

function getUUIDS() {
  const random = len => randomString(len, '0123456789abcdef');
  const t = Date.now().toString(16).padStart(12, '0');
  // const uuid = `${t.substring(0,8)}-${t.substring(8,12)}-4${random(3)}-9${random(3)}-${random(12)}`;
  const ulid = `${t}${random(14)}`.toUpperCase();
  // return { uuid, ulid };
  return ulid;
}

function requestId() {
  const random = len => randomString(len, '0123456789abcdef');
  const t = Date.now().toString(16).padStart(12, '0');
  return `${t.substring(0,8)}-${t.substring(8,12)}-4${random(3)}-9${random(3)}-${random(12)}`;
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

function selectWeightedFspPair() {
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

function executeDiscoveryPhase(sourceFsp, destFsp) {
  const startTime = Date.now();
  const { traceparent, traceId } = generateTraceparent();
  const transactionId = getUUIDS();
  const quoteId = getUUIDS();
  let quoteResponse;


  try {
    // Phase 1: Party Lookup with Callback
    const discoveryStartTime = Date.now();
    // Pick random MSISDN between startMsisdn and endMsisdn or use fixed msisdn
    // TODO: improve the logic to use either of startMsisdn or msisdn
    if (destFsp.startMsisdn != destFsp.endMsisdn) {
      const min = parseInt(destFsp.startMsisdn);
      const max = parseInt(destFsp.endMsisdn);
      const randomMsisdn = Math.floor(Math.random() * (max - min + 1)) + min;
      destFsp.msisdn = randomMsisdn.toString();
    }

    const alsEndpoint = `${sourceFsp.baseUrl}/parties/MSISDN/${destFsp.msisdn}`;
    // console.log(`Getting Party: ${alsEndpoint} traceparent=${traceparent}`);

    const params = {
      tags: { payerFspId: sourceFsp.id, payeeFspId: destFsp.id },
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'FSPIOP-Source': sourceFsp.id,
        'Date': new Date().toUTCString(),
        'traceparent': traceparent,
        'tracestate': `tx_end2end_start_ts=${discoveryStartTime}`,
        'x-request-id': requestId()
      },
    };



    const partyResponse = http.get(alsEndpoint, params);
    const partyCheck = check(partyResponse, { 'ALS_FSPIOP_GET_PARTIES_RESPONSE_IS_200': (r) => r.status === 200 });
    // console.log(`[${new Date().toISOString()}] Party Lookup for ${destFsp.msisdn} time: ${Date.now() - discoveryStartTime} traceparent=${traceparent}`);
    if (!partyCheck) {
      console.error(traceId, `traceparent=${traceparent} Party lookup failed with response: ${JSON.stringify(partyResponse)}`);
      failures.add(1);
      successRate.add(0);
      if (abortOnError) {
        exec.test.abort();
      }
      return;
    } else {
      discoveryTime.add(Date.now() - discoveryStartTime);
      // console.log(`[${new Date().toISOString()}] Party Lookup for ${destFsp.msisdn} time: ${Date.now() - discoveryStartTime} traceparent=${traceparent}`);
      executeQuotePhase();
    }
    } catch (err) {
    console.error(traceId, `Party lookup failed: ${err}`);
    failures.add(1);
    successRate.add(0);
    if (abortOnError) {
      exec.test.abort();
    }
    return;
  }

  // Quoting Phase
  function executeQuotePhase() {
    try {
      const quoteStartTime = Date.now();
      const quotesEndpoint = `${sourceFsp.baseUrl}/quotes`;

      const params = {
        tags: { payerFspId: sourceFsp.id, payeeFspId: destFsp.id },
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'FSPIOP-Source': sourceFsp.id,
          'FSPIOP-Destination': destFsp.id,
          'Date': new Date().toUTCString(),
          'traceparent': traceparent,
          'tracestate': `tx_end2end_start_ts=${quoteStartTime}`
        },
      };
      const body = {
        fspId: destFsp.id,
        quotesPostRequest: {
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
        }
      };
      // console.log(`Initiating Quote: ${quotesEndpoint}: ${body.quotesPostRequest.quoteId}`);
      quoteResponse = http.post(quotesEndpoint, JSON.stringify(body), params);
      const quoteCheck = check(quoteResponse, { 'QUOTES_FSPIOP_POST_QUOTES_RESPONSE_IS_200': (r) => r.status === 200 });
      // console.log(`Quote Response: ${JSON.stringify(quoteResponse.json())}`);
      
      if (!quoteCheck) {
        console.error(traceId, `Quote request failed with response: ${JSON.stringify(quoteResponse)}`);
        // console.log(`[${new Date().toISOString()}] QuoteId : ${body.quotesPostRequest.quoteId} time: ${Date.now() - quoteStartTime}, status: fail`);
        failures.add(1);
        successRate.add(0);
        if (abortOnError) {
          exec.test.abort();
        }
        return;
      } else {
        // console.log(`[${new Date().toISOString()}] QuoteId : ${body.quotesPostRequest.quoteId} time: ${Date.now() - quoteStartTime}, status: success`);
        quoteTime.add(Date.now() - quoteStartTime);
        executeTransferPhase();

      }
    } catch (err) {
      console.error(traceId, `Quote Phase Failed: ${err}`);
      failures.add(1);
      successRate.add(0);
      if (abortOnError) {
        exec.test.abort();
      }
    }
  }

  // Transfer Phase
  function executeTransferPhase() {
    try {
      const transferStartTime = Date.now();
      const transferId = transactionId;

      const transfersEndpoint = `${sourceFsp.baseUrl}/simpleTransfers`;
      // console.log(`Initiating Transfer: ${transfersEndpoint} with transferId: ${transferId}`);
      const params = {
        tags: { payerFspId: sourceFsp.id, payeeFspId: destFsp.id },
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'FSPIOP-Source': sourceFsp.id,
          'FSPIOP-Destination': destFsp.id,
          'Date': new Date().toUTCString(),
          'traceparent': traceparent,
          'tracestate': `tx_end2end_start_ts=${transferStartTime}`
        },
      };

      const quoteResponseBody = quoteResponse.json();

      const body = {
        fspId: destFsp.id,
        transfersPostRequest: {
          transferId,
          payerFsp: sourceFsp.id,
          payeeFsp: destFsp.id,
          amount: { amount: ENV.TRANSFER_AMOUNT, currency: ENV.CURRENCY },
          ilpPacket: quoteResponseBody.quotes.body.ilpPacket,
          condition: quoteResponseBody.quotes.body.condition,
          expiration: new Date(Date.now() + 60000).toISOString()
        }
      };

      // console.log(`Transfer Request Body: ${JSON.stringify(body)}`);
      // console.log(`[${new Date().toISOString()}] TransferId : ${transferId} started`);

      const transferResponse = http.post(transfersEndpoint, JSON.stringify(body), params);
      const transferCheck = check(transferResponse, { 'TRANSFERS_FSPIOP_POST_TRANSFERS_RESPONSE_IS_200': (r) => r.status === 200 });

      // console.log(`Transfer Response: ${JSON.stringify(transferResponse.json())}`);

      if (!transferCheck) {
        console.error(traceId, `Transfer request ${transferId} failed with response: ${JSON.stringify(transferResponse)}`);
        // console.log(`[${new Date().toISOString()}] TransferId : ${transferId} time: ${Date.now() - transferStartTime} status: fail`);
        failures.add(1);
        successRate.add(0);
        if (abortOnError) {
          exec.test.abort();
        }
        return;
      } else {
        // console.log(`[${new Date().toISOString()}] TransferId : ${transferId} time: ${Date.now() - transferStartTime} status: sucess`);
        transferTime.add(Date.now() - transferStartTime);
        // console.log(`[${new Date().toISOString()}] TransferId : ${transferId} took: ${Date.now() - transferStartTime} ms`);
        e2eTime.add(Date.now() - startTime);
        successRate.add(1);
        completedTxns.add(1);
      }

    } catch (err) {
      console.error(traceId, `Transfer Phase failed: ${err}`);
      failures.add(1);
      successRate.add(0);
      if (abortOnError) {
        exec.test.abort();
      }
    }
  }
}

let FSP_PAIRS = []; 

export default function() {
  validateEnv();
  const FSP_CONFIG = JSON.parse(__ENV.FSP_CONFIG);
  FSP_PAIRS = JSON.parse(__ENV.FSP_PAIRS_JSON).map(pair => ({
    source: FSP_CONFIG[pair.source],
    dest: FSP_CONFIG[pair.dest],
    weight: pair.weight,
  }));
  
  const pair = selectWeightedFspPair();
  executeDiscoveryPhase(pair.source, pair.dest);
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
  console.log('\n=== K6 TEST SUMMARY ===');
  console.log(JSON.stringify(customSummary, null, 2));

  return {
    'stdout': k6Summary + '\n\n=== K6 TEST SUMMARY ===\n' + JSON.stringify(customSummary, null, 2) + '\n',
  };
}
