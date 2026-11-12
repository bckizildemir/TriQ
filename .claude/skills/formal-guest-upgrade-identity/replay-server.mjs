// Replays the server half of each bug path the TLA+ model reports against the real
// functions/usernameRegistry.js (claimUsername, releaseUsername), with an in-memory Firestore.
// The client half is the order of calls in AuthModel.linkAnonymousAccount / signUp; each
// replay says which client branch it stands for. No network, no Firebase project.
//
//   node .claude/skills/formal-guest-upgrade-identity/replay-server.mjs
//
// Exit 0: the rule that holds still holds (HOLDS) and every finding still reproduces (REPRODUCES).
// Exit 1: BROKEN or GONE: the code changed; re-read the model before trusting it.

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
const claim = (db, uid, isAnonymous) =>
  claimUsername({ db, user: { uid }, username: N, email: "a@b.co", isAnonymous, createServerTimestamp: () => TS });
const release = (db, uid, restore) =>
  releaseUsername({ db, user: { uid }, username: N, ...restore, createServerTimestamp: () => TS });

let failed = 0;
function report(name, ok, detail) {
  console.log(`${ok ? "REPRODUCES" : "GONE      "}  ${name}\n            ${detail}`);
  if (!ok) failed += 1;
}
function holds(name, ok, detail) {
  console.log(`${ok ? "HOLDS     " : "BROKEN    "}  ${name}\n            ${detail}`);
  if (!ok) failed += 1;
}

// NameStaysWithItsHolder (holds): a claim never takes N from the account that holds it (:96).
{
  const db = fakeDb();
  await claimUsername({ db, user: { uid: "o" }, username: N, email: "o@b.co", isAnonymous: false, createServerTimestamp: () => TS });
  let refused = false;
  try {
    await claim(db, "g", true);
  } catch (e) {
    refused = /already taken/.test(e.message);
  }
  holds(
    "NameStaysWithItsHolder (the Guest claims a name someone else holds)",
    refused && db.doc("usernames", n)?.uid === "o",
    `claim refused: ${refused}; usernames/${n}.uid=${db.doc("usernames", n)?.uid}.`,
  );
}

// FailedUpgradeLeavesNoName / NoOrphanAfterUpgrade: claim 1 (:350) commits, the client throws
// before the inner do/catch, so releaseUsername is never called.
{
  const db = fakeDb();
  db.seed("users", "g", { ...guestDoc });
  await claim(db, "g", true);
  const reg = db.doc("usernames", n);
  const user = db.doc("users", "g");
  report(
    "FailedUpgradeLeavesNoName + NoOrphanAfterUpgrade (claim 1 answer lost, no release)",
    reg?.uid === "g" && user.username === N && user.isAnonymous === true,
    `usernames/${n}.uid=${reg?.uid}; users/g.username=${user.username}, isAnonymous=${user.isAnonymous}. ` +
      "Nothing on the server frees it when the Guest signs out.",
  );
}

// ShownNameIsHeld: profileSnapshot (:348, try?) came back nil, link fails, release with no restore.
{
  const db = fakeDb();
  db.seed("users", "g", { ...guestDoc });
  await claim(db, "g", true);
  await release(db, "g", {}); // restoreUsername/Email/IsAnonymous all nil
  let otherGot = false;
  try {
    await claimUsername({ db, user: { uid: "o" }, username: N, email: "o@b.co", isAnonymous: false, createServerTimestamp: () => TS });
    otherGot = db.doc("usernames", n)?.uid === "o";
  } catch {}
  const gName = db.doc("users", "g").username;
  report(
    "ShownNameIsHeld (profile read nil, link fails, release without restore)",
    gName === N && otherGot,
    `users/g.username=${gName} after release; someone else then claims ${N}: ${otherGot}. Two profiles show ${N}.`,
  );
}

// UpgradedAccountKeepsItsName: link succeeded, forceRefreshIDToken (:358) or claim 2 (:359)
// throws, the catch releases N and restores the Guest profile on a now-permanent account.
{
  const db = fakeDb();
  db.seed("users", "g", { ...guestDoc });
  await claim(db, "g", true);
  // (linkAccount succeeded here on the client; the Auth user is permanent from now on.)
  await release(db, "g", { restoreUsername: "Guest User", restoreEmail: "", restoreIsAnonymous: true });
  const user = db.doc("users", "g");
  const reg = db.doc("usernames", n);
  report(
    "UpgradedAccountKeepsItsName (link ok, token refresh fails, release)",
    reg === undefined && user.username === "Guest User" && user.isAnonymous === true,
    `usernames/${n} exists=${reg !== undefined}; users/g.username=${user.username}, isAnonymous=${user.isAnonymous} ` +
      "on an account Firebase Auth now treats as permanent.",
  );
}

// NoOrphanAfterSignUp: signUp claim (:277) commits, the client gets an error, :283
// deleteUserAndAuth removes users/s and the Auth user but not usernames/N.
{
  const db = fakeDb();
  await claim(db, "s", false);
  db.deleteUserDoc("s");
  let otherRefused = false;
  try {
    await claimUsername({ db, user: { uid: "o" }, username: N, email: "o@b.co", isAnonymous: false, createServerTimestamp: () => TS });
  } catch (e) {
    otherRefused = /already taken/.test(e.message);
  }
  report(
    "NoOrphanAfterSignUp (sign-up claim answer lost, account deleted)",
    db.doc("usernames", n)?.uid === "s" && db.doc("users", "s") === undefined && otherRefused,
    `usernames/${n}.uid=${db.doc("usernames", n)?.uid} for a deleted account; anyone else claiming ${N} gets "already taken": ${otherRefused}.`,
  );
}

process.exit(failed ? 1 : 0);
