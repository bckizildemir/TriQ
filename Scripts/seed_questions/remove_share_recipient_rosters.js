#!/usr/bin/env node

/**
 * Removes the denormalized recipientIds roster from question list share documents and
 * repairs acceptedRecipientCount from the recipients subcollection.
 *
 * Accepted recipients can read the whole share document, so a roster stored there let every
 * recipient enumerate the others. Recipient identities now live only in the recipients
 * subcollection, which recipients cannot read. Share documents written before that change
 * still carry the field, so it has to be deleted from existing data.
 *
 * Usage:
 *   node remove_share_recipient_rosters.js --dry-run
 *   node remove_share_recipient_rosters.js --commit
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

async function acceptedRecipientCount(shareRef) {
  const snapshot = await shareRef.collection('recipients')
    .where('status', '==', 'accepted')
    .get();
  return snapshot.size;
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
  const snapshot = await db.collection('questionListShares').get();

  const updates = [];
  let rosterCount = 0;
  let driftedCount = 0;

  for (const document of snapshot.docs) {
    const data = document.data() || {};
    const patch = {};

    if (Object.hasOwn(data, 'recipientIds')) {
      patch.recipientIds = admin.firestore.FieldValue.delete();
      rosterCount += 1;
    }

    const actual = await acceptedRecipientCount(document.ref);
    if (data.acceptedRecipientCount !== actual) {
      patch.acceptedRecipientCount = actual;
      driftedCount += 1;
    }

    if (Object.keys(patch).length > 0) {
      updates.push({
        ref: document.ref,
        id: document.id,
        stored: data.acceptedRecipientCount,
        actual,
        data: patch,
      });
    }
  }

  console.log(`Share documents scanned: ${snapshot.size}`);
  console.log(`Documents still exposing a recipientIds roster: ${rosterCount}`);
  console.log(`Documents with a drifted acceptedRecipientCount: ${driftedCount}`);
  console.log(`Documents needing updates: ${updates.length}`);

  updates.slice(0, 10).forEach((update) => {
    const fields = Object.keys(update.data).join(', ');
    console.log(`- ${update.id}: ${fields} (count stored ${update.stored} -> ${update.actual})`);
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
