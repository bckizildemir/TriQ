#!/usr/bin/env node
/**
 * Backfills explicit release-announcement state for legacy categories/questions.
 *
 * Questions:
 * - sets `isAnnounced = true` when the field is missing
 * - sets `source = "seeded"` when the field is missing
 *
 * Categories:
 * - sets `isAnnounced = true` when the field is missing
 *
 * Usage:
 *   node backfill_release_announcement_state.js
 *   node backfill_release_announcement_state.js --dry-run
 */

const fs = require('fs');
const https = require('https');
const os = require('os');
const path = require('path');

const FIREBASE_TOOLS_CONFIG = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
const PROJECT_ID = 'ttbp-9d652';
const PROJECT_HOST = 'firestore.googleapis.com';
const DB_PATH = `/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

const args = process.argv.slice(2);
const isDryRun = args.includes('--dry-run');

function httpsRequest(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

async function getAccessToken() {
  if (!fs.existsSync(FIREBASE_TOOLS_CONFIG)) {
    console.error('❌  Firebase CLI config not found. Run: firebase login');
    process.exit(1);
  }

  const config = JSON.parse(fs.readFileSync(FIREBASE_TOOLS_CONFIG, 'utf8'));
  const tokens = config.tokens;

  if (!tokens || !tokens.refresh_token) {
    console.error('❌  No refresh token found. Run: firebase login');
    process.exit(1);
  }

  const body = JSON.stringify({
    grant_type: 'refresh_token',
    refresh_token: tokens.refresh_token,
    client_id: '563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com',
    client_secret: 'j9iVZfS8kkCEFUPaAeJV0sAi',
  });

  const res = await httpsRequest(
    {
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    },
    body
  );

  if (res.status !== 200 || !res.body.access_token) {
    console.error('❌  Failed to refresh token:', JSON.stringify(res.body, null, 2));
    process.exit(1);
  }

  return res.body.access_token;
}

function toFirestoreValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'string') return { stringValue: val };
  if (typeof val === 'boolean') return { booleanValue: val };
  if (typeof val === 'number') return { integerValue: String(val) };
  if (Array.isArray(val)) return { arrayValue: { values: val.map(toFirestoreValue) } };
  if (typeof val === 'object') {
    const fields = {};
    for (const [key, value] of Object.entries(val)) fields[key] = toFirestoreValue(value);
    return { mapValue: { fields } };
  }
  return { stringValue: String(val) };
}

function firestoreGet(token, resourcePath, query) {
  return httpsRequest({
    hostname: PROJECT_HOST,
    path: `${DB_PATH}${resourcePath}${query ? `?${query}` : ''}`,
    method: 'GET',
    headers: { Authorization: `Bearer ${token}` },
  });
}

function firestorePatch(token, collection, docId, fields, fieldPaths) {
  const body = JSON.stringify({ fields });
  const query = fieldPaths
    .map((fieldPath) => `updateMask.fieldPaths=${encodeURIComponent(fieldPath)}`)
    .join('&');

  return httpsRequest(
    {
      hostname: PROJECT_HOST,
      path: `${DB_PATH}/${collection}/${docId}?${query}`,
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    },
    body
  );
}

async function listAllDocs(token, collection) {
  const docs = [];
  let pageToken = null;

  do {
    const query = pageToken ? `pageToken=${pageToken}` : '';
    const res = await firestoreGet(token, `/${collection}`, query);
    if (res.status !== 200) {
      console.error(`❌  Error listing ${collection}:`, res.body);
      process.exit(1);
    }
    if (res.body.documents) docs.push(...res.body.documents);
    pageToken = res.body.nextPageToken;
  } while (pageToken);

  return docs;
}

function plannedCategoryUpdates(doc) {
  const fields = doc.fields ?? {};
  const updates = {};

  if (!Object.prototype.hasOwnProperty.call(fields, 'isAnnounced')) {
    updates.isAnnounced = true;
  }

  return updates;
}

function plannedQuestionUpdates(doc) {
  const fields = doc.fields ?? {};
  const updates = {};

  if (!Object.prototype.hasOwnProperty.call(fields, 'isAnnounced')) {
    updates.isAnnounced = true;
  }

  if (!Object.prototype.hasOwnProperty.call(fields, 'source')) {
    updates.source = 'seeded';
  }

  return updates;
}

async function applyCollectionBackfill(token, collection, planner) {
  const docs = await listAllDocs(token, collection);
  const operations = docs
    .map((doc) => {
      const docId = doc.name.split('/').pop();
      const updates = planner(doc);
      return {
        docId,
        updates,
        fieldPaths: Object.keys(updates),
      };
    })
    .filter((operation) => operation.fieldPaths.length > 0);

  console.log(`📚  ${collection}: ${docs.length} doc(s) scanned, ${operations.length} update(s) planned.`);

  if (isDryRun || operations.length === 0) {
    return operations.length;
  }

  let completed = 0;
  for (const operation of operations) {
    const fields = Object.fromEntries(
      Object.entries(operation.updates).map(([key, value]) => [key, toFirestoreValue(value)])
    );
    const res = await firestorePatch(token, collection, operation.docId, fields, operation.fieldPaths);
    if (res.status !== 200) {
      console.error(`\n❌  Failed to update ${collection}/${operation.docId}:`, res.body);
      process.exit(1);
    }

    completed += 1;
    process.stdout.write(`   ${collection}: ${completed}/${operations.length}...\r`);
  }

  if (operations.length > 0) {
    process.stdout.write('\n');
  }

  return operations.length;
}

async function main() {
  console.log('');
  console.log('TTB Release Announcement Backfill');
  console.log('=================================');
  console.log(`🎯  Target project: ${PROJECT_ID}`);
  if (isDryRun) console.log('🔍  --dry-run: no writes.');
  console.log('');

  console.log('🔐  Getting access token from Firebase CLI...');
  const token = await getAccessToken();
  console.log('   ✅  Token obtained.\n');

  const categoryUpdates = await applyCollectionBackfill(token, 'categories', plannedCategoryUpdates);
  const questionUpdates = await applyCollectionBackfill(token, 'questions', plannedQuestionUpdates);

  console.log('');
  console.log('✅  Backfill complete.');
  console.log(`   Categories updated : ${categoryUpdates}`);
  console.log(`   Questions updated  : ${questionUpdates}`);
  console.log('');
}

main().catch((error) => {
  console.error('❌  Error:', error);
  process.exit(1);
});
