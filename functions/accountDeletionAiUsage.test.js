const test = require("node:test");
const assert = require("node:assert/strict");

const { deleteAiUsageCounter } = require("./accountDeletion");

// Account deletion removes the per-user AI counter, but the deleted uid's ID token stays valid for
// up to an hour. Deleting today's counter would hand that token a fresh daily limit (TriQ#153).

function fakeDb(initial) {
  const documents = new Map(Object.entries(initial));
  return {
    documents,
    collection: (collection) => ({ doc: (id) => ({ path: `${collection}/${id}` }) }),
    async runTransaction(callback) {
      const deletes = [];
      const result = await callback({
        get: async (reference) => ({
          exists: documents.has(reference.path),
          data: () => documents.get(reference.path),
        }),
        delete: (reference) => deletes.push(reference.path),
      });
      deletes.forEach((path) => documents.delete(path));
      return result;
    },
  };
}

const now = new Date("2026-07-31T10:00:00Z");

test("today's counter stays, so the deleted uid's token gets no fresh daily limit", async () => {
  const db = fakeDb({ "aiUsageDaily/u1": { dayKey: "2026-07-31", counts: { aiQuery: 5 } } });

  await deleteAiUsageCounter({ db, uid: "u1", now });

  assert.equal(db.documents.get("aiUsageDaily/u1").counts.aiQuery, 5);
});

test("an earlier day's counter is deleted", async () => {
  const db = fakeDb({ "aiUsageDaily/u1": { dayKey: "2026-07-30", counts: { aiQuery: 5 } } });

  await deleteAiUsageCounter({ db, uid: "u1", now });

  assert.equal(db.documents.has("aiUsageDaily/u1"), false);
});

test("a counter in an unknown shape is deleted, and a missing one is fine", async () => {
  const db = fakeDb({ "aiUsageDaily/u1": { aiQuery: { day: "2026-10-01", count: 2 } } });

  await deleteAiUsageCounter({ db, uid: "u1", now });
  await deleteAiUsageCounter({ db, uid: "u2", now });

  assert.equal(db.documents.has("aiUsageDaily/u1"), false);
});
