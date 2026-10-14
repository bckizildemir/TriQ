// Runs deleteOwnAccountData (TriQ#88) against the local Firestore, Storage and Auth emulators with
// the admin SDK. Run with `npm run test:rules`; the project id is a demo- id, so nothing reaches a real
// Firebase project. It uses its own project id, so the rules spec's clearFirestore() in the same
// emulator run cannot wipe this suite's data.
const assert = require("node:assert/strict");
const { after, before, beforeEach, describe, test } = require("node:test");
const admin = require("firebase-admin");
const { Timestamp } = require("firebase-admin/firestore");

const PROJECT_ID = "demo-ttb-account-deletion";
const BUCKET = `${PROJECT_ID}.appspot.com`;

let db;
let bucket;
let auth;
let deleteAccount;

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "run inside `firebase emulators:exec`");
  assert.ok(process.env.FIREBASE_STORAGE_EMULATOR_HOST, "run inside `firebase emulators:exec`");
  assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST, "run inside `firebase emulators:exec`");
  process.env.STORAGE_EMULATOR_HOST = `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}`;
  admin.initializeApp({ projectId: PROJECT_ID, storageBucket: BUCKET });
  db = admin.firestore();
  bucket = admin.storage().bucket();
  auth = admin.auth();
  const { deleteOwnAccountData } = require("../accountDeletion");
  deleteAccount = (uid) => deleteOwnAccountData({ db, bucket, auth, uid });
});

after(async () => {
  await admin.app().delete();
});

beforeEach(async () => {
  await clearFirestore();
  await clearAuth();
  await bucket.deleteFiles({ force: true });
  await seedWorld();
});

async function clearAuth() {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}/accounts`,
    { method: "DELETE" }
  );
  assert.ok(response.ok, `clearing the Auth emulator failed: ${response.status}`);
}

async function authUserExists(uid) {
  try {
    await auth.getUser(uid);
    return true;
  } catch (error) {
    if (error.code === "auth/user-not-found") {
      return false;
    }
    throw error;
  }
}

async function clearFirestore() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
    { method: "DELETE" }
  );
  assert.ok(response.ok, `clearing the Firestore emulator failed: ${response.status}`);
}

const answeredAt = Timestamp.fromDate(new Date("2026-10-01T10:00:00Z"));
const PROFILE_URL = "https://firebasestorage.googleapis.com/v0/b/x/o/profiles%2Falice%2Fprofile.jpg?alt=media&token=t";

// alice is the caller. bob and carol are other users whose data must survive, except the parts
// the brief names: their answers (and images and favorites) on alice's own questions, and alice's
// question ids in their lists.
async function seedWorld() {
  const docs = {
    "users/alice": { username: "Alice", usernameNormalized: "alice", profileImageURL: PROFILE_URL },
    "users/alice/aiQueries/q1": { question: "hi" },
    "users/alice/aiUsage/stats": { count: 3 },
    "users/alice/notificationDevices/d1": { isPushEligible: true },
    "users/bob": { username: "Bob", usernameNormalized: "bob" },
    "users/bob/aiUsage/stats": { count: 1 },
    "usernames/alice": { uid: "alice", username: "Alice" },
    "usernames/alice-old": { uid: "alice", username: "Alice-Old" },
    "usernames/bob": { uid: "bob", username: "Bob" },
    "aiUsageDaily/alice": { aiQuery: { day: "2026-10-01", count: 2 } },
    "aiUsageDaily/bob": { aiQuery: { day: "2026-10-01", count: 1 } },

    // A seeded question both alice and bob answered and favorited.
    "questions/seeded1": {
      source: "seeded",
      favoriteUserIds: ["alice", "bob"],
      answerStats: { 0: { tea: 2 }, 1: { cake: 1, pie: 1 } },
      totalRespondents: 2,
      todayRespondents: 0,
      todayDate: "",
      lastAnsweredAt: answeredAt,
    },
    "questions/seeded1/userAnswers/alice": { userId: "alice", answers: ["tea", "cake"], answeredAt },
    "questions/seeded1/userAnswers/bob": { userId: "bob", answers: ["tea", "pie"], answeredAt },

    // alice's own community question, answered and favorited by bob.
    "questions/aliceQ": {
      source: "userCreated",
      createdBy: "alice",
      moderationStatus: "approved",
      favoriteUserIds: ["bob"],
      totalRespondents: 2,
    },
    "questions/aliceQ/userAnswers/alice": { userId: "alice", answers: ["a"], answeredAt },
    "questions/aliceQ/userAnswers/bob": { userId: "bob", answers: ["b"], answeredAt },
    "questions/bobQ": { source: "userCreated", createdBy: "bob", moderationStatus: "approved" },
    // An official question alice added as an admin: it belongs to the app, not to alice.
    "questions/officialQ": { source: "seeded", createdBy: "alice" },
    "questions/officialQ/userAnswers/bob": { userId: "bob", answers: ["c"], answeredAt },

    "questionLists/aliceList": { ownerId: "alice", name: "Mine", questionIds: ["seeded1", "aliceQ"] },
    "questionLists/bobList": { ownerId: "bob", name: "Bob's", questionIds: ["seeded1", "aliceQ", "bobQ"] },

    // alice's share, which bob accepted.
    "questionListShares/aliceShare": {
      ownerId: "alice", sourceListId: "aliceList", shareCode: "ALICE1", status: "active",
      isLinkEnabled: true, acceptedRecipientCount: 1, updatedAt: answeredAt,
    },
    "questionListShares/aliceShare/recipients/bob": {
      recipientId: "bob", status: "accepted", updatedAt: answeredAt,
    },
    // bob's share of bobList, accepted by alice and carol. It copies alice's question and the
    // answers to it: bob's own (ownerAnswerSnapshots) and carol's reply.
    "questionListShares/bobShare": {
      ownerId: "bob", sourceListId: "bobList", shareCode: "BOB111", status: "active",
      isLinkEnabled: true, acceptedRecipientCount: 2, updatedAt: answeredAt,
      questionIds: ["seeded1", "aliceQ", "bobQ"],
      includeOwnerAnswers: true,
      ownerAnswerSnapshots: { seeded1: ["tea", "pie"], aliceQ: ["b"] },
    },
    "questionListShares/bobShare/recipients/alice": {
      recipientId: "alice", recipientDisplayName: "Alice", status: "accepted", updatedAt: answeredAt,
    },
    "questionListShares/bobShare/recipients/carol": {
      recipientId: "carol", status: "accepted", updatedAt: answeredAt,
      latestReplyAnswerSnapshots: { seeded1: ["x"], aliceQ: ["y"] },
    },
    // carol's share, which alice accepted and then left.
    "questionListShares/carolShare": {
      ownerId: "carol", sourceListId: "carolList", shareCode: "CAROL1", status: "active",
      isLinkEnabled: true, acceptedRecipientCount: 0, updatedAt: answeredAt,
    },
    "questionListShares/carolShare/recipients/alice": {
      recipientId: "alice", status: "left", updatedAt: answeredAt,
    },
    // dave's revoked share, which alice had accepted.
    "questionListShares/daveShare": {
      ownerId: "dave", sourceListId: "daveList", shareCode: "DAVE11", status: "revoked",
      isLinkEnabled: false, acceptedRecipientCount: 0, updatedAt: answeredAt,
    },
    "questionListShares/daveShare/recipients/alice": {
      recipientId: "alice", status: "revoked", updatedAt: answeredAt,
    },
  };

  const batch = db.batch();
  for (const [path, data] of Object.entries(docs)) {
    batch.set(db.doc(path), data);
  }
  await batch.commit();

  await auth.createUser({ uid: "alice", email: "alice@example.com", password: "secret-1" });
  await auth.createUser({ uid: "bob", email: "bob@example.com", password: "secret-2" });

  const files = [
    "profiles/alice/profile.jpg",
    "profiles/bob/profile.jpg",
    "answers/alice/seeded1/slot_0.jpg",
    "answers/alice/aliceQ/slot_1.jpg",
    "answers/alice/goneQuestion/slot_2.jpg",
    "answers/bob/seeded1/slot_0.jpg",
    "answers/bob/aliceQ/slot_0.jpg",
  ];
  await Promise.all(files.map((name) =>
    bucket.file(name).save(Buffer.from("jpeg"), { contentType: "image/jpeg", resumable: false })
  ));
}

async function exists(path) {
  return (await db.doc(path).get()).exists;
}

async function data(path) {
  return (await db.doc(path).get()).data();
}

async function fileExists(name) {
  const [found] = await bucket.file(name).exists();
  return found;
}

describe("deleteOwnAccountData", () => {
  test("deletes every item the caller owns", async () => {
    const result = await deleteAccount("alice");

    assert.equal(result.success, true);
    assert.equal(result.profileImageURL, PROFILE_URL);
    assert.equal(result.authUserDeleted, true);
    assert.equal(await authUserExists("alice"), false, "the Auth user should be deleted");

    for (const path of [
      "users/alice",
      "users/alice/aiQueries/q1",
      "users/alice/aiUsage/stats",
      "users/alice/notificationDevices/d1",
      "usernames/alice",
      "usernames/alice-old",
      "aiUsageDaily/alice",
      "questions/seeded1/userAnswers/alice",
      "questions/aliceQ",
      "questions/aliceQ/userAnswers/alice",
      "questionLists/aliceList",
      "questionListShares/aliceShare",
      "questionListShares/aliceShare/recipients/bob",
      "questionListShares/bobShare/recipients/alice",
      "questionListShares/carolShare/recipients/alice",
      "questionListShares/daveShare/recipients/alice",
    ]) {
      assert.equal(await exists(path), false, `${path} should be deleted`);
    }

    for (const name of [
      "profiles/alice/profile.jpg",
      "answers/alice/seeded1/slot_0.jpg",
      "answers/alice/aliceQ/slot_1.jpg",
      "answers/alice/goneQuestion/slot_2.jpg",
    ]) {
      assert.equal(await fileExists(name), false, `${name} should be deleted`);
    }

    // The share link resolves through the share document's shareCode, so it is gone too.
    const linkQuery = await db.collection("questionListShares").where("shareCode", "==", "ALICE1").get();
    assert.equal(linkQuery.size, 0);
  });

  test("removes other users' answers, images and favorites on the caller's own questions", async () => {
    await deleteAccount("alice");

    assert.equal(await exists("questions/aliceQ/userAnswers/bob"), false);
    assert.equal(await fileExists("answers/bob/aliceQ/slot_0.jpg"), false);
    assert.deepEqual((await data("questionLists/bobList")).questionIds, ["seeded1", "bobQ"]);
  });

  test("removes the caller's questions and the answers copied with them from other users' shares", async () => {
    await deleteAccount("alice");

    const share = await data("questionListShares/bobShare");
    assert.deepEqual(share.questionIds, ["seeded1", "bobQ"]);
    assert.deepEqual(share.ownerAnswerSnapshots, { seeded1: ["tea", "pie"] });
    assert.equal(share.shareCode, "BOB111");
    assert.deepEqual(
      (await data("questionListShares/bobShare/recipients/carol")).latestReplyAnswerSnapshots,
      { seeded1: ["x"] }
    );
  });

  test("leaves other users' data alone", async () => {
    await deleteAccount("alice");

    for (const path of [
      "users/bob",
      "users/bob/aiUsage/stats",
      "usernames/bob",
      "aiUsageDaily/bob",
      "questions/seeded1/userAnswers/bob",
      "questions/bobQ",
      "questions/officialQ",
      "questions/officialQ/userAnswers/bob",
      "questionListShares/daveShare",
      "questionLists/bobList",
      "questionListShares/bobShare/recipients/carol",
      "questionListShares/carolShare",
    ]) {
      assert.equal(await exists(path), true, `${path} should stay`);
    }
    assert.equal(await authUserExists("bob"), true, "another user's Auth account should stay");

    for (const name of ["profiles/bob/profile.jpg", "answers/bob/seeded1/slot_0.jpg"]) {
      assert.equal(await fileExists(name), true, `${name} should stay`);
    }

    const seeded = await data("questions/seeded1");
    assert.deepEqual(seeded.favoriteUserIds, ["bob"]);
    assert.equal(seeded.totalRespondents, 1);
    assert.deepEqual(seeded.answerStats, { 0: { tea: 1 }, 1: { pie: 1 } });

    assert.equal((await data("questionListShares/bobShare")).acceptedRecipientCount, 1);
    assert.equal((await data("questionListShares/carolShare")).acceptedRecipientCount, 0);
  });

  test("a second run succeeds and finds nothing left", async () => {
    const first = await deleteAccount("alice");
    const second = await deleteAccount("alice");

    assert.equal(second.success, true);
    assert.equal(second.profileImageURL, null);
    // The Auth user is already gone; that counts as done, not as a failure.
    assert.equal(first.authUserDeleted, true);
    assert.equal(second.authUserDeleted, false);
    for (const [key, count] of Object.entries(second.counts)) {
      assert.equal(count, 0, `second run counted ${count} ${key}`);
    }
    assert.ok(first.counts.answers > 0);
    assert.equal((await data("questionListShares/bobShare")).acceptedRecipientCount, 1);
    assert.equal((await data("questions/seeded1")).totalRespondents, 1);
  });

  test("an unauthenticated caller is refused before anything is deleted", async () => {
    await assert.rejects(
      () => deleteAccount(undefined),
      (error) => error.code === "unauthenticated"
    );
    assert.equal(await exists("users/alice"), true);
    assert.equal(await authUserExists("alice"), true);
  });
});

test("the suite ran against the emulators", () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST);
});
