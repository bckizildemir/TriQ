#!/usr/bin/env node
/**
 * TTB Question Sync — updates existing Firestore question docs in place by
 * matching the previous seeded text to the new seeded contentId.
 *
 * Usage:
 *   node sync_with_cli_token.js
 *   node sync_with_cli_token.js --dry-run
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const os = require('os');

const PREVIOUS_FILE = path.join(__dirname, 'questions.previous.json');
const CURRENT_FILE = path.join(__dirname, 'questions.json');
const FIREBASE_TOOLS_CONFIG = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
const PROJECT_ID = 'ttbp-9d652';
const COLLECTION = 'questions';

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

function questionLegacyKey(question) {
  return `${question.category}:::${question.text}`;
}

function managedQuestionFields(question) {
  return {
    contentId: toFirestoreValue(question.contentId),
    text: toFirestoreValue(question.text),
    category: toFirestoreValue(question.category),
    localizedTexts: toFirestoreValue(question.localizedTexts),
    answers: toFirestoreValue(question.answers),
    favoriteUserIds: toFirestoreValue(question.favoriteUserIds),
  };
}

function firestorePatch(token, docId, fields) {
  const body = JSON.stringify({ fields });
  const query = [
    'updateMask.fieldPaths=contentId',
    'updateMask.fieldPaths=text',
    'updateMask.fieldPaths=category',
    'updateMask.fieldPaths=localizedTexts',
    'updateMask.fieldPaths=answers',
    'updateMask.fieldPaths=favoriteUserIds',
  ].join('&');
  return httpsRequest(
    {
      hostname: BASE,
      path: `${DB_PATH}/${COLLECTION}/${docId}?${query}`,
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

const BASE = 'firestore.googleapis.com';
const DB_PATH = `/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function firestoreGet(token, resourcePath, query) {
  return httpsRequest({
    hostname: BASE,
    path: `${DB_PATH}${resourcePath}${query ? `?${query}` : ''}`,
    method: 'GET',
    headers: { Authorization: `Bearer ${token}` },
  });
}

function firestoreCreate(token, fields) {
  const body = JSON.stringify({ fields });
  return httpsRequest(
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
    if (res.body.documents) docs.push(...res.body.documents);
    pageToken = res.body.nextPageToken;
  } while (pageToken);

  return docs;
}

function loadJson(filePath) {
  if (!fs.existsSync(filePath)) {
    console.error(`❌  Missing file: ${filePath}`);
    process.exit(1);
  }
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function questionKey(question) {
  return `${question.category}:::${question.text}`;
}

function buildMigrations(previousQuestions, currentQuestions) {
  if (previousQuestions.length !== currentQuestions.length) {
    console.error('❌  Previous and current question files must have the same length for in-place sync.');
    process.exit(1);
  }

  return previousQuestions.map((previousQuestion, index) => {
    const normalizedPrevious = normalizeQuestion(previousQuestion);
    const normalizedCurrent = normalizeQuestion(currentQuestions[index]);

    if (normalizedPrevious.category !== normalizedCurrent.category) {
      console.error(`❌  Category mismatch at index ${index}: ${normalizedPrevious.category} vs ${normalizedCurrent.category}`);
      process.exit(1);
    }

    return {
      previous: normalizedPrevious,
      current: normalizedCurrent,
      changed:
        normalizedPrevious.text !== normalizedCurrent.text ||
        normalizedPrevious.contentId !== normalizedCurrent.contentId,
    };
  });
}

async function main() {
  console.log('');
  console.log('🔄  TTB Question Sync Script (Firebase CLI Auth)');
  console.log('═══════════════════════════════════════════════');
  if (isDryRun) console.log('🔍  --dry-run: no writes.');
  console.log('');

  const previousQuestions = loadJson(PREVIOUS_FILE);
  const currentQuestions = loadJson(CURRENT_FILE);
  const migrations = buildMigrations(previousQuestions, currentQuestions);
  const changedMigrations = migrations.filter((item) => item.changed);

  console.log(`📄  Loaded ${previousQuestions.length} previous questions`);
  console.log(`📄  Loaded ${currentQuestions.length} current questions`);
  console.log(`✏️   Planned text updates: ${changedMigrations.length}`);
  console.log('');

  console.log('🔐  Getting access token from Firebase CLI...');
  const token = await getAccessToken();
  console.log('   ✅  Token obtained.\n');

  console.log('📚  Fetching existing Firestore questions...');
  const existingDocs = await listAllDocs(token);
  console.log(`   Found ${existingDocs.length} document(s).\n`);

  const docsByContentId = new Map();
  const docsByLegacyKey = new Map();

  for (const doc of existingDocs) {
    const fields = doc.fields ?? {};
    const text = fields.text?.stringValue ?? '';
    const category = fields.category?.stringValue ?? '';
    const contentId = fields.contentId?.stringValue ?? '';
    const docId = doc.name.split('/').pop();
    const summary = { docId, text, category, contentId };

    if (contentId) {
      if (!docsByContentId.has(contentId)) docsByContentId.set(contentId, []);
      docsByContentId.get(contentId).push(summary);
    }

    const legacyKey = `${category}:::${text}`;
    if (!docsByLegacyKey.has(legacyKey)) docsByLegacyKey.set(legacyKey, []);
    docsByLegacyKey.get(legacyKey).push(summary);
  }

  const operations = [];

  for (const migration of changedMigrations) {
    const contentMatches = docsByContentId.get(migration.current.contentId) ?? [];
    const legacyMatches = docsByLegacyKey.get(questionKey(migration.previous)) ?? [];
    const matches = contentMatches.length > 0 ? contentMatches : legacyMatches;

    if (matches.length > 0) {
      matches.forEach((doc) => {
        operations.push({
          type: 'update',
          docId: doc.docId,
          previous: migration.previous,
          current: migration.current,
          duplicateMatchCount: matches.length,
        });
      });
      continue;
    }

    operations.push({
      type: 'create',
      previous: migration.previous,
      current: migration.current,
    });
  }

  const summary = operations.reduce(
    (acc, operation) => {
      acc[operation.type] = (acc[operation.type] ?? 0) + 1;
      return acc;
    },
    { update: 0, create: 0, skip: 0 }
  );

  console.log('🧾  Planned operations');
  console.log(`   Update : ${summary.update}`);
  console.log(`   Create : ${summary.create}`);
  console.log(`   Skip   : ${summary.skip}`);
  console.log('');

  const duplicateUpdates = operations.filter(
    (operation) => operation.type === 'update' && operation.duplicateMatchCount > 1
  );
  if (duplicateUpdates.length > 0) {
    console.log(`⚠️   Duplicate old-text matches found for ${duplicateUpdates.length} migration(s). All matches will be updated.`);
    console.log('');
  }

  if (isDryRun) {
    operations.slice(0, 25).forEach((operation, index) => {
      if (operation.type === 'update') {
        console.log(`${index + 1}. UPDATE [${operation.current.category}] ${operation.previous.text} -> ${operation.current.text}`);
      } else if (operation.type === 'create') {
        console.log(`${index + 1}. CREATE [${operation.current.category}] ${operation.current.text}`);
      }
    });
    if (operations.length > 25) {
      console.log(`...and ${operations.length - 25} more operation(s).`);
    }
    console.log('');
    return;
  }

  let completed = 0;
  for (const operation of operations) {
    if (operation.type === 'update') {
      const fields = managedQuestionFields(operation.current);
      const res = await firestorePatch(token, operation.docId, fields);
      if (res.status !== 200) {
        console.error(`\n❌  Failed to update ${operation.docId}:`, res.body);
        process.exit(1);
      }
    } else if (operation.type === 'create') {
      const now = new Date().toISOString();
      const fields = {
        ...managedQuestionFields(operation.current),
        source: toFirestoreValue('seeded'),
        isAnnounced: toFirestoreValue(false),
        createdAt: toFirestoreValue(now),
        createdBy: toFirestoreValue(null),
      };
      const res = await firestoreCreate(token, fields);
      if (res.status !== 200) {
        console.error(`\n❌  Failed to create "${operation.current.text}":`, res.body);
        process.exit(1);
      }
    }

    completed++;
    process.stdout.write(`   ${completed}/${operations.length}...\r`);
  }

  console.log(`\n✅  Sync complete.`);
  console.log(`   Updated : ${summary.update}`);
  console.log(`   Created : ${summary.create}`);
  console.log(`   Skipped : ${summary.skip}`);
  console.log('');
}

main().catch((error) => {
  console.error('❌  Error:', error);
  process.exit(1);
});
