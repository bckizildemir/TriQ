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

const claimArgs = (db, uid, extra = {}) => ({
  db,
  user: { uid },
  username: "Berke",
  email: "new@example.com",
  isAnonymous: false,
  createServerTimestamp: () => SERVER_TIMESTAMP,
  ...extra,
});

test("claimUsername takes over a name held by an account whose user document is gone", async () => {
  const db = createFakeDb({
    users: {},
    usernames: { berke: { uid: "deleted", username: "Berke", email: "" } },
  });

  await claimUsername(claimArgs(db, "user-2"));

  assert.equal(db.getDocument("usernames", "berke").uid, "user-2");
  assert.equal(db.getDocument("users", "user-2").username, "Berke");
});

test("claimUsername takes over a name held by an anonymous account and resets that profile", async () => {
  const db = createFakeDb({
    users: { guest: { username: "Berke", usernameNormalized: "berke", isAnonymous: true } },
    usernames: { berke: { uid: "guest", username: "Berke", isAnonymous: true } },
  });

  await claimUsername(claimArgs(db, "user-2", { isReclaimableHolder: async (uid) => (uid === "guest" ? "anonymous" : null) }));

  assert.equal(db.getDocument("usernames", "berke").uid, "user-2");
  assert.equal(db.getDocument("users", "guest").username, "Guest User");
  assert.equal(db.getDocument("users", "guest").usernameNormalized, "guest user");
});

test("claimUsername keeps an anonymous holder's name while its claim is fresh", async () => {
  const db = createFakeDb({
    users: { guest: { username: "Berke", usernameNormalized: "berke", isAnonymous: true } },
    usernames: { berke: { uid: "guest", username: "Berke", updatedAt: new Date(Date.now() - 1000) } },
  });

  await assert.rejects(
    claimUsername(claimArgs(db, "user-2", { isReclaimableHolder: async () => "anonymous" })),
    /already taken/
  );
  assert.equal(db.getDocument("usernames", "berke").uid, "guest");
});

test("claimUsername takes a name from a deleted Auth user even when its claim is fresh", async () => {
  const db = createFakeDb({
    users: { gone: { username: "Berke", usernameNormalized: "berke", isAnonymous: false } },
    usernames: { berke: { uid: "gone", username: "Berke", updatedAt: new Date() } },
  });

  await claimUsername(claimArgs(db, "user-2", { isReclaimableHolder: async () => "gone" }));

  assert.equal(db.getDocument("usernames", "berke").uid, "user-2");
});

test("claimUsername keeps a name held by a permanent account", async () => {
  const db = createFakeDb({
    users: { owner: { username: "Berke", usernameNormalized: "berke", isAnonymous: true } },
    usernames: { berke: { uid: "owner", username: "Berke", isAnonymous: true } },
  });

  await assert.rejects(
    claimUsername(claimArgs(db, "user-2", { isReclaimableHolder: async () => false })),
    /already taken/
  );
  assert.equal(db.getDocument("usernames", "berke").uid, "owner");
  assert.equal(db.getDocument("users", "owner").username, "Berke");
});

test("claimUsername with the same name twice by one user is a no-op change", async () => {
  const db = createFakeDb({ users: {}, usernames: {} });

  await claimUsername(claimArgs(db, "user-1", { isAnonymous: true }));
  await claimUsername(claimArgs(db, "user-1", { isAnonymous: true }));
  await claimUsername(claimArgs(db, "user-1"));

  assert.equal(db.getDocument("usernames", "berke").uid, "user-1");
  assert.equal(db.getDocument("users", "user-1").isAnonymous, false);
});

test("releaseUsername without a restore name puts the placeholder on the profile that showed the name", async () => {
  const db = createFakeDb({
    users: { "user-1": { username: "Berke", usernameNormalized: "berke", isAnonymous: true } },
    usernames: { berke: { uid: "user-1", username: "Berke" } },
  });

  await releaseUsername({
    db,
    user: { uid: "user-1" },
    username: "Berke",
    createServerTimestamp: () => SERVER_TIMESTAMP,
  });

  assert.equal(db.getDocument("usernames", "berke"), undefined);
  assert.equal(db.getDocument("users", "user-1").username, "Guest User");
});

test("releaseUsername twice leaves the same result", async () => {
  const db = createFakeDb({
    users: { "user-1": { username: "Berke", usernameNormalized: "berke", isAnonymous: false } },
    usernames: { berke: { uid: "user-1", username: "Berke" } },
  });
  const args = { db, user: { uid: "user-1" }, username: "Berke", createServerTimestamp: () => SERVER_TIMESTAMP };

  await releaseUsername(args);
  await releaseUsername(args);

  assert.equal(db.getDocument("users", "user-1").username, "User");
});

test("releaseUsername does not touch a profile that shows another name", async () => {
  const db = createFakeDb({
    users: { "user-1": { username: "Other", usernameNormalized: "other" } },
    usernames: {},
  });

  await releaseUsername({
    db,
    user: { uid: "user-1" },
    username: "Berke",
    createServerTimestamp: () => SERVER_TIMESTAMP,
  });

  assert.equal(db.getDocument("users", "user-1").username, "Other");
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

test("claimUsername refuses the placeholder names every new account shows", async () => {
  const db = createFakeDb({ users: {}, usernames: {} });

  for (const username of ["User", " guest user ", "kullanıcı", "Misafir Kullanıcı"]) {
    await assert.rejects(
      claimUsername({
        db,
        user: { uid: "user-1" },
        username,
        email: "",
        isAnonymous: false,
        createServerTimestamp: () => SERVER_TIMESTAMP,
      }),
      /reserved/
    );
  }
});

test("releaseUsername does not restore a name another user owns", async () => {
  const db = createFakeDb({
    users: {
      mallory: { username: "Mallory2", usernameNormalized: "mallory2", email: "" },
    },
    usernames: {
      berke: { uid: "berke", username: "Berke", email: "berke@example.com" },
      mallory2: { uid: "mallory", username: "Mallory2", email: "" },
    },
  });

  await releaseUsername({
    db,
    user: { uid: "mallory" },
    username: "mallory2",
    restoreUsername: "Berke",
    createServerTimestamp: () => SERVER_TIMESTAMP,
  });

  // The released name leaves the profile too, so it never shows a name the registry does not hold.
  assert.equal(db.getDocument("users", "mallory").username, "Guest User");
  assert.equal(db.getDocument("usernames", "berke").uid, "berke");
});

test("releaseUsername restores a free previous name and registers it to the caller", async () => {
  const db = createFakeDb({
    users: {
      "user-1": { username: "NewName", usernameNormalized: "newname", email: "" },
    },
    usernames: {
      newname: { uid: "user-1", username: "NewName", email: "" },
    },
  });

  await releaseUsername({
    db,
    user: { uid: "user-1" },
    username: "newname",
    restoreUsername: "OldName",
    restoreEmail: "old@example.com",
    createServerTimestamp: () => SERVER_TIMESTAMP,
  });

  assert.equal(db.getDocument("usernames", "newname"), undefined);
  assert.equal(db.getDocument("usernames", "oldname").uid, "user-1");
  assert.equal(db.getDocument("usernames", "oldname").email, "old@example.com");
  assert.equal(db.getDocument("users", "user-1").username, "OldName");
});

test("claimUsername refuses names that can look like another user's name", async () => {
  const db = createFakeDb({ users: {}, usernames: {} });

  for (const username of [
    "аlice", // Cyrillic а
    "alice​", // zero-width space
    "ａlice", // fullwidth a
    "al‮ice", // right-to-left override
    "alice  smith", // two spaces
    "alice smith", // no-break space
    "ali<ce>",
  ]) {
    await assert.rejects(
      claimUsername({
        db,
        user: { uid: "user-1" },
        username,
        email: "",
        isAnonymous: false,
        createServerTimestamp: () => SERVER_TIMESTAMP,
      }),
      /Latin letters/,
      JSON.stringify(username)
    );
  }
});

test("claimUsername accepts English and Turkish names", async () => {
  for (const username of ["Alice", "Ömer Çağlar", "İlker_99", "şule.k", "ığdır-1"]) {
    const db = createFakeDb({ users: {}, usernames: {} });
    await claimUsername({
      db,
      user: { uid: "user-1" },
      username,
      email: "",
      isAnonymous: false,
      createServerTimestamp: () => SERVER_TIMESTAMP,
    });
    assert.equal(db.getDocument("users", "user-1").username, username);
  }
});

test("releaseUsername does not register a look-alike name", async () => {
  const db = createFakeDb({
    users: { mallory: { username: "Mallory2", usernameNormalized: "mallory2", email: "" } },
    usernames: { mallory2: { uid: "mallory", username: "Mallory2", email: "" } },
  });

  await releaseUsername({
    db,
    user: { uid: "mallory" },
    username: "mallory2",
    restoreUsername: "аlice",
    createServerTimestamp: () => SERVER_TIMESTAMP,
  });

  assert.equal(db.getDocument("usernames", "аlice"), undefined);
  assert.equal(db.getDocument("users", "mallory").username, "Guest User");
});
