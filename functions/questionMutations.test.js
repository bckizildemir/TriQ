const test = require("node:test");
const assert = require("node:assert/strict");

const {
  addQuestionFavorites,
  saveQuestionAnswers,
  toggleQuestionFavorite,
} = require("./questionMutations");

test("toggleQuestionFavorite updates only the authenticated user's membership", async () => {
  const db = createFakeDb({
    "questions/q1": {
      source: "seeded",
      favoriteUserIds: ["user-2"],
    },
  });

  const first = await toggleQuestionFavorite({
    db,
    user: { uid: "user-1" },
    data: { questionId: "q1" },
  });
  const second = await toggleQuestionFavorite({
    db,
    user: { uid: "user-1" },
    data: { questionId: "q1" },
  });

  assert.deepEqual(first, { isFavorite: true, favoriteCount: 2 });
  assert.deepEqual(second, { isFavorite: false, favoriteCount: 1 });
  assert.deepEqual(db.getDocument("questions/q1").favoriteUserIds, ["user-2"]);
});

test("toggleQuestionFavorite rejects unavailable community questions", async () => {
  const db = createFakeDb({
    "questions/q1": {
      source: "userCreated",
      moderationStatus: "pending",
    },
  });

  await assert.rejects(
    () => toggleQuestionFavorite({
      db,
      user: { uid: "user-1" },
      data: { questionId: "q1" },
    }),
    (error) => error.code === "permission-denied"
  );
});

test("addQuestionFavorites adds the caller to every available question", async () => {
  const db = createFakeDb({
    "questions/q1": { source: "seeded", favoriteUserIds: ["user-2"] },
    "questions/q2": { source: "seeded" },
    "questions/q3": { source: "userCreated", moderationStatus: "approved", favoriteUserIds: [] },
  });

  const result = await addQuestionFavorites({
    db,
    user: { uid: "user-1", isAnonymous: false },
    data: { questionIds: ["q1", "q2", "q3"] },
  });

  assert.deepEqual(result, {
    added: 3,
    alreadyFavorite: 0,
    unavailable: 0,
    unavailableQuestionIds: [],
  });
  assert.deepEqual(db.getDocument("questions/q1").favoriteUserIds, ["user-2", "user-1"]);
  assert.deepEqual(db.getDocument("questions/q2").favoriteUserIds, ["user-1"]);
  assert.deepEqual(db.getDocument("questions/q3").favoriteUserIds, ["user-1"]);
});

test("addQuestionFavorites is idempotent, so a retried migration adds nothing", async () => {
  const db = createFakeDb({
    "questions/q1": { source: "seeded", favoriteUserIds: [] },
  });

  await addQuestionFavorites({
    db,
    user: { uid: "user-1", isAnonymous: false },
    data: { questionIds: ["q1"] },
  });
  const second = await addQuestionFavorites({
    db,
    user: { uid: "user-1", isAnonymous: false },
    data: { questionIds: ["q1", "q1"] },
  });

  assert.deepEqual(second, {
    added: 0,
    alreadyFavorite: 1,
    unavailable: 0,
    unavailableQuestionIds: [],
  });
  assert.deepEqual(db.getDocument("questions/q1").favoriteUserIds, ["user-1"]);
});

test("addQuestionFavorites skips unavailable questions instead of stranding the rest", async () => {
  const db = createFakeDb({
    "questions/pending": { source: "userCreated", moderationStatus: "pending" },
    "questions/kept": { source: "seeded", favoriteUserIds: [] },
  });

  const result = await addQuestionFavorites({
    db,
    user: { uid: "user-1", isAnonymous: false },
    data: { questionIds: ["pending", "deleted", "kept"] },
  });

  assert.deepEqual(result, {
    added: 1,
    alreadyFavorite: 0,
    unavailable: 2,
    unavailableQuestionIds: ["pending", "deleted"],
  });
  assert.deepEqual(db.getDocument("questions/kept").favoriteUserIds, ["user-1"]);
  assert.equal(db.getDocument("questions/pending").favoriteUserIds, undefined);
});

test("addQuestionFavorites requires a permanent account", async () => {
  const db = createFakeDb({
    "questions/q1": { source: "seeded", favoriteUserIds: [] },
  });

  await assert.rejects(
    () => addQuestionFavorites({
      db,
      user: { uid: "guest", isAnonymous: true },
      data: { questionIds: ["q1"] },
    }),
    (error) => error.code === "permission-denied"
  );
  await assert.rejects(
    () => addQuestionFavorites({
      db,
      user: {},
      data: { questionIds: ["q1"] },
    }),
    (error) => error.code === "unauthenticated"
  );
  assert.deepEqual(db.getDocument("questions/q1").favoriteUserIds, []);
});

test("addQuestionFavorites validates the id list", async () => {
  const db = createFakeDb({});

  for (const questionIds of [undefined, "q1", [], ["", "   "], [42]]) {
    await assert.rejects(
      () => addQuestionFavorites({
        db,
        user: { uid: "user-1", isAnonymous: false },
        data: { questionIds },
      }),
      (error) => error.code === "invalid-argument"
    );
  }

  await assert.rejects(
    () => addQuestionFavorites({
      db,
      user: { uid: "user-1", isAnonymous: false },
      data: { questionIds: Array.from({ length: 51 }, (_, index) => `q${index}`) },
    }),
    (error) => error.code === "invalid-argument"
  );
});

test("saveQuestionAnswers writes per-user answers and aggregate stats", async () => {
  const db = createFakeDb({
    "questions/q1": {
      source: "seeded",
      category: "Daily",
      answerStats: {},
      totalRespondents: 0,
      todayRespondents: 0,
      todayDate: "",
    },
    "users/user-1": {
      totalAnswered: 0,
      dailyAnswers: 0,
      weeklyAnswers: 0,
      completedQuestionIds: [],
      categoryAnswers: {},
      currentStreak: 0,
      unlockedBadges: [],
      badgeProgress: {},
    },
    "badges/first": {
      targetCount: 1,
      type: "total",
    },
  });

  const result = await saveQuestionAnswers({
    db,
    user: { uid: "user-1", isAnonymous: false },
    data: {
      questionId: "q1",
      answers: [" One ", "Two", "Three"],
      imageURLs: ["", "", ""],
      imageAttributions: [{}, {}, {}],
    },
    createTimestampFromDate: (date) => date,
  });

  assert.deepEqual(result, { didWrite: true });
  assert.deepEqual(db.getDocument("questions/q1").answerStats, {
    0: { One: 1 },
    1: { Two: 1 },
    2: { Three: 1 },
  });
  assert.equal(db.getDocument("questions/q1").totalRespondents, 1);
  assert.equal(db.getDocument("questions/q1").todayRespondents, 1);
  assert.deepEqual(db.getDocument("questions/q1/userAnswers/user-1").answers, ["One", "Two", "Three"]);
  assert.deepEqual(db.getDocument("users/user-1").completedQuestionIds, ["q1"]);
  assert.deepEqual(db.getDocument("users/user-1").categoryAnswers, { Daily: 1 });
  assert.deepEqual(db.getDocument("users/user-1").unlockedBadges, ["first"]);
  assert.deepEqual(db.getDocument("users/user-1").badgeProgress, { first: 1 });
});

test("saveQuestionAnswers edits previous answers without double-counting completion", async () => {
  const yesterday = new Date(Date.now() - 86_400_000);
  const db = createFakeDb({
    "questions/q1": {
      source: "seeded",
      category: "Daily",
      answerStats: {
        0: { Old: 1 },
        1: { Two: 1 },
        2: { Three: 1 },
      },
      totalRespondents: 1,
      todayRespondents: 0,
      todayDate: "2000-01-01",
    },
    "questions/q1/userAnswers/user-1": {
      userId: "user-1",
      answers: ["Old", "Two", "Three"],
      answeredAt: yesterday,
    },
    "users/user-1": {
      totalAnswered: 1,
      completedQuestionIds: ["q1"],
      categoryAnswers: { Daily: 1 },
    },
  });

  await saveQuestionAnswers({
    db,
    user: { uid: "user-1", isAnonymous: false },
    data: {
      questionId: "q1",
      answers: ["New", "Two", "Three"],
    },
    createTimestampFromDate: (date) => date,
  });

  assert.deepEqual(db.getDocument("questions/q1").answerStats, {
    0: { New: 1 },
    1: { Two: 1 },
    2: { Three: 1 },
  });
  assert.equal(db.getDocument("questions/q1").totalRespondents, 1);
  assert.equal(db.getDocument("questions/q1").todayRespondents, 1);
  assert.equal(db.getDocument("users/user-1").totalAnswered, 1);
});

function createFakeDb(initialDocuments) {
  const documents = new Map(
    Object.entries(initialDocuments).map(([path, data]) => [path, structuredClone(data)])
  );

  return {
    collection(path) {
      return createCollectionReference(path);
    },
    getDocument(path) {
      return structuredClone(documents.get(path));
    },
    async runTransaction(callback) {
      const operations = [];
      const transaction = {
        async get(ref) {
          return createSnapshot(ref.id, ref.path, documents.get(ref.path));
        },
        update(ref, data) {
          operations.push({ type: "update", ref, data: structuredClone(data) });
        },
        set(ref, data, options = {}) {
          operations.push({
            type: "set",
            ref,
            data: structuredClone(data),
            merge: options.merge === true,
          });
        },
      };

      const result = await callback(transaction);

      for (const operation of operations) {
        const current = documents.get(operation.ref.path) || {};
        if (operation.type === "update" || operation.merge) {
          documents.set(operation.ref.path, { ...current, ...operation.data });
        } else {
          documents.set(operation.ref.path, operation.data);
        }
      }

      return result;
    },
  };

  function createCollectionReference(path) {
    return {
      doc(id) {
        return createDocumentReference(`${path}/${id}`, id);
      },
      async get() {
        const prefix = `${path}/`;
        const docs = [...documents.entries()]
          .filter(([documentPath]) => {
            const remainder = documentPath.slice(prefix.length);
            return documentPath.startsWith(prefix) && remainder.length > 0 && !remainder.includes("/");
          })
          .map(([documentPath, data]) => {
            const id = documentPath.split("/").at(-1);
            return createSnapshot(id, documentPath, data);
          });
        return { docs };
      },
    };
  }

  function createDocumentReference(path, id) {
    return {
      id,
      path,
      collection(name) {
        return createCollectionReference(`${path}/${name}`);
      },
    };
  }
}

function createSnapshot(id, path, data) {
  return {
    id,
    ref: { id, path },
    exists: data !== undefined,
    data() {
      return data === undefined ? undefined : structuredClone(data);
    },
  };
}

test("saveQuestionAnswers refuses ids, answers and image URLs that reach past the caller's own data", async () => {
  const request = (data) => saveQuestionAnswers({
    db: { collection: () => assert.fail("no Firestore access for invalid input") },
    user: { uid: "attacker", isAnonymous: false },
    data: {
      questionId: "q1",
      answers: ["One", "Two", "Three"],
      imageURLs: ["", "", ""],
      imageAttributions: [{}, {}, {}],
      ...data,
    },
    createTimestampFromDate: (date) => date,
  });

  await assert.rejects(request({ questionId: "q1/userAnswers/victim" }), /questionId is not a valid id/);
  await assert.rejects(request({ questionId: "__name__" }), /questionId is not a valid id/);
});

function answerLimitDb(previousAnswer) {
  return createFakeDb({
    "questions/q1": { source: "seeded", category: "Daily", answerStats: {}, totalRespondents: 0 },
    "users/user-1": { totalAnswered: 0, completedQuestionIds: [], categoryAnswers: {} },
    ...(previousAnswer ? { "questions/q1/userAnswers/user-1": previousAnswer } : {}),
  });
}

function saveAnswers(db, data) {
  return saveQuestionAnswers({
    db,
    user: { uid: "user-1", isAnonymous: true },
    data: { questionId: "q1", imageURLs: ["", "", ""], imageAttributions: [{}, {}, {}], ...data },
    createTimestampFromDate: (date) => date,
  });
}

test("saveQuestionAnswers shortens a new long answer instead of refusing it", async () => {
  const db = answerLimitDb();
  await saveAnswers(db, { answers: ["x".repeat(250), "Two", "Three"] });

  assert.equal(db.getDocument("questions/q1/userAnswers/user-1").answers[0], "x".repeat(200));
});

test("saveQuestionAnswers keeps an unchanged legacy answer and image URL", async () => {
  const legacyAnswer = "y".repeat(250);
  const legacyURL = "https://legacy.example/old.jpg";
  const db = answerLimitDb({ answers: [legacyAnswer, "Two", "Three"], imageURLs: [legacyURL, "", ""] });

  await saveAnswers(db, { answers: [legacyAnswer, "Two edited", "Three"], imageURLs: [legacyURL, "", ""] });

  const saved = db.getDocument("questions/q1/userAnswers/user-1");
  assert.equal(saved.answers[0], legacyAnswer);
  assert.equal(saved.answers[1], "Two edited");
  assert.equal(saved.imageURLs[0], legacyURL);
});

test("saveQuestionAnswers refuses a new image URL outside Firebase Storage", async () => {
  await assert.rejects(
    saveAnswers(answerLimitDb(), {
      answers: ["One", "Two", "Three"],
      imageURLs: ["https://attacker.example/pixel.gif", "", ""],
    }),
    /Firebase Storage download URLs/
  );
});

test("toggleQuestionFavorite refuses a path-walking id", async () => {
  await assert.rejects(
    toggleQuestionFavorite({
      db: { collection: () => assert.fail("no Firestore access for invalid input") },
      user: { uid: "attacker" },
      data: { questionId: "q1/userAnswers/victim" },
    }),
    /questionId is not a valid id/
  );
});
