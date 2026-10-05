#!/usr/bin/env node

/**
 * Backfills moderation metadata for existing user-created questions.
 *
 * Usage:
 *   node backfill_question_moderation.js --dry-run
 *   node backfill_question_moderation.js --commit
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const SERVICE_ACCOUNT_FILE = path.join(__dirname, 'serviceAccountKey.json');
const BATCH_SIZE = 400;
const args = process.argv.slice(2);
const shouldCommit = args.includes('--commit');

function initFirebase() {
  if (!fs.existsSync(SERVICE_ACCOUNT_FILE)) {
    console.error('serviceAccountKey.json not found.');
    console.error(`Save it as: ${SERVICE_ACCOUNT_FILE}`);
    process.exit(1);
  }

  const serviceAccount = require(SERVICE_ACCOUNT_FILE);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  console.log(`Firebase project: ${serviceAccount.project_id}`);
  return admin.firestore();
}

function cleanedString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

async function usernameForUser(db, uid, cache) {
  if (!uid) return '';
  if (cache.has(uid)) return cache.get(uid);

  const snapshot = await db.collection('users').doc(uid).get();
  const username = cleanedString(snapshot.data()?.username);
  cache.set(uid, username);
  return username;
}

async function commitBatches(db, updates) {
  let committed = 0;
  for (let index = 0; index < updates.length; index += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = updates.slice(index, index + BATCH_SIZE);
    for (const update of chunk) {
      batch.update(update.ref, update.data);
    }
    await batch.commit();
    committed += chunk.length;
  }
  return committed;
}

async function main() {
  const db = initFirebase();
  const snapshot = await db.collection('questions')
    .where('source', '==', 'userCreated')
    .get();

  const usernameCache = new Map();
  const updates = [];
  let missingUsernameCount = 0;

  for (const document of snapshot.docs) {
    const data = document.data() || {};
    const patch = {};

    if (!cleanedString(data.moderationStatus)) {
      patch.moderationStatus = 'approved';
    }

    if (!cleanedString(data.featuredPlacement)) {
      patch.featuredPlacement = 'none';
    }

    if (!cleanedString(data.creatorUsername)) {
      const username = await usernameForUser(db, cleanedString(data.createdBy), usernameCache);
      if (username) {
        patch.creatorUsername = username;
      } else {
        missingUsernameCount += 1;
      }
    }

    if (Object.keys(patch).length > 0) {
      updates.push({
        ref: document.ref,
        id: document.id,
        data: patch,
      });
    }
  }

  console.log(`User-created questions scanned: ${snapshot.size}`);
  console.log(`Questions needing updates: ${updates.length}`);
  console.log(`Questions still missing resolvable usernames: ${missingUsernameCount}`);

  updates.slice(0, 10).forEach((update) => {
    console.log(`- ${update.id}: ${JSON.stringify(update.data)}`);
  });

  if (!shouldCommit) {
    console.log('Dry run only. Re-run with --commit to write changes.');
    return;
  }

  const committed = await commitBatches(db, updates);
  console.log(`Committed updates: ${committed}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
