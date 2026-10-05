// Runs firestore.rules and storage.rules in the local emulators and tries each attack from the
// 2026-10-06 rules audit. Run with `npm run test:rules` (the project id is a demo- id, so nothing
// reaches a real Firebase project).
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { after, before, beforeEach, describe, test } = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const firebase = require("firebase/compat/app");
require("firebase/compat/firestore");

const root = path.join(__dirname, "..", "..");
const serverTimestamp = () => firebase.firestore.FieldValue.serverTimestamp();
const permanent = { firebase: { sign_in_provider: "password" }, email: "user@example.com" };

let testEnv;

function db(uid, token = permanent) {
  return testEnv.authenticatedContext(uid, token).firestore();
}

async function seed(write) {
  await testEnv.withSecurityRulesDisabled(async (context) => write(context.firestore()));
}

// The fields AuthModelDependencies.defaultUserData sends for a new user.
function defaultUserData(overrides = {}) {
  return {
    username: "Guest User",
    usernameNormalized: "guest user",
    email: "",
    isAnonymous: true,
    dailyAnswers: 0,
    weeklyAnswers: 0,
    totalAnswered: 0,
    completedQuestionIds: [],
    categoryAnswers: {},
    currentStreak: 0,
    unlockedBadges: [],
    badgeProgress: {},
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

// The fields Question.toFirestore sends for a user-created question.
function userQuestion(uid, overrides = {}) {
  return {
    text: "What would you take to a desert island?",
    category: "general",
    contentId: "content-1",
    source: "userCreated",
    createdAt: new Date(),
    createdBy: uid,
    creatorUsername: "alice",
    isAnnounced: false,
    moderationStatus: "pending",
    featuredPlacement: "none",
    ...overrides,
  };
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-ttb-rules",
    firestore: { rules: fs.readFileSync(path.join(root, "firestore.rules"), "utf8") },
    storage: { rules: fs.readFileSync(path.join(root, "storage.rules"), "utf8") },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

describe("users: no self-granted admin", () => {
  test("a new user doc with isAdmin is refused", async () => {
    await assertFails(db("mallory").doc("users/mallory").set(defaultUserData({ isAdmin: true })));
  });

  test("delete and re-create with isAdmin is refused", async () => {
    await seed((admin) => admin.doc("users/mallory").set({ username: "mallory" }));
    const mallory = db("mallory");

    await assertSucceeds(mallory.doc("users/mallory").delete());
    await assertFails(mallory.doc("users/mallory").set(defaultUserData({ isAdmin: true })));
  });

  test("an update that sets isAdmin is refused", async () => {
    await seed((admin) => admin.doc("users/mallory").set({ username: "mallory" }));
    await assertFails(db("mallory").doc("users/mallory").update({ isAdmin: true }));
  });

  test("an anonymous sign-up with the default fields succeeds", async () => {
    const anonymous = { firebase: { sign_in_provider: "anonymous" } };
    await assertSucceeds(db("guest", anonymous).doc("users/guest").set(defaultUserData(), { merge: true }));
  });

  test("a Turkish placeholder succeeds", async () => {
    await assertSucceeds(db("alice").doc("users/alice").set(defaultUserData({
      username: "Kullanıcı",
      usernameNormalized: "kullanıcı",
      isAnonymous: false,
    }), { merge: true }));
  });

  test("BadgeModel's merge-create with only starting stats succeeds", async () => {
    await assertSucceeds(db("alice").doc("users/alice").set({
      dailyAnswers: 0,
      weeklyAnswers: 0,
      totalAnswered: 0,
      completedQuestionIds: [],
      categoryAnswers: {},
      currentStreak: 0,
      unlockedBadges: [],
      badgeProgress: {},
      updatedAt: serverTimestamp(),
    }, { merge: true }));
  });

  test("a re-created doc cannot forge stats", async () => {
    await assertFails(db("mallory").doc("users/mallory").set(defaultUserData({ totalAnswered: 5000 })));
    await assertFails(db("mallory").doc("users/mallory").set(defaultUserData({ unlockedBadges: ["legend"] })));
  });
});

describe("users: no impersonation by username", () => {
  beforeEach(async () => {
    await seed(async (admin) => {
      await admin.doc("usernames/berke").set({ uid: "berke", username: "Berke" });
      await admin.doc("usernames/alice").set({ uid: "alice", username: "Alice" });
      await admin.doc("users/alice").set({ username: "Guest User", usernameNormalized: "guest user" });
    });
  });

  test("a new user doc cannot take a registered name", async () => {
    await assertFails(db("mallory").doc("users/mallory").set(defaultUserData({
      username: "Berke",
      usernameNormalized: "berke",
    })));
  });

  test("a direct update to another user's registered name is refused", async () => {
    await assertFails(db("alice").doc("users/alice").update({ username: "Berke", usernameNormalized: "berke" }));
  });

  test("a name that does not match its normalized form is refused", async () => {
    await assertFails(db("alice").doc("users/alice").update({ username: "Berke", usernameNormalized: "alice" }));
  });

  test("the name the registry gave the caller succeeds", async () => {
    await assertSucceeds(db("alice").doc("users/alice").update({
      username: "Alice",
      usernameNormalized: "alice",
      updatedAt: serverTimestamp(),
    }));
  });
});

describe("users: older data and partial sign-ups keep working", () => {
  test("ensureExists may backfill usernameNormalized for a non-ASCII name", async () => {
    await seed((admin) => admin.doc("users/omer").set({ username: "Ömer" }));
    await assertSucceeds(db("omer").doc("users/omer").set({
      usernameNormalized: "ömer",
      isAnonymous: false,
      updatedAt: serverTimestamp(),
    }, { merge: true }));
  });

  test("onboarding may create the doc when the sign-up create failed", async () => {
    await assertSucceeds(db("alice").doc("users/alice").set({
      onboardingVersion: 2,
      onboardingCompletedAt: serverTimestamp(),
      termsAcceptedVersion: "2026-03",
      privacyAcceptedVersion: "2026-03",
      legalAcceptedAt: serverTimestamp(),
    }, { merge: true }));
  });

  test("a registered name may differ from the registry's display form only if the registry says so", async () => {
    await seed(async (admin) => {
      await admin.doc("usernames/ömer").set({ uid: "omer", username: "Ömer" });
      await admin.doc("users/omer").set({ username: "User", usernameNormalized: "user" });
    });
    await assertSucceeds(db("omer").doc("users/omer").update({ username: "Ömer", usernameNormalized: "ömer" }));
    await assertFails(db("omer").doc("users/omer").update({ username: "ÖMER", usernameNormalized: "ömer" }));
  });
});

describe("questions: creator attribution follows the registered name", () => {
  beforeEach(async () => {
    await seed(async (admin) => {
      await admin.doc("usernames/alice").set({ uid: "alice", username: "Alice" });
      await admin.doc("users/alice").set({ username: "alice", usernameNormalized: "alice" });
      await admin.doc("questions/q1").set(userQuestion("alice", { moderationStatus: "approved" }));
    });
  });

  test("a question with the user's own name succeeds", async () => {
    await assertSucceeds(db("alice").doc("questions/new").set(userQuestion("alice")));
  });

  test("a question with the trimmed stored name succeeds", async () => {
    await seed((admin) => admin.doc("users/alice").set({ username: "alice " }));
    await assertSucceeds(db("alice").doc("questions/new").set(userQuestion("alice")));
  });

  test("a question with another name is refused", async () => {
    await assertFails(db("alice").doc("questions/new").set(userQuestion("alice", { creatorUsername: "Berke" })));
  });

  test("an approved question cannot be renamed to any text", async () => {
    await assertFails(db("alice").doc("questions/q1").update({ creatorUsername: "something offensive" }));
  });

  test("ProfileModel's rename batch succeeds", async () => {
    const alice = db("alice");
    const batch = alice.batch();
    batch.update(alice.doc("users/alice"), { username: "Alice", updatedAt: serverTimestamp() });
    batch.update(alice.doc("questions/q1"), { creatorUsername: "Alice" });
    await assertSucceeds(batch.commit());
  });

  test("a text over 1000 characters is refused", async () => {
    await assertFails(db("alice").doc("questions/new").set(userQuestion("alice", { text: "x".repeat(1001) })));
  });

  test("a createdAt far in the future is refused", async () => {
    const future = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    await assertFails(db("alice").doc("questions/new").set(userQuestion("alice", { createdAt: future })));
  });
});

describe("user subcollections", () => {
  function device(overrides = {}) {
    return {
      fcmToken: "token",
      localeCode: "en",
      contentUpdatesEnabled: true,
      authorizationStatus: "authorized",
      isPushEligible: true,
      platform: "iOS",
      appVersion: "1.0",
      lastRegisteredAt: new Date(),
      ...overrides,
    };
  }

  test("a device doc with the model's fields succeeds", async () => {
    await assertSucceeds(db("alice").doc("users/alice/notificationDevices/d1").set(device(), { merge: true }));
  });

  test("a device doc with an extra field is refused", async () => {
    await assertFails(db("alice").doc("users/alice/notificationDevices/d1").set(device({ junk: "x".repeat(1000) })));
  });

  function aiQuery(overrides = {}) {
    return {
      question: "q",
      responses: ["a", "b", "c"],
      timestamp: new Date(),
      category: "fun",
      isSaved: false,
      isLoading: false,
      error: null,
      ...overrides,
    };
  }

  test("an AI query with a null error succeeds", async () => {
    await assertSucceeds(db("alice").doc("users/alice/aiQueries/a1").set(aiQuery()));
  });

  test("an AI query with an oversized response is refused", async () => {
    await assertFails(db("alice").doc("users/alice/aiQueries/a1").set(aiQuery({ responses: ["x".repeat(10001)] })));
  });
});

describe("storage", () => {
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

  function storage(uid) {
    return testEnv.authenticatedContext(uid, permanent).storage();
  }

  test("an own profile JPEG succeeds", async () => {
    await assertSucceeds(storage("alice").ref("profiles/alice/profile.jpg").put(jpeg, { contentType: "image/jpeg" }));
  });

  test("an SVG profile image is refused", async () => {
    await assertFails(storage("alice").ref("profiles/alice/profile.jpg").put(jpeg, { contentType: "image/svg+xml" }));
  });

  test("a second profile file name is refused", async () => {
    await assertFails(storage("alice").ref("profiles/alice/extra-1.jpg").put(jpeg, { contentType: "image/jpeg" }));
  });

  test("answer slots 0 to 2 succeed and slot 3 is refused", async () => {
    await assertSucceeds(storage("alice").ref("answers/alice/q1/slot_2.jpg").put(jpeg, { contentType: "image/jpeg" }));
    await assertFails(storage("alice").ref("answers/alice/q1/slot_3.jpg").put(jpeg, { contentType: "image/jpeg" }));
  });

  test("an upload to another user's folder is refused", async () => {
    await assertFails(storage("mallory").ref("profiles/alice/profile.jpg").put(jpeg, { contentType: "image/jpeg" }));
  });
});

test("the suite ran against the emulators", () => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "run through npm run test:rules");
});
