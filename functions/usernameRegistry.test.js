const test = require("node:test");
const assert = require("node:assert/strict");

const {
  claimUsername,
  normalizeUsername,
  releaseUsername,
  resolveUsername,
} = require("./usernameRegistry");

const SERVER_TIMESTAMP = "SERVER_TIMESTAMP";

test("normalizeUsername trims and lowercases usernames", () => {
  assert.equal(normalizeUsername(" Berke "), "berke");
  assert.equal(normalizeUsername("BERKE"), "berke");
});

test("claimUsername creates a private registry entry and updates the user doc", async () => {
  const db = createFakeDb({
    users: {
      "user-1": { email: "", isAnonymous: true },
    },
    usernames: {},
  });

  const result = await claimUsername({
    db,
    user: { uid: "user-1" },
    username: " Berke ",
    email: "berke@example.com",
    isAnonymous: false,
    createServerTimestamp: () => SERVER_TIMESTAMP,
  });

  assert.deepEqual(result, {
    username: "Berke",
    usernameNormalized: "berke",
  });
  assert.deepEqual(db.getDocument("usernames", "berke"), {
    uid: "user-1",
    username: "Berke",
    usernameNormalized: "berke",
    email: "berke@example.com",
    isAnonymous: false,
    createdAt: SERVER_TIMESTAMP,
    updatedAt: SERVER_TIMESTAMP,
  });
  assert.equal(db.getDocument("users", "user-1").usernameNormalized, "berke");
});

test("claimUsername creates the user doc when it does not exist yet", async () => {
  const db = createFakeDb({
    users: {},
    usernames: {},
  });

  await claimUsername({
    db,
    user: { uid: "user-1" },
    username: "Berke",
    email: "berke@example.com",
    isAnonymous: false,
    createServerTimestamp: () => SERVER_TIMESTAMP,
  });

  assert.deepEqual(db.getDocument("usernames", "berke"), {
    uid: "user-1",
    username: "Berke",
    usernameNormalized: "berke",
    email: "berke@example.com",
    isAnonymous: false,
    createdAt: SERVER_TIMESTAMP,
    updatedAt: SERVER_TIMESTAMP,
  });
  assert.deepEqual(db.getDocument("users", "user-1"), {
    username: "Berke",
    usernameNormalized: "berke",
    email: "berke@example.com",
    isAnonymous: false,
    updatedAt: SERVER_TIMESTAMP,
  });
});

test("claimUsername rejects a case-insensitive duplicate owned by another user", async () => {
  const db = createFakeDb({
    users: {
      "user-1": {},
      "user-2": {},
    },
    usernames: {
      berke: { uid: "user-1", username: "Berke", email: "berke@example.com" },
    },
  });

  await assert.rejects(
    () => claimUsername({
      db,
      user: { uid: "user-2" },
      username: "BERKE",
      email: "other@example.com",
      isAnonymous: false,
      createServerTimestamp: () => SERVER_TIMESTAMP,
    }),
    (error) => error.code === "already-exists"
  );
});

test("claimUsername lets the same user rename and removes the old registry entry", async () => {
  const db = createFakeDb({
    users: {
      "user-1": { username: "Berke", usernameNormalized: "berke", email: "berke@example.com" },
    },
    usernames: {
      berke: { uid: "user-1", username: "Berke", email: "berke@example.com" },
    },
  });

  await claimUsername({
    db,
    user: { uid: "user-1" },
    username: "Cankizildemir",
    email: "berke@example.com",
    isAnonymous: false,
    createServerTimestamp: () => SERVER_TIMESTAMP,
  });

  assert.equal(db.getDocument("usernames", "berke"), undefined);
  assert.equal(db.getDocument("usernames", "cankizildemir").uid, "user-1");
  assert.equal(db.getDocument("users", "user-1").username, "Cankizildemir");
});

test("resolveUsername returns the stored email for username login", async () => {
  const db = createFakeDb({
    usernames: {
      berke: { uid: "user-1", username: "Berke", email: "berke@example.com" },
    },
  });

  const result = await resolveUsername({ db, username: " BERKE " });
  assert.deepEqual(result, { email: "berke@example.com" });
});

test("releaseUsername deletes only the current user's claimed username", async () => {
  const db = createFakeDb({
    users: {
      "user-1": { username: "Berke", usernameNormalized: "berke", email: "" },
    },
    usernames: {
      berke: { uid: "user-1", username: "Berke", email: "" },
      ceren: { uid: "user-2", username: "Ceren", email: "ceren@example.com" },
    },
  });

  await releaseUsername({
    db,
    user: { uid: "user-1" },
    username: "berke",
    restoreUsername: "Guest User",
    restoreEmail: "",
    restoreIsAnonymous: true,
    createServerTimestamp: () => SERVER_TIMESTAMP,
  });

  assert.equal(db.getDocument("usernames", "berke"), undefined);
  assert.equal(db.getDocument("usernames", "ceren").uid, "user-2");
  assert.equal(db.getDocument("users", "user-1").username, "Guest User");
  assert.equal(db.getDocument("users", "user-1").isAnonymous, true);
});

function createFakeDb(initialCollections) {
  const collections = new Map(
    Object.entries(initialCollections).map(([name, documents]) => [
      name,
      new Map(Object.entries(documents).map(([id, data]) => [id, structuredClone(data)])),
    ])
  );

  function ensureCollection(name) {
    if (!collections.has(name)) {
      collections.set(name, new Map());
    }

    return collections.get(name);
  }

  return {
    collection(name) {
      return {
        doc(id) {
          return {
            collectionName: name,
            id,
            get: async () => createSnapshot(id, ensureCollection(name).get(id)),
          };
        },
      };
    },
    async runTransaction(callback) {
      const operations = [];
      const transaction = {
        async get(ref) {
          return createSnapshot(ref.id, ensureCollection(ref.collectionName).get(ref.id));
        },
        set(ref, data, options = {}) {
          operations.push({ type: "set", ref, data: structuredClone(data), merge: options.merge === true });
        },
        delete(ref) {
          operations.push({ type: "delete", ref });
        },
      };

      await callback(transaction);

      for (const operation of operations) {
        const collection = ensureCollection(operation.ref.collectionName);
        if (operation.type === "delete") {
          collection.delete(operation.ref.id);
          continue;
        }

        const existing = collection.get(operation.ref.id) || {};
        collection.set(
          operation.ref.id,
          operation.merge ? { ...existing, ...operation.data } : operation.data
        );
      }
    },
    getDocument(collectionName, id) {
      const document = ensureCollection(collectionName).get(id);
      return document === undefined ? undefined : structuredClone(document);
    },
  };
}

function createSnapshot(id, data) {
  return {
    id,
    exists: data !== undefined,
    data() {
      return data === undefined ? undefined : structuredClone(data);
    },
  };
}
