#!/usr/bin/env node

/**
 * TTB Question Seed Script
 *
 * Seeds questions.json data into Firestore using stable content IDs.
 *
 * Prerequisites:
 *   1. npm install
 *   2. Download service account key from Firebase Console:
 *      Project Settings > Service Accounts > Generate new private key
 *      Save as serviceAccountKey.json in this directory
 *
 * Usage:
 *   node seed.js               # Upsert questions by contentId
 *   node seed.js --clean       # Delete all existing questions first, then seed
 *   node seed.js --dry-run     # Preview what would be uploaded without writing
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const QUESTIONS_FILE = path.join(__dirname, 'questions.json');
const SERVICE_ACCOUNT_FILE = path.join(__dirname, 'serviceAccountKey.json');
const COLLECTION = 'questions';
const BATCH_SIZE = 400; // Firestore max is 500 per batch

const args = process.argv.slice(2);
const isClean = args.includes('--clean');
const isDryRun = args.includes('--dry-run');

// ─── Init ───────────────────────────────────────────────────────────────────

function initFirebase() {
  if (!fs.existsSync(SERVICE_ACCOUNT_FILE)) {
    console.error('❌  serviceAccountKey.json not found.');
    console.error('   Download it from Firebase Console:');
    console.error('   Project Settings > Service Accounts > Generate new private key');
    console.error(`   Save as: ${SERVICE_ACCOUNT_FILE}`);
    process.exit(1);
  }

  const serviceAccount = require(SERVICE_ACCOUNT_FILE);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  console.log(`🔥  Firebase project: ${serviceAccount.project_id}`);
  return admin.firestore();
}

// ─── Load questions ──────────────────────────────────────────────────────────

function loadQuestions() {
  if (!fs.existsSync(QUESTIONS_FILE)) {
    console.error(`❌  questions.json not found at: ${QUESTIONS_FILE}`);
    process.exit(1);
  }

  const raw = fs.readFileSync(QUESTIONS_FILE, 'utf8');
  const questions = JSON.parse(raw);

  if (!Array.isArray(questions) || questions.length === 0) {
    console.error('❌  questions.json is empty or not a valid array.');
    process.exit(1);
  }

  return questions;
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
  const localizedTexts = {
    ...(question.localizedTexts ?? {}),
  };

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

function managedQuestionData(question) {
  return {
    contentId: question.contentId,
    text: question.text,
    category: question.category,
    localizedTexts: question.localizedTexts,
    source: 'seeded',
    answers: question.answers,
    favoriteUserIds: question.favoriteUserIds,
  };
}

function managedQuestionDataMatches(existingData, question) {
  const existingLocalizedTexts = existingData.localizedTexts ?? {};
  const current = managedQuestionData(question);

  return (
    (existingData.contentId ?? '') === current.contentId &&
    (existingData.text ?? '') === current.text &&
    (existingData.category ?? '') === current.category &&
    (existingLocalizedTexts.tr ?? '') === (current.localizedTexts.tr ?? '') &&
    (existingLocalizedTexts.en ?? '') === (current.localizedTexts.en ?? '') &&
    JSON.stringify(Array.isArray(existingData.answers) ? existingData.answers : []) === JSON.stringify(current.answers) &&
    JSON.stringify(Array.isArray(existingData.favoriteUserIds) ? existingData.favoriteUserIds : []) ===
      JSON.stringify(current.favoriteUserIds)
  );
}

// ─── Clean collection ────────────────────────────────────────────────────────

async function deleteAllQuestions(db) {
  console.log('🗑   Fetching existing questions to delete...');
  const snapshot = await db.collection(COLLECTION).get();

  if (snapshot.empty) {
    console.log('   Collection is already empty.');
    return;
  }

  console.log(`   Found ${snapshot.size} documents — deleting in batches...`);

  const chunks = [];
  const docs = snapshot.docs;
  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    chunks.push(docs.slice(i, i + BATCH_SIZE));
  }

  for (const chunk of chunks) {
    const batch = db.batch();
    chunk.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }

  console.log(`   ✅  Deleted ${snapshot.size} documents.`);
}

// ─── Seed questions ──────────────────────────────────────────────────────────

async function seedQuestions(db, questions, existingDocs) {
  const now = admin.firestore.Timestamp.now();
  const docsByContentId = new Map();
  const docsByLegacyKey = new Map();

  existingDocs.forEach((doc) => {
    const data = doc.data();
    if (data.contentId) {
      docsByContentId.set(data.contentId, doc);
    }
    if (data.text && data.category) {
      docsByLegacyKey.set(questionLegacyKey(data), doc);
    }
  });

  const operations = questions.map((question) => {
    const existingDoc = docsByContentId.get(question.contentId) ?? docsByLegacyKey.get(questionLegacyKey(question));
    if (!existingDoc) {
      return { type: 'create', question };
    }

    const existingData = existingDoc.data();
    if (managedQuestionDataMatches(existingData, question)) {
      return { type: 'skip', question, existingDoc };
    }

    return { type: 'update', question, existingDoc };
  });

  const toCreate = operations.filter((operation) => operation.type === 'create');
  const toUpdate = operations.filter((operation) => operation.type === 'update');
  const writeOperations = operations.filter((operation) => operation.type !== 'skip');

  if (toCreate.length === 0 && toUpdate.length === 0) {
    console.log('   All questions already exist — nothing to upload.');
    return 0;
  }

  if (isDryRun) {
    console.log(`\n📋  DRY RUN — would create ${toCreate.length} and update ${toUpdate.length} question(s):`);
    operations.forEach((operation, i) => {
      const label = operation.type === 'create' ? 'CREATE' : operation.type === 'update' ? 'UPDATE' : 'SKIP';
      console.log(`   ${i + 1}. ${label} [${operation.question.category}] ${operation.question.text}`);
    });
    return writeOperations.length;
  }

  const chunks = [];
  for (let i = 0; i < writeOperations.length; i += BATCH_SIZE) {
    chunks.push(writeOperations.slice(i, i + BATCH_SIZE));
  }

  let uploaded = 0;
  for (const chunk of chunks) {
    if (chunk.length === 0) {
      continue;
    }

    const batch = db.batch();
    chunk.forEach((operation) => {
      const docRef =
        operation.type === 'update' ? operation.existingDoc.ref : db.collection(COLLECTION).doc(operation.question.contentId);
      const data = managedQuestionData(operation.question);

      if (operation.type === 'create') {
        batch.set(docRef, {
          ...data,
          isAnnounced: false,
          createdAt: now,
          createdBy: null,
        });
      } else {
        batch.set(docRef, data, { merge: true });
      }
    });
    await batch.commit();
    uploaded += chunk.length;
    console.log(`   Processed ${uploaded}/${writeOperations.length}...`);
  }

  return uploaded;
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log('');
  console.log('📚  TTB Question Seed Script');
  console.log('═══════════════════════════');
  if (isClean) console.log('⚠️   --clean flag set: existing questions will be DELETED first.');
  if (isDryRun) console.log('🔍  --dry-run flag set: no writes will be performed.');
  console.log('');

  const questions = loadQuestions().map(normalizeQuestion);
  console.log(`📄  Loaded ${questions.length} questions from questions.json`);

  // Summarise by category
  const byCategory = questions.reduce((acc, q) => {
    acc[q.category] = (acc[q.category] ?? 0) + 1;
    return acc;
  }, {});
  console.log('   Categories:');
  Object.entries(byCategory).forEach(([cat, count]) => {
    console.log(`     • ${cat}: ${count} question(s)`);
  });
  console.log('');

  if (isDryRun) {
    console.log('🔍  Dry-run mode: skipping Firebase init.');
    questions.forEach((q, i) => {
      console.log(`   ${i + 1}. [${q.category}] ${q.text} (${q.contentId})`);
    });
    return;
  }

  const db = initFirebase();

  // Optionally wipe existing data
  if (isClean) {
    await deleteAllQuestions(db);
    console.log('');
  }

  // Fetch existing docs to avoid duplicates and keep legacy doc IDs intact.
  let existingDocs = [];
  if (!isClean) {
    console.log('🔍  Checking for existing questions to skip duplicates...');
    const snapshot = await db.collection(COLLECTION).get();
    existingDocs = snapshot.docs;
    console.log(`   Found ${existingDocs.length} existing question(s).`);
    console.log('');
  }

  console.log('🚀  Uploading questions...');
  const uploaded = await seedQuestions(db, questions, existingDocs);

  console.log('');
  console.log('✅  Done!');
  console.log(`   Uploaded : ${uploaded}`);
  console.log(`   Skipped  : ${questions.length - uploaded}`);
  console.log(`   Total in file: ${questions.length}`);
  console.log('');

  process.exit(0);
}

main().catch((err) => {
  console.error('❌  Unexpected error:', err);
  process.exit(1);
});
