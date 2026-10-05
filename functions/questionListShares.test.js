const test = require("node:test");
const assert = require("node:assert/strict");

const {
  acceptQuestionListShare,
  createQuestionListShare,
  disableQuestionListShare,
  leaveQuestionListShare,
  previewQuestionListShare,
  regenerateQuestionListShareLink,
  revokeQuestionListShare,
  revokeSharesForSourceList,
  sendQuestionListShareReply,
} = require("./questionListShares");

test("question list shares require permanent accounts for create and accept", async () => {
  const db = createFakeDb({
    "questionLists/list-1": {
      ownerId: "owner",
      name: "Private",
      questionIds: ["q1"],
    },
  });

  await assert.rejects(
    () => createQuestionListShare({
      db,
      user: { uid: "guest", isAnonymous: true },
      data: { listId: "list-1" },
      createServerTimestamp: () => "now",
    }),
    (error) => error.code === "permission-denied"
  );

  await assert.rejects(
    () => acceptQuestionListShare({
      db,
      user: { uid: "guest", isAnonymous: true },
      data: { shareCode: "code" },
      createServerTimestamp: () => "now",
    }),
    (error) => error.code === "permission-denied"
  );
});

test("preview returns only summary metadata while create snapshots text answers", async () => {
  const db = createFakeDb({
    "users/owner": { username: "Berke" },
    "questionLists/list-1": {
      ownerId: "owner",
      name: "Friends",
      questionIds: ["q1"],
    },
    "questions/q1/userAnswers/owner": {
      userId: "owner",
      answers: [" One ", "", "Three"],
    },
  });

  const created = await createQuestionListShare({
    db,
    user: { uid: "owner", isAnonymous: false },
    data: { listId: "list-1", includeOwnerAnswers: true },
    createServerTimestamp: () => "now",
    createShareCode: () => "share-code",
  });

  assert.equal(created.shareCode, "share-code");
  const share = db.getDocument(`questionListShares/${created.shareId}`);
  assert.deepEqual(share.ownerAnswerSnapshots, { q1: ["One", "", "Three"] });

  const preview = await previewQuestionListShare({
    db,
    user: {},
    data: { shareCode: "share-code" },
  });

  assert.deepEqual(preview, {
    shareId: created.shareId,
    shareCode: "share-code",
    listName: "Friends",
    ownerDisplayName: "Berke",
    questionCount: 1,
    includeOwnerAnswers: true,
    recipientCap: 25,
    acceptedRecipientCount: 0,
    isAccepted: false,
  });
  assert.equal(Object.hasOwn(preview, "ownerAnswerSnapshots"), false);
  assert.equal(Object.hasOwn(preview, "questionIds"), false);
});

test("preview refreshes stored owner display names", async () => {
  const db = createFakeDb({
    "users/owner": { username: "NewName" },
    "questionListShares/share-1": {
      ownerId: "owner",
      ownerDisplayName: "OldName",
      listName: "Friends",
      questionIds: ["q1"],
      shareCode: "code-1",
      recipientCap: 25,
      acceptedRecipientCount: 0,
      status: "active",
      isLinkEnabled: true,
    },
  });

  const preview = await previewQuestionListShare({
    db,
    user: {},
    data: { shareCode: "code-1" },
  });

  assert.equal(preview.ownerDisplayName, "NewName");
  assert.equal(db.getDocument("questionListShares/share-1").ownerDisplayName, "NewName");
});

test("create allows sharing an empty question list", async () => {
  const db = createFakeDb({
    "users/owner": { username: "Berke" },
    "questionLists/list-empty": {
      ownerId: "owner",
      name: "Empty plan",
      questionIds: [],
    },
  });

  const created = await createQuestionListShare({
    db,
    user: { uid: "owner", isAnonymous: false },
    data: { listId: "list-empty", includeOwnerAnswers: true },
    createServerTimestamp: () => "now",
    createShareCode: () => "empty code",
  });

  assert.equal(created.shareCode, "empty code");
  assert.equal(created.shareURL, "https://ttbp-9d652.web.app/share/lists/empty%20code");
  const share = db.getDocument(`questionListShares/${created.shareId}`);
  assert.deepEqual(share.questionIds, []);
  assert.deepEqual(share.ownerAnswerSnapshots, {});
});

test("accept is idempotent and enforces recipient cap", async () => {
  const db = createFakeDb({
    "users/recipient": { username: "Ada" },
    "users/blocked": { username: "Grace" },
    "questionListShares/share-1": {
      ownerId: "owner",
      listName: "Friends",
      questionIds: ["q1"],
      shareCode: "code-1",
      recipientCap: 1,
      acceptedRecipientCount: 0,
      status: "active",
      isLinkEnabled: true,
    },
  });

  await acceptQuestionListShare({
    db,
    user: { uid: "recipient", isAnonymous: false },
    data: { shareCode: "code-1" },
    createServerTimestamp: () => "accepted",
  });
  await acceptQuestionListShare({
    db,
    user: { uid: "recipient", isAnonymous: false },
    data: { shareCode: "code-1" },
    createServerTimestamp: () => "again",
  });

  assert.equal(db.getDocument("questionListShares/share-1").acceptedRecipientCount, 1);
  assert.deepEqual(db.getDocument("questionListShares/share-1/recipients/recipient"), {
    recipientId: "recipient",
    recipientDisplayName: "Ada",
    status: "accepted",
    acceptedAt: "accepted",
    latestReplyAnswerSnapshots: {},
    repliedAt: null,
    unreadByOwner: false,
    updatedAt: "accepted",
  });

  const acceptedPreview = await previewQuestionListShare({
    db,
    user: { uid: "recipient" },
    data: { shareCode: "code-1" },
  });
  assert.equal(acceptedPreview.isAccepted, true);

  await assert.rejects(
    () => acceptQuestionListShare({
      db,
      user: { uid: "blocked", isAnonymous: false },
      data: { shareCode: "code-1" },
      createServerTimestamp: () => "blocked",
    }),
    (error) => error.code === "resource-exhausted"
  );
});

test("share documents never carry recipient identities", async () => {
  const db = createFakeDb({
    "users/owner": { username: "Berke" },
    "users/first": { username: "Ada" },
    "users/second": { username: "Grace" },
    "questionLists/list-1": {
      ownerId: "owner",
      name: "Friends",
      questionIds: ["q1"],
    },
  });

  const created = await createQuestionListShare({
    db,
    user: { uid: "owner", isAnonymous: false },
    data: { listId: "list-1" },
    createServerTimestamp: () => "now",
    createShareCode: () => "code-1",
  });

  assert.equal(Object.hasOwn(db.getDocument(`questionListShares/${created.shareId}`), "recipientIds"), false);

  for (const uid of ["first", "second"]) {
    await acceptQuestionListShare({
      db,
      user: { uid, isAnonymous: false },
      data: { shareCode: "code-1" },
      createServerTimestamp: () => "accepted",
    });
  }

  // An accepted recipient can read the whole share document, so it must not name anyone.
  const share = db.getDocument(`questionListShares/${created.shareId}`);
  assert.equal(Object.hasOwn(share, "recipientIds"), false);
  assert.equal(JSON.stringify(share).includes("first"), false);
  assert.equal(JSON.stringify(share).includes("second"), false);
  assert.equal(share.acceptedRecipientCount, 2);

  // Identities live only in the recipients subcollection, which recipients cannot read.
  assert.equal(db.getDocument(`questionListShares/${created.shareId}/recipients/first`).recipientId, "first");
  assert.equal(db.getDocument(`questionListShares/${created.shareId}/recipients/second`).recipientId, "second");
});

test("recipient cap counts accepted recipient documents rather than a stored counter", async () => {
  const db = createFakeDb({
    "users/blocked": { username: "Grace" },
    "questionListShares/share-1": {
      ownerId: "owner",
      listName: "Friends",
      questionIds: ["q1"],
      shareCode: "code-1",
      recipientCap: 2,
      // Understates reality, as a share written before the count was derived would.
      acceptedRecipientCount: 0,
      status: "active",
      isLinkEnabled: true,
    },
    "questionListShares/share-1/recipients/first": { recipientId: "first", status: "accepted" },
    "questionListShares/share-1/recipients/second": { recipientId: "second", status: "accepted" },
  });

  await assert.rejects(
    () => acceptQuestionListShare({
      db,
      user: { uid: "blocked", isAnonymous: false },
      data: { shareCode: "code-1" },
      createServerTimestamp: () => "blocked",
    }),
    (error) => error.code === "resource-exhausted"
  );
});

test("recipients who left do not consume cap slots", async () => {
  const db = createFakeDb({
    "users/joining": { username: "Ada" },
    "questionListShares/share-1": {
      ownerId: "owner",
      listName: "Friends",
      questionIds: ["q1"],
      shareCode: "code-1",
      recipientCap: 2,
      acceptedRecipientCount: 2,
      status: "active",
      isLinkEnabled: true,
    },
    "questionListShares/share-1/recipients/staying": { recipientId: "staying", status: "accepted" },
    "questionListShares/share-1/recipients/departed": { recipientId: "departed", status: "left" },
  });

  await acceptQuestionListShare({
    db,
    user: { uid: "joining", isAnonymous: false },
    data: { shareCode: "code-1" },
    createServerTimestamp: () => "accepted",
  });

  assert.equal(db.getDocument("questionListShares/share-1").acceptedRecipientCount, 2);
});

test("leaving recomputes the accepted recipient count from recipient documents", async () => {
  const db = createFakeDb({
    "questionListShares/share-1": {
      ownerId: "owner",
      shareCode: "code-1",
      recipientCap: 25,
      // Stale counter: the recipient documents are the source of truth.
      acceptedRecipientCount: 7,
      status: "active",
      isLinkEnabled: true,
    },
    "questionListShares/share-1/recipients/leaving": { recipientId: "leaving", status: "accepted" },
    "questionListShares/share-1/recipients/staying": { recipientId: "staying", status: "accepted" },
  });

  await leaveQuestionListShare({
    db,
    user: { uid: "leaving", isAnonymous: false },
    data: { shareId: "share-1" },
    createServerTimestamp: () => "left",
  });

  const share = db.getDocument("questionListShares/share-1");
  assert.equal(share.acceptedRecipientCount, 1);
  assert.equal(Object.hasOwn(share, "recipientIds"), false);
  assert.equal(db.getDocument("questionListShares/share-1/recipients/leaving").status, "left");
  assert.equal(db.getDocument("questionListShares/share-1/recipients/staying").status, "accepted");
});

test("recipient send replaces the latest reply snapshot", async () => {
  const db = createFakeDb({
    "users/recipient": { username: "Ada" },
    "questionListShares/share-1": {
      ownerId: "owner",
      listName: "Friends",
      questionIds: ["q1"],
      shareCode: "code-1",
      status: "active",
      isLinkEnabled: true,
    },
    "questionListShares/share-1/recipients/recipient": {
      recipientId: "recipient",
      status: "accepted",
    },
    "questions/q1/userAnswers/recipient": {
      userId: "recipient",
      answers: ["Old", "", ""],
    },
  });

  await sendQuestionListShareReply({
    db,
    user: { uid: "recipient", isAnonymous: false },
    data: { shareId: "share-1" },
    createServerTimestamp: () => "first",
  });
  db.setDocument("questions/q1/userAnswers/recipient", {
    userId: "recipient",
    answers: ["New", "Two", ""],
  });
  await sendQuestionListShareReply({
    db,
    user: { uid: "recipient", isAnonymous: false },
    data: { shareId: "share-1" },
    createServerTimestamp: () => "second",
  });

  const recipient = db.getDocument("questionListShares/share-1/recipients/recipient");
  assert.deepEqual(recipient.latestReplyAnswerSnapshots, { q1: ["New", "Two", ""] });
  assert.equal(recipient.repliedAt, "second");
  assert.equal(recipient.unreadByOwner, true);
});

test("owner can revoke a share and accepted recipients lose reply access", async () => {
  const db = createFakeDb({
    "questionListShares/share-1": {
      ownerId: "owner",
      listName: "Friends",
      questionIds: ["q1"],
      shareCode: "code-1",
      status: "active",
      isLinkEnabled: true,
    },
    "questionListShares/share-1/recipients/recipient": {
      recipientId: "recipient",
      status: "accepted",
    },
  });

  await revokeQuestionListShare({
    db,
    user: { uid: "owner", isAnonymous: false },
    data: { shareId: "share-1" },
    createServerTimestamp: () => "revoked",
  });

  assert.equal(db.getDocument("questionListShares/share-1").status, "revoked");
  assert.equal(db.getDocument("questionListShares/share-1").isLinkEnabled, false);
  assert.equal(db.getDocument("questionListShares/share-1/recipients/recipient").status, "revoked");

  await assert.rejects(
    () => sendQuestionListShareReply({
      db,
      user: { uid: "recipient", isAnonymous: false },
      data: { shareId: "share-1" },
      createServerTimestamp: () => "after",
    }),
    (error) => error.code === "not-found"
  );
});

test("owner can disable and regenerate a share link", async () => {
  const db = createFakeDb({
    "questionListShares/share-1": {
      ownerId: "owner",
      listName: "Friends",
      questionIds: ["q1"],
      shareCode: "old-code",
      status: "active",
      isLinkEnabled: true,
    },
  });

  await disableQuestionListShare({
    db,
    user: { uid: "owner", isAnonymous: false },
    data: { shareId: "share-1" },
    createServerTimestamp: () => "disabled",
  });
  await assert.rejects(
    () => previewQuestionListShare({ db, user: {}, data: { shareCode: "old-code" } }),
    (error) => error.code === "failed-precondition"
  );

  const regenerated = await regenerateQuestionListShareLink({
    db,
    user: { uid: "owner", isAnonymous: false },
    data: { shareId: "share-1" },
    createServerTimestamp: () => "regenerated",
    createShareCode: () => "new code",
  });

  assert.equal(regenerated.shareCode, "new code");
  assert.equal(regenerated.shareURL, "https://ttbp-9d652.web.app/share/lists/new%20code");
  assert.equal(db.getDocument("questionListShares/share-1").ownerDisplayName, "TTB user");
  await assert.rejects(
    () => previewQuestionListShare({ db, user: {}, data: { shareCode: "old-code" } }),
    (error) => error.code === "not-found"
  );
  const preview = await previewQuestionListShare({ db, user: {}, data: { shareCode: "new code" } });
  assert.equal(preview.shareId, "share-1");
});

test("disabling a link keeps existing recipients able to re-enter", async () => {
  const db = createFakeDb({
    "questionListShares/share-1": {
      ownerId: "owner",
      listName: "Friends",
      questionIds: ["q1"],
      shareCode: "code",
      status: "active",
      isLinkEnabled: true,
      recipientCap: 25,
    },
    "questionListShares/share-1/recipients/recipient": {
      recipientId: "recipient",
      status: "accepted",
      acceptedAt: "accepted",
    },
  });

  await disableQuestionListShare({
    db,
    user: { uid: "owner", isAnonymous: false },
    data: { shareId: "share-1" },
    createServerTimestamp: () => "disabled",
  });

  const preview = await previewQuestionListShare({
    db,
    user: { uid: "recipient", isAnonymous: false },
    data: { shareCode: "code" },
  });
  assert.equal(preview.isAccepted, true);
  assert.equal(preview.shareId, "share-1");

  await acceptQuestionListShare({
    db,
    user: { uid: "recipient", isAnonymous: false },
    data: { shareCode: "code" },
    createServerTimestamp: () => "re-accepted",
  });
  assert.equal(
    db.getDocument("questionListShares/share-1/recipients/recipient").acceptedAt,
    "accepted"
  );

  // A disabled link still refuses new claims.
  await assert.rejects(
    () => previewQuestionListShare({
      db,
      user: { uid: "stranger", isAnonymous: false },
      data: { shareCode: "code" },
    }),
    (error) => error.code === "failed-precondition"
  );
  await assert.rejects(
    () => acceptQuestionListShare({
      db,
      user: { uid: "stranger", isAnonymous: false },
      data: { shareCode: "code" },
      createServerTimestamp: () => "now",
    }),
    (error) => error.code === "failed-precondition"
  );
});

test("revocation withdraws access even from accepted recipients", async () => {
  const db = createFakeDb({
    "questionListShares/share-1": {
      ownerId: "owner",
      listName: "Friends",
      questionIds: ["q1"],
      shareCode: "code",
      status: "active",
      isLinkEnabled: true,
    },
    "questionListShares/share-1/recipients/recipient": {
      recipientId: "recipient",
      status: "accepted",
    },
  });

  await revokeQuestionListShare({
    db,
    user: { uid: "owner", isAnonymous: false },
    data: { shareId: "share-1" },
    createServerTimestamp: () => "revoked",
  });

  await assert.rejects(
    () => previewQuestionListShare({
      db,
      user: { uid: "recipient", isAnonymous: false },
      data: { shareCode: "code" },
    }),
    (error) => error.code === "failed-precondition"
  );
  await assert.rejects(
    () => acceptQuestionListShare({
      db,
      user: { uid: "recipient", isAnonymous: false },
      data: { shareCode: "code" },
      createServerTimestamp: () => "now",
    }),
    (error) => error.code === "failed-precondition"
  );
});

test("a revoked share blocks re-entry even when a recipient document was left accepted", async () => {
  // revokeShareRef updates the share, then batches recipient statuses in a separate write.
  // A failed batch leaves exactly this state, and it must not read as valid re-entry.
  const db = createFakeDb({
    "questionListShares/share-1": {
      ownerId: "owner",
      listName: "Friends",
      questionIds: ["q1"],
      shareCode: "code",
      recipientCap: 25,
      acceptedRecipientCount: 1,
      status: "revoked",
      isLinkEnabled: false,
    },
    "questionListShares/share-1/recipients/recipient": {
      recipientId: "recipient",
      status: "accepted",
    },
  });

  await assert.rejects(
    () => previewQuestionListShare({
      db,
      user: { uid: "recipient", isAnonymous: false },
      data: { shareCode: "code" },
    }),
    (error) => error.code === "failed-precondition"
  );

  await assert.rejects(
    () => acceptQuestionListShare({
      db,
      user: { uid: "recipient", isAnonymous: false },
      data: { shareCode: "code" },
      createServerTimestamp: () => "now",
    }),
    (error) => error.code === "failed-precondition"
  );
});

test("source list deletion revokes active shares from that list", async () => {
  const db = createFakeDb({
    "questionListShares/share-1": {
      ownerId: "owner",
      sourceListId: "list-1",
      status: "active",
      isLinkEnabled: true,
      shareCode: "code-1",
    },
    "questionListShares/share-1/recipients/recipient": {
      recipientId: "recipient",
      status: "accepted",
    },
    "questionListShares/share-2": {
      ownerId: "owner",
      sourceListId: "list-2",
      status: "active",
      isLinkEnabled: true,
      shareCode: "code-2",
    },
  });

  const result = await revokeSharesForSourceList({
    db,
    ownerId: "owner",
    sourceListId: "list-1",
    createServerTimestamp: () => "revoked",
  });

  assert.deepEqual(result, { revokedCount: 1 });
  assert.equal(db.getDocument("questionListShares/share-1").status, "revoked");
  assert.equal(db.getDocument("questionListShares/share-1/recipients/recipient").status, "revoked");
  assert.equal(db.getDocument("questionListShares/share-2").status, "active");
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
    batch() {
      const operations = [];
      return {
        update(ref, data) {
          operations.push({ type: "update", ref, data: structuredClone(data) });
        },
        async commit() {
          applyOperations(operations);
        },
      };
    },
    getDocument(path) {
      const document = documents.get(path);
      return document === undefined ? undefined : structuredClone(document);
    },
    setDocument(path, data) {
      documents.set(path, structuredClone(data));
    },
    async runTransaction(callback) {
      const operations = [];
      const transaction = {
        async get(refOrQuery) {
          // Document references carry a path; queries do not. Buffered writes are applied
          // after the callback, so both read the pre-transaction state either way.
          if (typeof refOrQuery.path !== "string") {
            return refOrQuery.get();
          }
          return createSnapshot(refOrQuery.id, refOrQuery.path, documents.get(refOrQuery.path), refOrQuery);
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
      applyOperations(operations);
      return result;
    },
  };

  function createCollectionReference(path) {
    return createQuery(path, []);
  }

  function createQuery(path, filters, queryLimit) {
    return {
      doc(id = `generated-${nextGeneratedId++}`) {
        return createDocumentReference(`${path}/${id}`, id);
      },
      where(field, op, value) {
        return createQuery(path, [...filters, { field, op, value }], queryLimit);
      },
      limit(limitValue) {
        return createQuery(path, filters, limitValue);
      },
      async get() {
        let docs = directChildren(path)
          .filter((snapshot) => filters.every((filter) => matchesFilter(snapshot.data(), filter)));
        if (queryLimit !== undefined) {
          docs = docs.slice(0, queryLimit);
        }
        return { docs, size: docs.length };
      },
    };
  }

  function createDocumentReference(path, id) {
    return {
      id,
      path,
      async get() {
        return createSnapshot(id, path, documents.get(path), this);
      },
      async set(data, options = {}) {
        applyOperations([{ type: "set", ref: this, data: structuredClone(data), merge: options.merge === true }]);
      },
      async update(data) {
        applyOperations([{ type: "update", ref: this, data: structuredClone(data) }]);
      },
      collection(name) {
        return createCollectionReference(`${path}/${name}`);
      },
    };
  }

  function directChildren(collectionPath) {
    const prefix = `${collectionPath}/`;
    return [...documents.entries()]
      .filter(([documentPath]) => {
        const remainder = documentPath.slice(prefix.length);
        return documentPath.startsWith(prefix) && remainder.length > 0 && !remainder.includes("/");
      })
      .map(([documentPath, data]) => {
        const id = documentPath.split("/").at(-1);
        return createSnapshot(id, documentPath, data, createDocumentReference(documentPath, id));
      });
  }

  function matchesFilter(data, filter) {
    switch (filter.op) {
      case "==":
        return data?.[filter.field] === filter.value;
      default:
        throw new Error(`Unsupported fake filter operator: ${filter.op}`);
    }
  }

  function applyOperations(operations) {
    for (const operation of operations) {
      if (operation.type === "update") {
        const current = documents.get(operation.ref.path) || {};
        documents.set(operation.ref.path, { ...current, ...operation.data });
      } else if (operation.merge) {
        const current = documents.get(operation.ref.path) || {};
        documents.set(operation.ref.path, { ...current, ...operation.data });
      } else {
        documents.set(operation.ref.path, operation.data);
      }
    }
  }
}

function createSnapshot(id, path, data, ref) {
  return {
    id,
    ref,
    exists: data !== undefined,
    data() {
      return data === undefined ? undefined : structuredClone(data);
    },
  };
}
