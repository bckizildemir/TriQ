// Replays the two findings (fixed in TriQ#153) against the real consumeDailyQuota, one call per model step,
// with an in-memory Firestore whose runTransaction runs one transaction at a time (the model's
// QuotaTransaction). Needs functions/node_modules (run `npm ci` in functions/ first).
//
// usage: node .claude/skills/formal-ai-quota-pools/replay.cjs
const path = require("node:path");
const root = path.resolve(__dirname, "../../..");
const { consumeDailyQuota, AI_QUERY_GROUP, USAGE_COLLECTION } = require(path.join(root, "functions/aiUsageLimit.js"));
const { deleteAiUsageCounter } = require(path.join(root, "functions/accountDeletion.js"));

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
        delete: (r) => writes.push([r.key, undefined]),
      });
      for (const [key, value] of writes) {
        if (value === undefined) documents.delete(key);
        else documents.set(key, value);
      }
      return result;
    },
  };
}

// `now` is a clock function, as withDailyQuota passes it: the day is read inside the transaction.
async function attempt(db, clock, label) {
  try {
    const r = await consumeDailyQuota({ db, uid: "guest-1", group: AI_QUERY_GROUP, isAnonymous: true, isGuest: true, now: () => new Date(clock.time) });
    console.log(`  ${label}: let through (${r.used}/${r.limit}) -> provider called`);
    return 1;
  } catch (error) {
    console.log(`  ${label}: refused (${error.details?.reason})`);
    return 0;
  }
}

(async () => {
  let failures = 0;

  console.log("Finding 1: a call that waits on the counter across UTC midnight");
  {
    const db = fakeDb();
    const clock = { time: "2026-07-31T23:59:50.000Z" };
    let day1 = 0;
    for (let i = 0; i < 5; i++) day1 += await attempt(db, clock, `call ${i + 1}`);
    // Call 6 starts before midnight but its transaction waits; call 7 commits first.
    let release;
    const gate = new Promise((resolve) => { release = resolve; });
    const slowDb = { ...db, runTransaction: async (work) => { await gate; return db.runTransaction(work); } };
    clock.time = "2026-07-31T23:59:59.000Z";
    const late = attempt(slowDb, clock, "call 6 (waits)");
    clock.time = "2026-08-01T00:00:00.100Z";
    await attempt(db, clock, "call 7 (next day)");
    release();
    await late;
    const stored = db.documents.get(`${USAGE_COLLECTION}/guest-1`);
    console.log(`  stored: ${stored.dayKey} count ${stored.counts[AI_QUERY_GROUP]}`);
    if (stored.dayKey !== "2026-08-01" || stored.counts[AI_QUERY_GROUP] !== 2) failures++;
  }

  console.log("Finding 2: account deletion while the uid's ID token still works");
  {
    const db = fakeDb();
    const clock = { time: "2026-07-31T10:00:00.000Z" };
    let today = 0;
    for (let i = 0; i < 6; i++) today += await attempt(db, clock, `call ${i + 1}`);
    await deleteAiUsageCounter({ db, uid: "guest-1", now: new Date(clock.time) });
    console.log("  deleteOwnAccountData ran; the ID token is still valid (onCall does not check revocation)");
    for (let i = 0; i < 6; i++) today += await attempt(db, clock, `call ${i + 7}`);
    console.log(`  provider calls for 2026-07-31: ${today} (limit 5)`);
    if (today > 5) failures++;
  }

  console.log(failures === 0 ? "Neither finding reproduces: the per-uid limit holds." : `${failures} of 2 findings still reproduce.`);
  process.exit(failures === 0 ? 0 : 1);
})();
