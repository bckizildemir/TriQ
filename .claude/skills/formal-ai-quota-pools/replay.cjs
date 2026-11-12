// Replays the two known findings against the real consumeDailyQuota, one call per model step,
// with an in-memory Firestore whose runTransaction runs one transaction at a time (the model's
// QuotaTransaction). Needs functions/node_modules (run `npm ci` in functions/ first).
//
// usage: node .claude/skills/formal-ai-quota-pools/replay.cjs
const path = require("node:path");
const root = path.resolve(__dirname, "../../..");
const { consumeDailyQuota, AI_QUERY_GROUP, USAGE_COLLECTION } = require(path.join(root, "functions/aiUsageLimit.js"));

function fakeDb() {
  const documents = new Map();
  const ref = (collection, id) => ({ key: `${collection}/${id}` });
  return {
    documents,
    collection: (collection) => ({ doc: (id) => ref(collection, id) }),
    async runTransaction(work) {
      const writes = [];
      const result = await work({
        get: async (r) => ({ exists: documents.has(r.key), data: () => documents.get(r.key) }),
        set: (r, value) => writes.push([r.key, value]),
      });
      for (const [key, value] of writes) documents.set(key, value);
      return result;
    },
  };
}

async function attempt(db, now, label) {
  try {
    const r = await consumeDailyQuota({ db, uid: "guest-1", group: AI_QUERY_GROUP, isAnonymous: true, isGuest: true, now: new Date(now) });
    console.log(`  ${label}: let through (${r.used}/${r.limit}) -> provider called`);
    return 1;
  } catch (error) {
    console.log(`  ${label}: refused (${error.details?.reason})`);
    return 0;
  }
}

(async () => {
  let failures = 0;

  console.log("Finding 1: a call stamped before UTC midnight commits after a call stamped after it");
  {
    const db = fakeDb();
    let day1 = 0;
    for (let i = 0; i < 5; i++) day1 += await attempt(db, `2026-07-31T23:59:5${i}.000Z`, `call ${i + 1}`);
    day1 += await attempt(db, "2026-07-31T23:59:58.000Z", "call 6 (refused, as it should be)");
    await attempt(db, "2026-08-01T00:00:00.100Z", "call 7 (next day)");
    day1 += await attempt(db, "2026-07-31T23:59:59.000Z", "call 8 (stamped before midnight, commits after call 7)");
    console.log(`  provider calls for 2026-07-31: ${day1} > 5`);
    if (day1 > 5) failures++;
  }

  console.log("Finding 2: account deletion removes the counter while the uid's ID token still works");
  {
    const db = fakeDb();
    let today = 0;
    for (let i = 0; i < 6; i++) today += await attempt(db, `2026-07-31T10:00:0${i}.000Z`, `call ${i + 1}`);
    db.documents.delete(`${USAGE_COLLECTION}/guest-1`); // deleteOwnAccountData: recursiveDelete(aiUsageDaily/{uid})
    console.log("  deleteOwnAccountData ran; the ID token is still valid (onCall does not check revocation)");
    for (let i = 0; i < 6; i++) today += await attempt(db, `2026-07-31T10:05:0${i}.000Z`, `call ${i + 7}`);
    console.log(`  provider calls for 2026-07-31: ${today} > 5`);
    if (today > 5) failures++;
  }

  console.log(failures === 2 ? "Both findings reproduce on the real code." : `Reproduced ${failures} of 2.`);
})();
