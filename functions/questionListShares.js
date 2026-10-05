const crypto = require("node:crypto");
const { HttpsError } = require("firebase-functions/v2/https");
const { requiredDocId } = require("./firestoreIds");
const { canonicalListShareUrl } = require("./shareRoutes");

const DEFAULT_RECIPIENT_CAP = 25;
const SHARE_CODE_BYTES = 16;

async function createQuestionListShare({
  db,
  user,
  data,
  createServerTimestamp,
  createShareCode = generateShareCode,
}) {
  const uid = permanentUID(user);
  const listId = requiredDocId(data?.listId, "listId");
  const includeOwnerAnswers = optionalBoolean(data?.includeOwnerAnswers, false);
  const listRef = db.collection("questionLists").doc(listId);
  const shareRef = db.collection("questionListShares").doc();
  const now = createServerTimestamp();

  const listSnapshot = await listRef.get();
  const list = assertOwnedQuestionList(listSnapshot, uid);
  const questionIds = normalizedQuestionIds(list.questionIds);

  const ownerDisplayName = await displayNameForUser(db, uid);
  const ownerAnswerSnapshots = includeOwnerAnswers
    ? await answerSnapshotsForUser(db, uid, questionIds)
    : {};
  const shareCode = createShareCode();

  await shareRef.set({
    ownerId: uid,
    ownerDisplayName,
    sourceListId: listId,
    listName: normalizedListName(list.name),
    questionIds,
    includeOwnerAnswers,
    ownerAnswerSnapshots,
    shareCode,
    shareCodePrefix: shareCode.slice(0, 6),
    recipientCap: DEFAULT_RECIPIENT_CAP,
    acceptedRecipientCount: 0,
    status: "active",
    isLinkEnabled: true,
    createdAt: now,
    updatedAt: now,
  });

  return shareResponse(shareRef.id, shareCode);
}

async function previewQuestionListShare({ db, user, data }) {
  const shareCode = requiredDocId(data?.shareCode, "shareCode");
  const shareSnapshot = await shareSnapshotForCode(db, shareCode);
  const share = shareSnapshot.data() || {};
  const ownerDisplayName = await refreshShareOwnerDisplayName(db, shareSnapshot);

  let isAccepted = false;
  if (user?.uid) {
    const recipientSnapshot = await shareSnapshot.ref.collection("recipients").doc(user.uid).get();
    // A revoked share withdraws access even when the recipient document has not caught up:
    // revokeShareRef updates the share before batching recipient statuses, so the two can
    // disagree if that batch fails.
    isAccepted = recipientSnapshot.exists
      && recipientSnapshot.data()?.status === "accepted"
      && share.status === "active";
  }

  // Disabling a link stops new claims; it does not withdraw access from recipients who
  // already accepted, so an existing recipient re-opening the link is still routed to
  // their shared list. Revocation is what withdraws access, and it flips accepted
  // recipient documents to "revoked", so this cannot let a revoked recipient back in.
  if (!isAccepted && !shareIsClaimable(share)) {
    throw new HttpsError("failed-precondition", "This share link is not accepting recipients.");
  }

  return {
    shareId: shareSnapshot.id,
    shareCode,
    listName: share.listName || "Question list",
    ownerDisplayName,
    questionCount: normalizedQuestionIds(share.questionIds).length,
    includeOwnerAnswers: share.includeOwnerAnswers === true,
    recipientCap: numericOrDefault(share.recipientCap, DEFAULT_RECIPIENT_CAP),
    acceptedRecipientCount: numericOrDefault(share.acceptedRecipientCount, 0),
    isAccepted,
  };
}

async function acceptQuestionListShare({
  db,
  user,
  data,
  createServerTimestamp,
}) {
  const uid = permanentUID(user);
  const shareCode = requiredDocId(data?.shareCode, "shareCode");
  const shareSnapshot = await shareSnapshotForCode(db, shareCode);
  const shareRef = shareSnapshot.ref;
  const share = shareSnapshot.data() || {};
  const recipientRef = shareRef.collection("recipients").doc(uid);
  const recipientDisplayName = await displayNameForUser(db, uid);
  const ownerDisplayName = typeof share.ownerId === "string"
    ? await displayNameForUser(db, share.ownerId)
    : share.ownerDisplayName || "TTB user";
  const now = createServerTimestamp();

  await db.runTransaction(async (transaction) => {
    const [currentShareSnapshot, recipientSnapshot, acceptedRecipientsSnapshot] = await Promise.all([
      transaction.get(shareRef),
      transaction.get(recipientRef),
      transaction.get(acceptedRecipientsQuery(shareRef)),
    ]);
    const share = currentShareSnapshot.data() || {};
    if (!currentShareSnapshot.exists) {
      throw new HttpsError("failed-precondition", "This share link is not accepting recipients.");
    }

    // Accepting again is a no-op, and stays one after the owner disables the link — this
    // recipient already has access. Revocation flips accepted recipient documents to
    // "revoked", so a revoked recipient falls through to the claimable check below.
    // The share must still be active as well: revokeShareRef updates the share before
    // batching recipient statuses, so a failed batch can leave the two disagreeing.
    const existing = recipientSnapshot.data() || {};
    if (recipientSnapshot.exists && existing.status === "accepted" && share.status === "active") {
      return;
    }

    if (!shareIsClaimable(share)) {
      throw new HttpsError("failed-precondition", "This share link is not accepting recipients.");
    }

    if (share.ownerId === uid) {
      throw new HttpsError("failed-precondition", "Owners cannot accept their own share link.");
    }

    // Recipient identities stay in the recipients subcollection, which recipients cannot
    // read. Deriving the count from that subcollection keeps the roster off the share
    // document, which every accepted recipient can read, and keeps the count from drifting
    // away from the documents it describes. Reaching here means this uid is not currently
    // accepted, so it is absent from acceptedRecipientsSnapshot.
    const acceptedRecipientCount = acceptedRecipientsSnapshot.size;
    if (acceptedRecipientCount >= numericOrDefault(share.recipientCap, DEFAULT_RECIPIENT_CAP)) {
      throw new HttpsError("resource-exhausted", "This share link has reached its recipient limit.");
    }

    transaction.set(recipientRef, {
      recipientId: uid,
      recipientDisplayName,
      status: "accepted",
      acceptedAt: existing.acceptedAt || now,
      latestReplyAnswerSnapshots: existing.latestReplyAnswerSnapshots || {},
      repliedAt: existing.repliedAt || null,
      unreadByOwner: existing.unreadByOwner === true,
      updatedAt: now,
    }, { merge: true });
    transaction.update(shareRef, {
      acceptedRecipientCount: acceptedRecipientCount + 1,
      ownerDisplayName,
      updatedAt: now,
    });
  });

  return { success: true, shareId: shareSnapshot.id };
}

async function disableQuestionListShare({
  db,
  user,
  data,
  createServerTimestamp,
}) {
  const uid = permanentUID(user);
  const shareId = requiredDocId(data?.shareId, "shareId");
  const shareRef = db.collection("questionListShares").doc(shareId);
  const now = createServerTimestamp();

  await db.runTransaction(async (transaction) => {
    const shareSnapshot = await transaction.get(shareRef);
    assertOwnedShare(shareSnapshot, uid);
    transaction.update(shareRef, {
      isLinkEnabled: false,
      updatedAt: now,
    });
  });

  return { success: true };
}

async function regenerateQuestionListShareLink({
  db,
  user,
  data,
  createServerTimestamp,
  createShareCode = generateShareCode,
}) {
  const uid = permanentUID(user);
  const shareId = requiredDocId(data?.shareId, "shareId");
  const shareRef = db.collection("questionListShares").doc(shareId);
  const shareCode = createShareCode();
  const now = createServerTimestamp();
  const ownerDisplayName = await displayNameForUser(db, uid);

  await db.runTransaction(async (transaction) => {
    const shareSnapshot = await transaction.get(shareRef);
    assertOwnedShare(shareSnapshot, uid);
    transaction.update(shareRef, {
      shareCode,
      shareCodePrefix: shareCode.slice(0, 6),
      ownerDisplayName,
      isLinkEnabled: true,
      updatedAt: now,
    });
  });

  return shareResponse(shareId, shareCode);
}

async function revokeQuestionListShare({
  db,
  user,
  data,
  createServerTimestamp,
}) {
  const uid = permanentUID(user);
  const shareId = requiredDocId(data?.shareId, "shareId");
  const shareRef = db.collection("questionListShares").doc(shareId);
  await revokeShareRef({
    db,
    shareRef,
    ownerId: uid,
    createServerTimestamp,
  });
  return { success: true };
}

async function leaveQuestionListShare({
  db,
  user,
  data,
  createServerTimestamp,
}) {
  const uid = permanentUID(user);
  const shareId = requiredDocId(data?.shareId, "shareId");
  const shareRef = db.collection("questionListShares").doc(shareId);
  const recipientRef = shareRef.collection("recipients").doc(uid);
  const now = createServerTimestamp();

  await db.runTransaction(async (transaction) => {
    const [shareSnapshot, recipientSnapshot, acceptedRecipientsSnapshot] = await Promise.all([
      transaction.get(shareRef),
      transaction.get(recipientRef),
      transaction.get(acceptedRecipientsQuery(shareRef)),
    ]);
    if (!shareSnapshot.exists || !recipientSnapshot.exists || recipientSnapshot.data()?.status !== "accepted") {
      throw new HttpsError("not-found", "Shared question list not found.");
    }

    const remainingRecipientCount = acceptedRecipientsSnapshot.docs
      .filter((snapshot) => snapshot.id !== uid)
      .length;

    transaction.update(recipientRef, {
      status: "left",
      leftAt: now,
      updatedAt: now,
    });
    transaction.update(shareRef, {
      acceptedRecipientCount: remainingRecipientCount,
      updatedAt: now,
    });
  });

  return { success: true };
}

async function sendQuestionListShareReply({
  db,
  user,
  data,
  createServerTimestamp,
}) {
  const uid = permanentUID(user);
  const shareId = requiredDocId(data?.shareId, "shareId");
  const shareRef = db.collection("questionListShares").doc(shareId);
  const recipientRef = shareRef.collection("recipients").doc(uid);
  const now = createServerTimestamp();

  const shareSnapshot = await shareRef.get();
  const share = shareSnapshot.data() || {};
  if (!shareSnapshot.exists || share.status !== "active") {
    throw new HttpsError("not-found", "Shared question list not found.");
  }

  const recipientSnapshot = await recipientRef.get();
  if (!recipientSnapshot.exists || recipientSnapshot.data()?.status !== "accepted") {
    throw new HttpsError("permission-denied", "Shared question list is not accepted.");
  }

  const questionIds = normalizedQuestionIds(share.questionIds);
  const latestReplyAnswerSnapshots = await answerSnapshotsForUser(db, uid, questionIds);
  const recipientDisplayName = await displayNameForUser(db, uid);
  await recipientRef.set({
    recipientDisplayName,
    latestReplyAnswerSnapshots,
    repliedAt: now,
    unreadByOwner: true,
    updatedAt: now,
  }, { merge: true });
  await shareRef.update({ updatedAt: now });

  return { success: true, repliedQuestionCount: Object.keys(latestReplyAnswerSnapshots).length };
}

async function markQuestionListShareReplySeen({
  db,
  user,
  data,
  createServerTimestamp,
}) {
  const uid = permanentUID(user);
  const shareId = requiredDocId(data?.shareId, "shareId");
  const recipientId = requiredDocId(data?.recipientId, "recipientId");
  const shareRef = db.collection("questionListShares").doc(shareId);
  const recipientRef = shareRef.collection("recipients").doc(recipientId);
  const now = createServerTimestamp();

  await db.runTransaction(async (transaction) => {
    const shareSnapshot = await transaction.get(shareRef);
    assertOwnedShare(shareSnapshot, uid);
    transaction.update(recipientRef, {
      unreadByOwner: false,
      seenByOwnerAt: now,
      updatedAt: now,
    });
  });

  return { success: true };
}

async function revokeSharesForSourceList({
  db,
  ownerId,
  sourceListId,
  createServerTimestamp,
}) {
  const snapshot = await db.collection("questionListShares")
    .where("ownerId", "==", ownerId)
    .where("sourceListId", "==", sourceListId)
    .where("status", "==", "active")
    .get();

  for (const shareSnapshot of snapshot.docs) {
    await revokeShareRef({
      db,
      shareRef: shareSnapshot.ref,
      ownerId,
      createServerTimestamp,
    });
  }

  return { revokedCount: snapshot.docs.length };
}

async function revokeShareRef({
  db,
  shareRef,
  ownerId,
  createServerTimestamp,
}) {
  const now = createServerTimestamp();
  const shareSnapshot = await shareRef.get();
  assertOwnedShare(shareSnapshot, ownerId);

  await shareRef.update({
    status: "revoked",
    isLinkEnabled: false,
    revokedAt: now,
    updatedAt: now,
  });

  const recipientsSnapshot = await shareRef.collection("recipients").get();
  const batch = db.batch();
  for (const recipientSnapshot of recipientsSnapshot.docs) {
    if (recipientSnapshot.data()?.status === "accepted") {
      batch.update(recipientSnapshot.ref, {
        status: "revoked",
        updatedAt: now,
      });
    }
  }
  await batch.commit();
}

function acceptedRecipientsQuery(shareRef) {
  return shareRef.collection("recipients").where("status", "==", "accepted");
}

async function shareSnapshotForCode(db, shareCode) {
  const snapshot = await db.collection("questionListShares")
    .where("shareCode", "==", shareCode)
    .limit(1)
    .get();
  const shareSnapshot = snapshot.docs[0];
  if (!shareSnapshot) {
    throw new HttpsError("not-found", "Share link not found.");
  }
  return shareSnapshot;
}

async function answerSnapshotsForUser(db, userId, questionIds) {
  const entries = await Promise.all(questionIds.map(async (questionId) => {
    const snapshot = await db.collection("questions").doc(questionId)
      .collection("userAnswers").doc(userId).get();
    if (!snapshot.exists) {
      return null;
    }

    const answers = normalizedAnswers(snapshot.data()?.answers);
    return answers.some((answer) => answer.length > 0)
      ? [questionId, answers]
      : null;
  }));

  return Object.fromEntries(entries.filter(Boolean));
}

async function displayNameForUser(db, userId) {
  const snapshot = await db.collection("users").doc(userId).get();
  const data = snapshot.data() || {};
  const username = typeof data.username === "string" ? data.username.trim() : "";
  if (username.length > 0) {
    return username.slice(0, 80);
  }
  return "TTB user";
}

async function refreshShareOwnerDisplayName(db, shareSnapshot) {
  const share = shareSnapshot.data() || {};
  if (typeof share.ownerId !== "string" || share.ownerId.trim().length === 0) {
    return share.ownerDisplayName || "TTB user";
  }

  const ownerDisplayName = await displayNameForUser(db, share.ownerId);
  if (ownerDisplayName !== share.ownerDisplayName) {
    await shareSnapshot.ref.update({ ownerDisplayName });
  }
  return ownerDisplayName;
}

function shareIsClaimable(share) {
  return share.status === "active" && share.isLinkEnabled === true;
}

function shareResponse(shareId, shareCode) {
  return {
    shareId,
    shareCode,
    shareURL: canonicalListShareUrl(shareCode),
  };
}

function permanentUID(user) {
  if (!user?.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  if (user.isAnonymous === true) {
    throw new HttpsError("permission-denied", "Question list sharing requires a permanent account.");
  }
  return user.uid;
}

function requiredString(value, field) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}

function optionalBoolean(value, fallback) {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", "Expected a boolean value.");
  }
  return value;
}

function normalizedListName(value) {
  const name = typeof value === "string" ? value.trim() : "";
  return name.length > 0 ? name.slice(0, 80) : "Question list";
}

function normalizedQuestionIds(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((questionId) => typeof questionId === "string")
    .map((questionId) => questionId.trim())
    .filter((questionId, index, all) => questionId.length > 0 && all.indexOf(questionId) === index)
    .slice(0, 500);
}

function normalizedAnswers(value) {
  const answers = Array.isArray(value) ? value : [];
  const normalized = answers.map((answer) => typeof answer === "string" ? answer.trim() : "");
  while (normalized.length < 3) {
    normalized.push("");
  }
  return normalized.slice(0, 3);
}

function assertOwnedQuestionList(snapshot, uid) {
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Question list not found.");
  }

  const list = snapshot.data() || {};
  if (list.ownerId !== uid) {
    throw new HttpsError("permission-denied", "Question list is not available.");
  }
  return list;
}

function assertOwnedShare(snapshot, uid) {
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Shared question list not found.");
  }

  const share = snapshot.data() || {};
  if (share.ownerId !== uid) {
    throw new HttpsError("permission-denied", "Shared question list is not available.");
  }
  return share;
}

function numericOrDefault(value, fallback) {
  return Number.isFinite(value) ? value : fallback;
}

function generateShareCode() {
  return crypto.randomBytes(SHARE_CODE_BYTES).toString("base64url");
}

module.exports = {
  DEFAULT_RECIPIENT_CAP,
  acceptQuestionListShare,
  createQuestionListShare,
  disableQuestionListShare,
  leaveQuestionListShare,
  markQuestionListShareReplySeen,
  previewQuestionListShare,
  regenerateQuestionListShareLink,
  revokeQuestionListShare,
  revokeSharesForSourceList,
  sendQuestionListShareReply,
};
