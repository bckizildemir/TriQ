// Replays the server half of each former bug path (issue #151) and checks the fix against the real
// functions/usernameRegistry.js (claimUsername, releaseUsername), with an in-memory Firestore.
// The client half is the order of calls in AuthModel.linkAnonymousAccount / signUp; each
// replay says which client branch it stands for. No network, no Firebase project.
//
//   node .claude/skills/formal-guest-upgrade-identity/replay-server.mjs
//
// Exit 0: every path ends consistent (HOLDS). Exit 1: BROKEN, the bug is back.

import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const { claimUsername, releaseUsername } = require(path.join(here, "../../../functions/usernameRegistry.js"));

const TS = "TS";
const N = "Berke";
const n = "berke";

function fakeDb() {
  const cols = new Map();
  const col = (name) => (cols.has(name) ? cols.get(name) : cols.set(name, new Map()).get(name));
  const snap = (id, data) => ({ id, exists: data !== undefined, data: () => (data === undefined ? undefined : structuredClone(data)) });
  return {
    collection: (name) => ({ doc: (id) => ({ c: name, id, get: async () => snap(id, col(name).get(id)) }) }),
    async runTransaction(cb) {
      const ops = [];
      await cb({
        get: async (ref) => snap(ref.id, col(ref.c).get(ref.id)),
        set: (ref, data, o = {}) => ops.push({ t: "set", ref, data: structuredClone(data), merge: o.merge === true }),
        delete: (ref) => ops.push({ t: "delete", ref }),
      });
      for (const op of ops) {
        const c = col(op.ref.c);
        if (op.t === "delete") c.delete(op.ref.id);
        else c.set(op.ref.id, op.merge ? { ...(c.get(op.ref.id) || {}), ...op.data } : op.data);
      }
    },
    // LiveAuthUserDocumentManager.deleteUserAndAuth: users/<uid> only.
    deleteUserDoc: (uid) => col("users").delete(uid),
    doc: (c, id) => col(c).get(id),
    seed: (c, id, data) => col(c).set(id, data),
  };
}

const guestDoc = { username: "Guest User", usernameNormalized: "guest user", email: "", isAnonymous: true };
const claim = (db, uid, isAnonymous, extra = {}) =>
  claimUsername({ db, user: { uid }, username: N, email: "a@b.co", isAnonymous, createServerTimestamp: () => TS, ...extra });
const release = (db, uid, restore) =>
  releaseUsername({ db, user: { uid }, username: N, ...restore, createServerTimestamp: () => TS });

let failed = 0;
function holds(name, ok, detail) {
  console.log(`${ok ? "HOLDS     " : "BROKEN    "}  ${name}\n            ${detail}`);
  if (!ok) failed += 1;
}

// NameStaysWithItsHolder: a claim never takes N from a permanent account that holds it.
{
  const db = fakeDb();
  await claimUsername({ db, user: { uid: "o" }, username: N, email: "o@b.co", isAnonymous: false, createServerTimestamp: () => TS });
  let refused = false;
  try {
    await claim(db, "g", true, { isReclaimableHolder: async () => null });
  } catch (e) {
    refused = /already taken/.test(e.message);
  }
  holds(
    "NameStaysWithItsHolder (the Guest claims a name a permanent account holds)",
    refused && db.doc("usernames", n)?.uid === "o",
    `claim refused: ${refused}; usernames/${n}.uid=${db.doc("usernames", n)?.uid}.`,
  );
}

// Finding 1: claim 1 commits, the answer is lost; the client now calls releaseUsername with the
// Guest profile it read first.
{
  const db = fakeDb();
  db.seed("users", "g", { ...guestDoc });
  await claim(db, "g", true);
  await release(db, "g", { restoreUsername: "Guest User", restoreEmail: "", restoreIsAnonymous: true });
  const user = db.doc("users", "g");
  holds(
    "FailedUpgradeLeavesNoName (claim 1 answer lost, client releases)",
    db.doc("usernames", n) === undefined && user.username === "Guest User" && user.isAnonymous === true,
    `usernames/${n} exists=${db.doc("usernames", n) !== undefined}; users/g.username=${user.username}.`,
  );
}

// Finding 1, app killed before the release: the next claim takes the idle Guest's name over and
// puts the placeholder on the Guest's profile.
{
  const db = fakeDb();
  db.seed("users", "g", { ...guestDoc });
  await claim(db, "g", true);
  await claim(db, "o", false, { isReclaimableHolder: async (uid) => (uid === "g" ? "anonymous" : null) });
  const user = db.doc("users", "g");
  holds(
    "NoOrphanAfterUpgrade (Guest killed after claim 1, someone else claims the name)",
    db.doc("usernames", n)?.uid === "o" && user.username === "Guest User",
    `usernames/${n}.uid=${db.doc("usernames", n)?.uid}; users/g.username=${user.username}.`,
  );
}

// Finding 2: release without any restore data must not leave the name on the profile.
{
  const db = fakeDb();
  db.seed("users", "g", { ...guestDoc });
  await claim(db, "g", true);
  await release(db, "g", {});
  const gName = db.doc("users", "g").username;
  holds(
    "ShownNameIsHeld (release without restore data)",
    gName === "Guest User" && db.doc("usernames", n) === undefined,
    `users/g.username=${gName} after release; usernames/${n} exists=${db.doc("usernames", n) !== undefined}.`,
  );
}

// Finding 3: link succeeded; the client no longer releases. Claim 2 repeated gives the same result.
{
  const db = fakeDb();
  db.seed("users", "g", { ...guestDoc });
  await claim(db, "g", true);
  await claim(db, "g", false);
  await claim(db, "g", false);
  const user = db.doc("users", "g");
  holds(
    "UpgradedAccountKeepsItsName (claim 2 repeated after the link)",
    db.doc("usernames", n)?.uid === "g" && user.username === N && user.isAnonymous === false,
    `usernames/${n}.uid=${db.doc("usernames", n)?.uid}; users/g.username=${user.username}, isAnonymous=${user.isAnonymous}.`,
  );
}

// Finding 4: the sign-up claim commits, the answer is lost; the client releases before deleting.
{
  const db = fakeDb();
  await claim(db, "s", false);
  await release(db, "s", {});
  db.deleteUserDoc("s");
  let otherGot = false;
  try {
    await claim(db, "o", false);
    otherGot = db.doc("usernames", n)?.uid === "o";
  } catch {}
  holds("NoOrphanAfterSignUp (release before delete)", otherGot, `someone else claims ${N}: ${otherGot}.`);
}

// Finding 4, the release failed: the deleted account's name is taken over.
{
  const db = fakeDb();
  await claim(db, "s", false);
  db.deleteUserDoc("s");
  // Firebase Auth says the user is gone (index.js isAccountGoneOrAnonymous).
  await claim(db, "o", false, { isReclaimableHolder: async (uid) => (uid === "s" ? "gone" : null) });
  holds(
    "NoOrphanAfterSignUp (release failed, account deleted)",
    db.doc("usernames", n)?.uid === "o",
    `usernames/${n}.uid=${db.doc("usernames", n)?.uid}.`,
  );
}

process.exit(failed ? 1 : 0);
