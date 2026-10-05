#!/usr/bin/env node
/**
 * TTB Question Seed — uses stored Firebase CLI OAuth tokens (no service account needed).
 *
 * Usage:
 *   node seed_with_cli_token.js               # upsert by contentId/text
 *   node seed_with_cli_token.js --clean       # wipe collection then seed
 *   node seed_with_cli_token.js --dry-run     # preview only
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const os = require('os');

const QUESTIONS_FILE = path.join(__dirname, 'questions.json');
const FIREBASE_TOOLS_CONFIG = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
const PROJECT_ID = 'ttbp-9d652';
const COLLECTION = 'questions';

const args = process.argv.slice(2);
const isClean = args.includes('--clean');
const isDryRun = args.includes('--dry-run');

// ─── Helpers ─────────────────────────────────────────────────────────────────

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

// ─── Auth ─────────────────────────────────────────────────────────────────────

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

  // Try existing access token first; if expired Google will return 401 and we refresh
  // Always refresh to be safe
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
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
    },
    body
  );

  if (res.status !== 200 || !res.body.access_token) {
    console.error('❌  Failed to refresh token:', JSON.stringify(res.body, null, 2));
    process.exit(1);
  }

  return res.body.access_token;
}

// ─── Firestore REST helpers ───────────────────────────────────────────────────

const BASE = `firestore.googleapis.com`;
const DB_PATH = `/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function firestoreGet(token, path, query) {
  const url = `${DB_PATH}${path}${query ? '?' + query : ''}`;
  return httpsRequest({
    hostname: BASE,
    path: url,
    method: 'GET',
    headers: { Authorization: `Bearer ${token}` },
  });
}

function firestorePatch(token, docPath, fields) {
  const body = JSON.stringify({ fields });
  const query = [
    'updateMask.fieldPaths=contentId',
    'updateMask.fieldPaths=text',
    'updateMask.fieldPaths=category',
    'updateMask.fieldPaths=localizedTexts',
  ].join('&');
  return httpsRequest(
    {
      hostname: BASE,
      path: `${DB_PATH}${docPath}?${query}`,
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

function firestoreDelete(token, docPath) {
  return httpsRequest({
    hostname: BASE,
    path: `${DB_PATH}${docPath}`,
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` },
  });
}

// Convert a JS value to a Firestore REST field value
function toFirestoreValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'string') return { stringValue: val };
  if (typeof val === 'boolean') return { booleanValue: val };
  if (typeof val === 'number') return { integerValue: String(val) };
  if (Array.isArray(val)) return { arrayValue: { values: val.map(toFirestoreValue) } };
  if (val instanceof Date) return { timestampValue: val.toISOString() };
  if (typeof val === 'object') {
    const fields = {};
    for (const [k, v] of Object.entries(val)) fields[k] = toFirestoreValue(v);
    return { mapValue: { fields } };
  }
  return { stringValue: String(val) };
}

function slugify(value) {
  return String(value)
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/ç/g, 'c')
    .replace(/ğ/g, 'g')
    .replace(/ı/g, 'i')
    .replace(/İ/g, 'I')
    .replace(/ö/g, 'o')
    .replace(/ş/g, 's')
    .replace(/ü/g, 'u')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function normalizeQuestion(question) {
  const text = question.text ?? question.localizedTexts?.tr ?? question.localizedTexts?.en ?? '';
  const category = question.category ?? '';
  const localizedTexts = { ...(question.localizedTexts ?? {}) };

  if (!localizedTexts.tr && text) {
    localizedTexts.tr = text;
  }
  if (!localizedTexts.en && text) {
    localizedTexts.en = text;
  }

  return {
    contentId: question.contentId ?? `${slugify(category)}-${slugify(text)}`,
    text,
    category,
    localizedTexts,
    answers: Array.isArray(question.answers) ? question.answers : [],
    favoriteUserIds: Array.isArray(question.favoriteUserIds) ? question.favoriteUserIds : [],
  };
}

function managedQuestionFields(question) {
  return {
    text: toFirestoreValue(question.text),
    category: toFirestoreValue(question.category),
    contentId: toFirestoreValue(question.contentId),
    localizedTexts: toFirestoreValue(question.localizedTexts),
  };
}

function managedQuestionFieldsMatch(existingFields, question) {
  const localized = existingFields.localizedTexts?.mapValue?.fields ?? {};

  return (
    (existingFields.contentId?.stringValue ?? '') === question.contentId &&
    (existingFields.text?.stringValue ?? '') === question.text &&
    (existingFields.category?.stringValue ?? '') === question.category &&
    (localized.tr?.stringValue ?? '') === (question.localizedTexts.tr ?? '') &&
    (localized.en?.stringValue ?? '') === (question.localizedTexts.en ?? '')
  );
}

// ─── List all docs (handles pagination) ──────────────────────────────────────

async function listAllDocs(token) {
  const docs = [];
  let pageToken = null;

  do {
    const query = pageToken ? `pageToken=${pageToken}` : '';
    const res = await firestoreGet(token, `/${COLLECTION}`, query);
    if (res.status !== 200) {
      console.error('❌  Error listing documents:', res.body);
      process.exit(1);
    }
    const body = res.body;
    if (body.documents) docs.push(...body.documents);
    pageToken = body.nextPageToken;
  } while (pageToken);

  return docs;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log('');
  console.log('📚  TTB Question Seed Script (Firebase CLI Auth)');
  console.log('══════════════════════════════════════════════');
  if (isClean) console.log('⚠️   --clean: existing questions will be DELETED first.');
  if (isDryRun) console.log('🔍  --dry-run: no writes.');
  console.log('');

  // Load questions
  const questions = JSON.parse(fs.readFileSync(QUESTIONS_FILE, 'utf8')).map(normalizeQuestion);
  console.log(`📄  Loaded ${questions.length} questions from questions.json`);
  const byCategory = questions.reduce((a, q) => { a[q.category] = (a[q.category] ?? 0) + 1; return a; }, {});
  Object.entries(byCategory).forEach(([c, n]) => console.log(`     • ${c}: ${n}`));
  console.log('');

  // Get access token
  console.log('🔐  Getting access token from Firebase CLI...');
  const token = await getAccessToken();
  console.log('   ✅  Token obtained.\n');

  // Clean if requested
  if (isClean) {
    console.log('🗑   Fetching existing questions...');
    const existing = await listAllDocs(token);
    if (existing.length === 0) {
      console.log('   Collection is empty.\n');
    } else {
      console.log(`   Deleting ${existing.length} documents...`);
      let deleted = 0;
      for (const doc of existing) {
        const docId = doc.name.split('/').pop();
        await firestoreDelete(token, `/${COLLECTION}/${docId}`);
        deleted++;
        if (deleted % 20 === 0) process.stdout.write(`   ${deleted}/${existing.length}...\r`);
      }
      console.log(`   ✅  Deleted ${deleted} documents.        \n`);
    }
  }

  // Find existing docs to update in place. Preserve nested userAnswers subcollections.
  let existingDocs = [];
  if (!isClean) {
    console.log('🔍  Checking for existing questions...');
    existingDocs = await listAllDocs(token);
    console.log(`   Found ${existingDocs.length} existing question document(s).\n`);
  }

  const docsByContentId = new Map();
  const docsByText = new Map();
  existingDocs.forEach((doc) => {
    const fields = doc.fields ?? {};
    const docId = doc.name.split('/').pop();
    const summary = { docId, fields };
    const contentId = fields.contentId?.stringValue;
    const text = fields.text?.stringValue;
    if (contentId && !docsByContentId.has(contentId)) {
      docsByContentId.set(contentId, summary);
    }
    if (text && !docsByText.has(text)) {
      docsByText.set(text, summary);
    }
  });

  const operations = questions.map((question) => {
    const existingDoc = docsByContentId.get(question.contentId) ?? docsByText.get(question.text);
    if (!existingDoc) {
      return { type: 'create', question };
    }
    if (managedQuestionFieldsMatch(existingDoc.fields, question)) {
      return { type: 'skip', question, existingDoc };
    }
    return { type: 'update', question, existingDoc };
  });

  const toCreate = operations.filter((operation) => operation.type === 'create');
  const toUpdate = operations.filter((operation) => operation.type === 'update');
  const toSkip = operations.filter((operation) => operation.type === 'skip');
  const writeOperations = operations.filter((operation) => operation.type !== 'skip');

  if (writeOperations.length === 0) {
    console.log('   All questions already match questions.json — nothing to upload.');
    return;
  }

  console.log('🧾  Planned operations');
  console.log(`   Create : ${toCreate.length}`);
  console.log(`   Update : ${toUpdate.length}`);
  console.log(`   Skip   : ${toSkip.length}`);
  console.log('');

  if (isDryRun) {
    operations.forEach((operation, i) => {
      const label = operation.type.toUpperCase();
      console.log(`   ${i + 1}. ${label} [${operation.question.category}] ${operation.question.text}`);
    });
    return;
  }

  console.log(`🚀  Writing ${writeOperations.length} question(s)...`);
  const now = new Date().toISOString();
  let completed = 0;

  for (const operation of writeOperations) {
    const q = operation.question;
    const fields = managedQuestionFields(q);
    let res;
    if (operation.type === 'update') {
      res = await firestorePatch(token, `/${COLLECTION}/${operation.existingDoc.docId}`, fields);
    } else {
      const body = JSON.stringify({
        fields: {
          ...fields,
          isAnnounced: toFirestoreValue(false),
          createdAt: toFirestoreValue(now),
          createdBy: toFirestoreValue(null),
        },
      });
      res = await httpsRequest(
        {
          hostname: BASE,
          path: `${DB_PATH}/${COLLECTION}`,
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(body),
          },
        },
        body
      );
    }

    if (res.status !== 200) {
      console.error(`\n❌  Failed to ${operation.type} "${q.text}":`, res.body);
      process.exit(1);
    }

    completed++;
    process.stdout.write(`   ${completed}/${writeOperations.length}...\r`);
  }

  console.log(`\n✅  Done!`);
  console.log(`   Created : ${toCreate.length}`);
  console.log(`   Updated : ${toUpdate.length}`);
  console.log(`   Skipped : ${toSkip.length}`);
  console.log(`   Total    : ${questions.length}`);
  console.log('');
}

main().catch((err) => {
  console.error('❌  Error:', err);
  process.exit(1);
});
