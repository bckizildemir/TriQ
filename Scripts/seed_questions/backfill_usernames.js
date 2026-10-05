#!/usr/bin/env node

/**
 * Backfills the private /usernames registry from existing /users docs.
 *
 * Prerequisites:
 *   npm install
 *   serviceAccountKey.json in this directory
 *
 * Usage:
 *   node backfill_usernames.js --dry-run
 *   node backfill_usernames.js --commit
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const SERVICE_ACCOUNT_FILE = path.join(__dirname, 'serviceAccountKey.json');
const BATCH_SIZE = 400;
const args = process.argv.slice(2);
const shouldCommit = args.includes('--commit');

function normalizeUsername(username) {
  return String(username || '').trim().toLowerCase();
}

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

async function main() {
  const db = initFirebase();
  const usersSnapshot = await db.collection('users').get();
  const candidates = [];
  const invalidUsers = [];

  for (const document of usersSnapshot.docs) {
    const data = document.data() || {};
    const username = String(data.username || '').trim();
    const normalizedUsername = normalizeUsername(username);

    if (!username || !normalizedUsername || normalizedUsername.includes('/')) {
      invalidUsers.push({ uid: document.id, username });
      continue;
    }

    candidates.push({
      uid: document.id,
      username,
      usernameNormalized: normalizedUsername,
      email: typeof data.email === 'string' ? data.email.trim() : '',
      isAnonymous: data.isAnonymous === true,
      createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  const grouped = candidates.reduce((map, candidate) => {
    if (!map.has(candidate.usernameNormalized)) {
      map.set(candidate.usernameNormalized, []);
    }
    map.get(candidate.usernameNormalized).push(candidate);
    return map;
  }, new Map());

  const duplicates = [...grouped.entries()]
    .filter(([, values]) => values.length > 1)
    .map(([usernameNormalized, values]) => ({ usernameNormalized, values }));

  const uniqueCandidates = [...grouped.entries()]
    .filter(([, values]) => values.length === 1)
    .map(([, values]) => values[0]);

  console.log(`Users scanned: ${usersSnapshot.size}`);
  console.log(`Valid unique usernames: ${uniqueCandidates.length}`);
  console.log(`Invalid usernames skipped: ${invalidUsers.length}`);
  console.log(`Duplicate normalized usernames skipped: ${duplicates.length}`);

  if (invalidUsers.length > 0) {
    console.log('\nInvalid users:');
    invalidUsers.forEach((user) => {
      console.log(`- uid=${user.uid} username="${user.username}"`);
    });
  }

  if (duplicates.length > 0) {
    console.log('\nDuplicate usernames requiring manual resolution:');
    duplicates.forEach(({ usernameNormalized, values }) => {
      const owners = values.map((value) => `${value.uid}(${value.username})`).join(', ');
      console.log(`- ${usernameNormalized}: ${owners}`);
    });
  }

  if (!shouldCommit) {
    console.log('\nDry run only. Re-run with --commit to write non-conflicting username docs.');
    process.exit(duplicates.length > 0 ? 1 : 0);
  }

  for (let index = 0; index < uniqueCandidates.length; index += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = uniqueCandidates.slice(index, index + BATCH_SIZE);

    for (const candidate of chunk) {
      const now = admin.firestore.FieldValue.serverTimestamp();
      batch.set(
        db.collection('usernames').doc(candidate.usernameNormalized),
        {
          uid: candidate.uid,
          username: candidate.username,
          usernameNormalized: candidate.usernameNormalized,
          email: candidate.email,
          isAnonymous: candidate.isAnonymous,
          createdAt: candidate.createdAt,
          updatedAt: now,
        },
        { merge: true }
      );
      batch.set(
        db.collection('users').doc(candidate.uid),
        {
          usernameNormalized: candidate.usernameNormalized,
          updatedAt: now,
        },
        { merge: true }
      );
    }

    await batch.commit();
    console.log(`Committed ${Math.min(index + BATCH_SIZE, uniqueCandidates.length)} / ${uniqueCandidates.length}`);
  }

  if (duplicates.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
