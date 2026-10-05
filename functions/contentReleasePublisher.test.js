const test = require("node:test");
const assert = require("node:assert/strict");

const {
  publishPendingContentRelease,
} = require("./contentReleasePublisher");

const SERVER_TIMESTAMP = "SERVER_TIMESTAMP";

test("publishPendingContentRelease returns a no-op result when there is no pending content", async () => {
  const db = createFakeDb({
    categories: {
      announced: { isAnnounced: true, sortOrder: 0 },
    },
    questions: {
      announced: { isAnnounced: true, source: "seeded" },
    },
  });

  let notificationCount = 0;

  const result = await publishPendingContentRelease({
    db,
    createServerTimestamp: () => SERVER_TIMESTAMP,
    sendNotifications: async () => {
      notificationCount += 1;
    },
    localizedTitleOverrides: {},
    localizedBodyOverrides: {},
    createdBy: "admin-1",
  });

  assert.deepEqual(result, {
    success: true,
    didPublish: false,
    reason: "no-pending-content",
    categoryCount: 0,
    questionCount: 0,
  });
  assert.equal(notificationCount, 0);
  assert.equal(db.collectionSize("contentReleases"), 0);
});

test("publishPendingContentRelease publishes all pending categories and seeded questions", async () => {
  const db = createFakeDb({
    categories: {
      categoryB: {
        localizedNames: { en: "Sleep", tr: "Uyku" },
        sortOrder: 2,
        isAnnounced: false,
      },
      categoryA: {
        localizedNames: { en: "Mindset", tr: "Zihin" },
        sortOrder: 1,
        isAnnounced: false,
      },
      alreadyAnnounced: {
        localizedNames: { en: "Archive", tr: "Arsiv" },
        sortOrder: 3,
        isAnnounced: true,
      },
    },
    questions: {
      seededNewer: {
        text: "Newest pending seeded question",
        source: "seeded",
        isAnnounced: false,
        createdAt: new Date("2026-03-29T12:00:00Z"),
      },
      seededOlder: {
        text: "Older pending seeded question",
        source: "seeded",
        isAnnounced: false,
        createdAt: new Date("2026-03-28T12:00:00Z"),
      },
      userCreatedPending: {
        text: "Ignore me",
        source: "userCreated",
        isAnnounced: false,
        createdAt: new Date("2026-03-29T10:00:00Z"),
      },
      seededAnnounced: {
        text: "Already announced",
        source: "seeded",
        isAnnounced: true,
      },
    },
  });

  const sentNotifications = [];

  const result = await publishPendingContentRelease({
    db,
    createServerTimestamp: () => SERVER_TIMESTAMP,
    sendNotifications: async (payload) => {
      sentNotifications.push(payload);
    },
    localizedTitleOverrides: { tr: "Elle düzenlenmiş başlık" },
    localizedBodyOverrides: { en: "Custom English body" },
    createdBy: "admin-1",
  });

  assert.equal(result.success, true);
  assert.equal(result.didPublish, true);
  assert.equal(result.releaseId, "generated-1");
  assert.equal(result.categoryCount, 2);
  assert.equal(result.questionCount, 2);
  assert.equal(result.notificationStatus, "sent");

  assert.equal(sentNotifications.length, 1);
  assert.deepEqual(sentNotifications[0], {
    releaseId: "generated-1",
    localizedTitle: {
      en: "Fresh prompts just landed",
      tr: "Elle düzenlenmiş başlık",
    },
    localizedBody: {
      en: "Custom English body",
      tr: "Zihin, Uyku kategorilerinde 2 yeni soru seni bekliyor.",
    },
  });

  assert.equal(db.getDocument("categories", "categoryA").isAnnounced, true);
  assert.equal(db.getDocument("categories", "categoryA").announcedInReleaseId, "generated-1");
  assert.equal(db.getDocument("categories", "categoryA").announcedAt, SERVER_TIMESTAMP);
  assert.equal(db.getDocument("categories", "categoryB").isAnnounced, true);
  assert.equal(db.getDocument("questions", "seededNewer").isAnnounced, true);
  assert.equal(db.getDocument("questions", "seededOlder").announcedInReleaseId, "generated-1");
  assert.equal(db.getDocument("questions", "userCreatedPending").isAnnounced, false);

  assert.deepEqual(db.getDocument("contentReleases", "generated-1"), {
    localizedTitle: {
      en: "Fresh prompts just landed",
      tr: "Elle düzenlenmiş başlık",
    },
    localizedBody: {
      en: "Custom English body",
      tr: "Zihin, Uyku kategorilerinde 2 yeni soru seni bekliyor.",
    },
    categoryIds: ["categoryA", "categoryB"],
    questionIds: ["seededNewer", "seededOlder"],
    status: "published",
    createdAt: SERVER_TIMESTAMP,
    updatedAt: SERVER_TIMESTAMP,
    publishedAt: SERVER_TIMESTAMP,
    createdBy: "admin-1",
  });
});

test("publishPendingContentRelease does not republish content after it has been announced", async () => {
  const db = createFakeDb({
    categories: {
      categoryA: {
        localizedNames: { en: "Mindset", tr: "Zihin" },
        sortOrder: 1,
        isAnnounced: false,
      },
    },
    questions: {
      seededNewer: {
        text: "Newest pending seeded question",
        source: "seeded",
        isAnnounced: false,
        createdAt: new Date("2026-03-29T12:00:00Z"),
      },
    },
  });

  let notificationCount = 0;
  const payload = {
    db,
    createServerTimestamp: () => SERVER_TIMESTAMP,
    sendNotifications: async () => {
      notificationCount += 1;
    },
    localizedTitleOverrides: {},
    localizedBodyOverrides: {},
    createdBy: "admin-1",
  };

  const firstResult = await publishPendingContentRelease(payload);
  const secondResult = await publishPendingContentRelease(payload);

  assert.equal(firstResult.didPublish, true);
  assert.deepEqual(secondResult, {
    success: true,
    didPublish: false,
    reason: "no-pending-content",
    categoryCount: 0,
    questionCount: 0,
  });
  assert.equal(notificationCount, 1);
  assert.equal(db.collectionSize("contentReleases"), 1);
});

test("publishPendingContentRelease chunks release writes above Firestore batch limits", async () => {
  const pendingQuestions = Object.fromEntries(
    Array.from({ length: 560 }, (_, index) => [
      `seeded-${index}`,
      {
        text: `Pending seeded question ${index}`,
        source: "seeded",
        isAnnounced: false,
        createdAt: new Date(`2026-03-${String((index % 28) + 1).padStart(2, "0")}T12:00:00Z`),
      },
    ])
  );
  const db = createFakeDb({
    categories: {},
    questions: pendingQuestions,
  });

  const result = await publishPendingContentRelease({
    db,
    createServerTimestamp: () => SERVER_TIMESTAMP,
    sendNotifications: async () => {},
    localizedTitleOverrides: {},
    localizedBodyOverrides: {},
    createdBy: "admin-1",
  });

  assert.equal(result.success, true);
  assert.equal(result.didPublish, true);
  assert.equal(result.questionCount, 560);
  assert.deepEqual(db.batchCommitSizes(), [450, 111]);
  assert.equal(db.collectionSize("contentReleases"), 1);
  assert.equal(db.getDocument("questions", "seeded-0").isAnnounced, true);
  assert.equal(db.getDocument("questions", "seeded-559").announcedInReleaseId, "generated-1");
});

test("publishPendingContentRelease keeps release published when notifications fail", async () => {
  const db = createFakeDb({
    categories: {},
    questions: {
      seededQuestion: {
        text: "Pending seeded question",
        source: "seeded",
        isAnnounced: false,
        createdAt: new Date("2026-03-29T12:00:00Z"),
      },
    },
  });
  const warnings = [];

  const result = await publishPendingContentRelease({
    db,
    createServerTimestamp: () => SERVER_TIMESTAMP,
    sendNotifications: async () => {
      assert.equal(db.getDocument("questions", "seededQuestion").isAnnounced, true);
      throw new Error("FCM unavailable");
    },
    logger: {
      warn(message, details) {
        warnings.push({ message, details });
      },
    },
    localizedTitleOverrides: {},
    localizedBodyOverrides: {},
    createdBy: "admin-1",
  });

  assert.equal(result.success, true);
  assert.equal(result.didPublish, true);
  assert.equal(result.notificationStatus, "failed");
  assert.equal(db.collectionSize("contentReleases"), 1);
  assert.equal(db.getDocument("questions", "seededQuestion").announcedInReleaseId, "generated-1");
  assert.equal(warnings.length, 1);
});

function createFakeDb(initialCollections) {
  const collections = new Map(
    Object.entries(initialCollections).map(([name, documents]) => [
      name,
      new Map(
        Object.entries(documents).map(([id, data]) => [id, structuredClone(data)])
      ),
    ])
  );

  let generatedIDCounter = 1;
  const batchCommitSizes = [];

  function ensureCollection(name) {
    if (!collections.has(name)) {
      collections.set(name, new Map());
    }

    return collections.get(name);
  }

  function filteredDocuments(name, filters) {
    return [...ensureCollection(name).entries()]
      .filter(([, document]) =>
        filters.every(({ field, operator, value }) => matchesFilter(document[field], operator, value))
      )
      .map(([id, document]) => createDocumentSnapshot(id, document, name));
  }

  return {
    collection(name) {
      return createCollectionReference(name);
    },
    batch() {
      const operations = [];

      return {
        set(documentRef, data, options = {}) {
          operations.push({
            collectionName: documentRef.collectionName,
            id: documentRef.id,
            data: structuredClone(data),
            merge: options.merge === true,
          });
        },
        async commit() {
          assert.ok(operations.length <= 500, `Batch contains ${operations.length} writes`);
          batchCommitSizes.push(operations.length);

          for (const operation of operations) {
            const collection = ensureCollection(operation.collectionName);
            const existing = collection.get(operation.id) || {};
            const nextValue = operation.merge
              ? { ...existing, ...operation.data }
              : operation.data;

            collection.set(operation.id, structuredClone(nextValue));
          }
        },
      };
    },
    getDocument(name, id) {
      return structuredClone(ensureCollection(name).get(id));
    },
    collectionSize(name) {
      return ensureCollection(name).size;
    },
    batchCommitSizes() {
      return [...batchCommitSizes];
    },
  };

  function createCollectionReference(name) {
    return {
      where(field, operator, value) {
        return createQuery(name, [{ field, operator, value }]);
      },
      doc(id = `generated-${generatedIDCounter++}`) {
        return {
          id,
          collectionName: name,
          get: async () => {
            const document = ensureCollection(name).get(id);
            return createDocumentSnapshot(id, document, name);
          },
        };
      },
      async get() {
        return {
          docs: filteredDocuments(name, []),
          empty: ensureCollection(name).size === 0,
        };
      },
    };
  }

  function createQuery(name, filters) {
    return {
      where(field, operator, value) {
        return createQuery(name, [...filters, { field, operator, value }]);
      },
      async get() {
        const docs = filteredDocuments(name, filters);
        return {
          docs,
          empty: docs.length === 0,
        };
      },
    };
  }
}

function createDocumentSnapshot(id, data, collectionName = "") {
  return {
    id,
    exists: data !== undefined,
    data() {
      return data === undefined ? undefined : structuredClone(data);
    },
    ref: {
      id,
      collectionName,
    },
  };
}

function matchesFilter(fieldValue, operator, expectedValue) {
  switch (operator) {
  case "==":
    return fieldValue === expectedValue;
  case "<=":
    return toMillis(fieldValue) <= toMillis(expectedValue);
  default:
    assert.fail(`Unsupported operator: ${operator}`);
  }
}

function toMillis(value) {
  if (value instanceof Date) {
    return value.getTime();
  }

  return value;
}
