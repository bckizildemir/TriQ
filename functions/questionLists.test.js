const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createQuestionList,
  deleteQuestionList,
  setQuestionInList,
  updateQuestionList,
} = require("./questionLists");

test("permanent user can create rename add remove and delete a question list", async () => {
  const db = createFakeDb({
    "questions/q1": {
      source: "seeded",
    },
  });

  const created = await createQuestionList({
    db,
    user: { uid: "user-1", isAnonymous: false },
    data: { name: " Family " },
    createServerTimestamp: () => "now",
    createDocumentId: () => "list-1",
  });

  assert.deepEqual(created, { listId: "list-1" });
  assert.deepEqual(db.getDocument("questionLists/list-1"), {
    ownerId: "user-1",
    name: "Family",
    questionIds: [],
    visibility: "private",
    createdAt: "now",
    updatedAt: "now",
  });

  await updateQuestionList({
    db,
    user: { uid: "user-1", isAnonymous: false },
    data: { listId: "list-1", name: "Best questions" },
    createServerTimestamp: () => "later",
  });
  assert.equal(db.getDocument("questionLists/list-1").name, "Best questions");

  await setQuestionInList({
    db,
    user: { uid: "user-1", isAnonymous: false },
    data: { listId: "list-1", questionId: "q1", isIncluded: true },
    createServerTimestamp: () => "after-add",
  });
  assert.deepEqual(db.getDocument("questionLists/list-1").questionIds, ["q1"]);

  await setQuestionInList({
    db,
    user: { uid: "user-1", isAnonymous: false },
    data: { listId: "list-1", questionId: "q1", isIncluded: false },
    createServerTimestamp: () => "after-remove",
  });
  assert.deepEqual(db.getDocument("questionLists/list-1").questionIds, []);

  await deleteQuestionList({
    db,
    user: { uid: "user-1", isAnonymous: false },
    data: { listId: "list-1" },
  });
  assert.equal(db.getDocument("questionLists/list-1"), undefined);
});

test("question lists reject anonymous and unauthenticated users", async () => {
  const db = createFakeDb({});

  await assert.rejects(
    () => createQuestionList({
      db,
      user: { uid: "guest-1", isAnonymous: true },
      data: { name: "Guest" },
      createServerTimestamp: () => "now",
      createDocumentId: () => "list-1",
    }),
    (error) => error.code === "permission-denied"
  );

  await assert.rejects(
    () => createQuestionList({
      db,
      user: {},
      data: { name: "Missing" },
      createServerTimestamp: () => "now",
      createDocumentId: () => "list-1",
    }),
    (error) => error.code === "unauthenticated"
  );
});

test("question list mutations reject other owners", async () => {
  const db = createFakeDb({
    "questionLists/list-1": {
      ownerId: "user-2",
      name: "Private",
      questionIds: [],
      visibility: "private",
    },
  });

  await assert.rejects(
    () => updateQuestionList({
      db,
      user: { uid: "user-1", isAnonymous: false },
      data: { listId: "list-1", name: "Stolen" },
      createServerTimestamp: () => "now",
    }),
    (error) => error.code === "permission-denied"
  );
});

test("question lists reject empty names and unavailable questions", async () => {
  const db = createFakeDb({
    "questionLists/list-1": {
      ownerId: "user-1",
      name: "Private",
      questionIds: [],
      visibility: "private",
    },
    "questions/q1": {
      source: "userCreated",
      moderationStatus: "pending",
    },
  });

  await assert.rejects(
    () => createQuestionList({
      db,
      user: { uid: "user-1", isAnonymous: false },
      data: { name: "   " },
      createServerTimestamp: () => "now",
      createDocumentId: () => "list-2",
    }),
    (error) => error.code === "invalid-argument"
  );

  await assert.rejects(
    () => setQuestionInList({
      db,
      user: { uid: "user-1", isAnonymous: false },
      data: { listId: "list-1", questionId: "q1", isIncluded: true },
      createServerTimestamp: () => "now",
    }),
    (error) => error.code === "permission-denied"
  );
});

test("question lists reject adding more than 500 questions", async () => {
  const questionIds = Array.from({ length: 500 }, (_, index) => `q${index}`);
  const db = createFakeDb({
    "questionLists/list-1": {
      ownerId: "user-1",
      name: "Private",
      questionIds,
      visibility: "private",
    },
    "questions/q501": {
      source: "seeded",
    },
  });

  await assert.rejects(
    () => setQuestionInList({
      db,
      user: { uid: "user-1", isAnonymous: false },
      data: { listId: "list-1", questionId: "q501", isIncluded: true },
      createServerTimestamp: () => "now",
    }),
    (error) => error.code === "failed-precondition"
  );

  assert.deepEqual(db.getDocument("questionLists/list-1").questionIds, questionIds);
});

function createFakeDb(initialDocuments) {
  const documents = new Map(
    Object.entries(initialDocuments).map(([path, data]) => [path, structuredClone(data)])
  );
  let nextGeneratedId = 1;

  return {
    collection(path) {
      return createCollectionReference(path);
    },
    getDocument(path) {
      const document = documents.get(path);
      return document === undefined ? undefined : structuredClone(document);
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
        delete(ref) {
          operations.push({ type: "delete", ref });
        },
      };

      const result = await callback(transaction);

      for (const operation of operations) {
        if (operation.type === "delete") {
          documents.delete(operation.ref.path);
          continue;
        }

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
      doc(id = `generated-${nextGeneratedId++}`) {
        return createDocumentReference(`${path}/${id}`, id);
      },
    };
  }
}

function createDocumentReference(path, id) {
  return {
    id,
    path,
  };
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
