#!/usr/bin/env node
/**
 * Updates seeded question category fields in Firestore using Firebase CLI auth.
 *
 * Usage:
 *   node sync_categories_with_cli_token.js --dry-run
 *   node sync_categories_with_cli_token.js
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const os = require('os');

const QUESTIONS_FILE = path.join(__dirname, 'questions.json');
const FIREBASE_TOOLS_CONFIG = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
const PROJECT_ID = 'ttbp-9d652';
const COLLECTION = 'questions';
const BASE = 'firestore.googleapis.com';
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
    console.error('Firebase CLI config not found. Run: firebase login');
    process.exit(1);
  }

  const config = JSON.parse(fs.readFileSync(FIREBASE_TOOLS_CONFIG, 'utf8'));
  const refreshToken = config.tokens?.refresh_token;
  if (!refreshToken) {
    console.error('Firebase CLI refresh token not found. Run: firebase login');
    process.exit(1);
  }

  const body = JSON.stringify({
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
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
    console.error('Failed to refresh token:', JSON.stringify(res.body, null, 2));
    process.exit(1);
  }

  return res.body.access_token;
}

function firestoreGet(token, resourcePath, query) {
  return httpsRequest({
    hostname: BASE,
    path: `${DB_PATH}${resourcePath}${query ? `?${query}` : ''}`,
    method: 'GET',
    headers: { Authorization: `Bearer ${token}` },
  });
}

function firestorePatchCategory(token, docId, category) {
  const body = JSON.stringify({
    fields: {
      category: { stringValue: category },
    },
  });

  return httpsRequest(
    {
      hostname: BASE,
      path: `${DB_PATH}/${COLLECTION}/${docId}?updateMask.fieldPaths=category`,
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

async function listAllDocs(token) {
  const docs = [];
  let pageToken = null;

  do {
    const query = pageToken ? `pageToken=${pageToken}` : '';
    const res = await firestoreGet(token, `/${COLLECTION}`, query);
    if (res.status !== 200) {
      console.error('Error listing documents:', res.body);
      process.exit(1);
    }
    if (res.body.documents) {
      docs.push(...res.body.documents);
    }
    pageToken = res.body.nextPageToken;
  } while (pageToken);

  return docs;
}

function normalizeQuestion(question) {
  return {
    contentId: question.contentId ?? '',
    text: question.text ?? question.localizedTexts?.tr ?? question.localizedTexts?.en ?? '',
    category: question.category ?? '',
  };
}

async function main() {
  console.log('');
  console.log('TTB Category Sync (Firebase CLI Auth)');
  if (isDryRun) console.log('--dry-run: no writes');
  console.log('');

  const questions = JSON.parse(fs.readFileSync(QUESTIONS_FILE, 'utf8')).map(normalizeQuestion);
  const nonDailyQuestions = questions.filter((question) => question.category !== 'Daily');

  const token = await getAccessToken();
  const docs = await listAllDocs(token);

  const docsByContentId = new Map();
  const docsByText = new Map();
  docs.forEach((doc) => {
    const fields = doc.fields ?? {};
    const docId = doc.name.split('/').pop();
    const contentId = fields.contentId?.stringValue;
    const text = fields.text?.stringValue;
    const category = fields.category?.stringValue ?? '';
    const summary = { docId, category, text, contentId };

    if (contentId && !docsByContentId.has(contentId)) {
      docsByContentId.set(contentId, summary);
    }
    if (text && !docsByText.has(text)) {
      docsByText.set(text, summary);
    }
  });

  const operations = [];
  const missing = [];

  nonDailyQuestions.forEach((question) => {
    const existingDoc = docsByContentId.get(question.contentId) ?? docsByText.get(question.text);
    if (!existingDoc) {
      missing.push(question);
      return;
    }
    if (existingDoc.category !== question.category) {
      operations.push({
        docId: existingDoc.docId,
        text: question.text,
        from: existingDoc.category,
        to: question.category,
      });
    }
  });

  console.log(`Questions loaded : ${questions.length}`);
  console.log(`Non-Daily checked: ${nonDailyQuestions.length}`);
  console.log(`Firestore docs   : ${docs.length}`);
  console.log(`Updates planned  : ${operations.length}`);
  console.log(`Missing matches  : ${missing.length}`);
  console.log('');

  operations.forEach((operation, index) => {
    console.log(`${index + 1}. ${operation.from} -> ${operation.to}: ${operation.text}`);
  });

  if (missing.length > 0) {
    console.log('');
    console.log('Missing question matches:');
    missing.forEach((question) => console.log(`- [${question.category}] ${question.text}`));
  }

  if (isDryRun) {
    return;
  }

  let completed = 0;
  for (const operation of operations) {
    const res = await firestorePatchCategory(token, operation.docId, operation.to);
    if (res.status !== 200) {
      console.error(`Failed to update ${operation.docId}:`, res.body);
      process.exit(1);
    }
    completed++;
    process.stdout.write(`${completed}/${operations.length}\r`);
  }

  console.log(`Updated ${completed} question category field(s).`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
