// Replays the model's two former counterexamples on the real callables, with the fake
// Firestore from functions/questionListShares.test.js. Run through check.sh --replay (sets
// WT to the repo root). Both were fixed in #152; each test passes while the fix holds and
// fails if a callable lets the old interleaving through again.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const Q = require(path.join(process.env.WT, "functions/questionListShares.js"));
const testSource = fs.readFileSync(path.join(process.env.WT, "functions/questionListShares.test.js"), "utf8");
const { createFakeDb } = new Function(
  `${testSource.slice(testSource.indexOf("function createFakeDb("))}\nreturn { createFakeDb };`
)();
const ts = () => "now";
const owner = { uid: "owner" }, r1 = { uid: "r1" };

async function sharedDb() {
  const db = createFakeDb({
    "questionLists/list-1": { ownerId: "owner", name: "Trip", questionIds: ["q1"] },
    "users/owner": { username: "owner" }, "users/r1": { username: "r1" },
    "questions/q1/userAnswers/r1": { answers: ["a", "", ""] },
  });
  const created = await Q.createQuestionListShare({ db, user: owner, data: { listId: "list-1" }, createServerTimestamp: ts, createShareCode: () => "code1" });
  return { db, shareId: created.shareId };
}

test("ReplacedLinkAdmitsNoOne holds: regenerate lands between accept's code lookup and its transaction", async () => {
  const { db, shareId } = await sharedDb();
  await Q.previewQuestionListShare({ db, user: r1, data: { shareCode: "code1" } });   // r1 opens link 1
  const realRun = db.runTransaction.bind(db);
  let once = true;
  db.runTransaction = async (cb) => {
    if (once) { once = false;   // accept found the share by code1; now the owner regenerates
      await Q.regenerateQuestionListShareLink({ db, user: owner, data: { shareId }, createServerTimestamp: ts, createShareCode: () => "code2" });
    }
    return realRun(cb);
  };
  await assert.rejects(() => Q.acceptQuestionListShare({ db, user: r1, data: { shareCode: "code1" }, createServerTimestamp: ts }),
    (e) => e.code === "failed-precondition");
  db.runTransaction = realRun;
  assert.equal(db.getDocument(`questionListShares/${shareId}`).shareCode, "code2");
  assert.equal(db.getDocument(`questionListShares/${shareId}/recipients/r1`), undefined,
    "r1 must not get in through link 1 after the owner replaced it");
});

for (const exit of ["leave", "revoke"]) {
  test(`NoReplyAfterLeavingOrRevocation holds: ${exit} lands while Send Answers is in flight`, async () => {
    const { db, shareId } = await sharedDb();
    await Q.acceptQuestionListShare({ db, user: r1, data: { shareCode: "code1" }, createServerTimestamp: ts });
    const realCollection = db.collection.bind(db);
    let once = true;
    db.collection = (name) => {
      const c = realCollection(name);
      if (name !== "questions" || !once) return c;
      once = false;   // the reply passed both checks and is reading r1's answers
      return { doc: (id) => ({ collection: (n) => ({ doc: (u) => ({ get: async () => {
        if (exit === "leave") await Q.leaveQuestionListShare({ db, user: r1, data: { shareId }, createServerTimestamp: ts });
        else await Q.revokeQuestionListShare({ db, user: owner, data: { shareId }, createServerTimestamp: ts });
        return c.doc(id).collection(n).doc(u).get();
      } }) }) }) };
    };
    await assert.rejects(() => Q.sendQuestionListShareReply({ db, user: r1, data: { shareId }, createServerTimestamp: ts }));
    const rec = db.getDocument(`questionListShares/${shareId}/recipients/r1`);
    assert.equal(rec.status, exit === "leave" ? "left" : "revoked");
    assert.notEqual(rec.unreadByOwner, true, "no new unread reply after r1 left / after revoke");
    assert.deepEqual(rec.latestReplyAnswerSnapshots, {});
  });
}
