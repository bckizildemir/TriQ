#!/usr/bin/env node
/**
 * One-time migration script for legacy seeded questions.
 *
 * It matches old Firestore question documents by their previous
 * `category + text` key and patches them in place with the new stable
 * `contentId` and `localizedTexts` fields.
 *
 * Usage:
 *   node migrate_legacy_questions.js
 *   node migrate_legacy_questions.js --dry-run
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
    source: toFirestoreValue('seeded'),
    isAnnounced: toFirestoreValue(true),
    answers: toFirestoreValue(question.answers),
    favoriteUserIds: toFirestoreValue(question.favoriteUserIds),
  };
}

function managedQuestionDataMatches(existingFields, question) {
  const localizedTexts = existingFields.localizedTexts?.mapValue?.fields ?? {};
  const existingAnswers = existingFields.answers?.arrayValue?.values ?? [];
  const existingFavoriteUserIds = existingFields.favoriteUserIds?.arrayValue?.values ?? [];

  return (
    (existingFields.contentId?.stringValue ?? '') === question.contentId &&
    (existingFields.text?.stringValue ?? '') === question.text &&
    (existingFields.category?.stringValue ?? '') === question.category &&
    (localizedTexts.tr?.stringValue ?? '') === (question.localizedTexts.tr ?? '') &&
    (localizedTexts.en?.stringValue ?? '') === (question.localizedTexts.en ?? '') &&
    (existingFields.source?.stringValue ?? 'seeded') === 'seeded' &&
    (existingFields.isAnnounced?.booleanValue ?? true) === true &&
    JSON.stringify(existingAnswers) === JSON.stringify(question.answers.map(toFirestoreValue)) &&
    JSON.stringify(existingFavoriteUserIds) === JSON.stringify(question.favoriteUserIds.map(toFirestoreValue))
  );
}

function firestorePatch(token, docId, fields) {
  const body = JSON.stringify({ fields });
  const query = [
    'updateMask.fieldPaths=contentId',
    'updateMask.fieldPaths=text',
    'updateMask.fieldPaths=category',
    'updateMask.fieldPaths=localizedTexts',
    'updateMask.fieldPaths=source',
    'updateMask.fieldPaths=isAnnounced',
    'updateMask.fieldPaths=answers',
    'updateMask.fieldPaths=favoriteUserIds',
  ].join('&');
  return httpsRequest(
    {
      hostname: PROJECT_HOST,
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

function firestoreGet(token, resourcePath, query) {
  return httpsRequest({
    hostname: PROJECT_HOST,
    path: `${DB_PATH}${resourcePath}${query ? `?${query}` : ''}`,
    method: 'GET',
    headers: { Authorization: `Bearer ${token}` },
  });
}

const PROJECT_HOST = 'firestore.googleapis.com';
const DB_PATH = `/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

function loadJson(filePath) {
  if (!fs.existsSync(filePath)) {
    console.error(`❌  Missing file: ${filePath}`);
    process.exit(1);
  }
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
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

function buildMigrationMap(previousQuestions, currentQuestions) {
  if (previousQuestions.length !== currentQuestions.length) {
    console.error('❌  Previous and current question files must have the same length.');
    process.exit(1);
  }

  const migrations = [];
  for (let index = 0; index < previousQuestions.length; index++) {
    const previousQuestion = normalizeQuestion(previousQuestions[index]);
    const currentQuestion = normalizeQuestion(currentQuestions[index]);

    if (previousQuestion.category !== currentQuestion.category) {
      console.error(`❌  Category mismatch at index ${index}: ${previousQuestion.category} vs ${currentQuestion.category}`);
      process.exit(1);
    }

    migrations.push({
      previous: previousQuestion,
      current: currentQuestion,
      legacyKey: questionLegacyKey(previousQuestion),
    });
  }

  return migrations;
}

async function main() {
  console.log('');
  console.log('TTB Legacy Question Migration');
  console.log('=================================');
  if (isDryRun) console.log('🔍  --dry-run: no writes.');
  console.log('');

  const previousQuestions = loadJson(PREVIOUS_FILE);
  const currentQuestions = loadJson(CURRENT_FILE);
  const migrations = buildMigrationMap(previousQuestions, currentQuestions);

  console.log(`📄  Loaded ${previousQuestions.length} previous questions`);
  console.log(`📄  Loaded ${currentQuestions.length} current questions`);
  console.log('');

  console.log('🔐  Getting access token from Firebase CLI...');
  const token = await getAccessToken();
  console.log('   ✅  Token obtained.\n');

  console.log('📚  Fetching existing Firestore questions...');
  const existingDocs = await listAllDocs(token);
  console.log(`   Found ${existingDocs.length} document(s).\n`);

  const docsByLegacyKey = new Map();
  const docsByContentId = new Map();
  for (const doc of existingDocs) {
    const fields = doc.fields ?? {};
    const docId = doc.name.split('/').pop();
    const text = fields.text?.stringValue ?? '';
    const category = fields.category?.stringValue ?? '';
    const contentId = fields.contentId?.stringValue ?? '';
    const legacyKey = `${category}:::${text}`;
    const summary = { docId, fields, legacyKey, contentId };

    if (contentId) {
      if (!docsByContentId.has(contentId)) docsByContentId.set(contentId, []);
      docsByContentId.get(contentId).push(summary);
    }

    if (!docsByLegacyKey.has(legacyKey)) docsByLegacyKey.set(legacyKey, []);
    docsByLegacyKey.get(legacyKey).push(summary);
  }

  const operations = [];
  for (const migration of migrations) {
    const currentMatches = docsByContentId.get(migration.current.contentId) ?? [];
    if (currentMatches.length > 0) {
      for (const doc of currentMatches) {
        if (!managedQuestionDataMatches(doc.fields, migration.current)) {
          operations.push({ type: 'update', docId: doc.docId, migration });
        }
      }
      continue;
    }

    const legacyMatches = docsByLegacyKey.get(migration.legacyKey) ?? [];
    for (const doc of legacyMatches) {
      operations.push({ type: 'update', docId: doc.docId, migration });
    }
  }

  console.log(`🧾  Planned updates: ${operations.length}`);
  console.log('');

  if (isDryRun) {
    operations.slice(0, 25).forEach((operation, index) => {
      console.log(`${index + 1}. UPDATE [${operation.migration.current.category}] ${operation.migration.previous.text} -> ${operation.migration.current.text}`);
    });
    if (operations.length > 25) {
      console.log(`...and ${operations.length - 25} more operation(s).`);
    }
    console.log('');
    return;
  }

  let completed = 0;
  for (const operation of operations) {
    const res = await firestorePatch(token, operation.docId, managedQuestionFields(operation.migration.current));
    if (res.status !== 200) {
      console.error(`\n❌  Failed to update ${operation.docId}:`, res.body);
      process.exit(1);
    }

    completed++;
    process.stdout.write(`   ${completed}/${operations.length}...\r`);
  }

  console.log(`\n✅  Migration complete.`);
  console.log(`   Updated : ${operations.length}`);
  console.log('');
}

main().catch((error) => {
  console.error('❌  Error:', error);
  process.exit(1);
});
