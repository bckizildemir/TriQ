const { HttpsError } = require("firebase-functions/v2/https");
const { FieldPath, FieldValue, Timestamp } = require("firebase-admin/firestore");

// Firestore allows 500 writes in one batch. Stay under it.
const BATCH_WRITE_LIMIT = 400;
// The recipient statuses questionListShares.js writes. The query uses the existing
// (recipientId, status, updatedAt) collection-group index, so no new index is needed.
const RECIPIENT_STATUSES = ["accepted", "left", "revoked"];

/**
 * Deletes the caller's account (TriQ#88): all data the caller owns, then the Firebase Auth user
 * as the very last step. The client calls this after reauthentication and only signs out locally
 * after it succeeds.
 *
 * Safe to run again: every step finds its work with a query or ignores a missing document or
 * file, and an Auth user that is already gone counts as deleted, so a retry after a partial
 * failure finishes the job. `users/<uid>` goes last of the Firestore data, so a failed run still
 * leaves the profile for the retry to read.
 *
 * Other users' data is touched only where the owner allowed it: their answers, answer images and
 * favorites on the caller's own community questions go with those questions; the caller's
 * question ids leave their lists and shares (with the answers copied into those shares); and the
 * caller's recipient entries on their shares go, with the share's accepted count decremented.
 */
async function deleteOwnAccountData({ db, bucket, auth, uid }) {
  if (typeof uid !== "string" || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }

  const userRef = db.collection("users").doc(uid);
  const userSnapshot = await userRef.get();
  const profileImageURL = stringOrNull(userSnapshot.data()?.profileImageURL);

  const counts = {
    answers: await purgeOwnAnswersForAccountDeletion({ db, bucket, userId: uid }),
    favorites: await removeFavorites(db, uid),
    questions: 0,
    questionLists: 0,
    questionListShares: 0,
    shareRecipients: 0,
    usernames: 0,
  };

  await deleteFilesWithPrefix(bucket, `answers/${uid}/`);

  counts.questionLists = await deleteQueryResults(
    db,
    db.collection("questionLists").where("ownerId", "==", uid)
  );
  counts.questions = await deleteOwnQuestions({ db, bucket, uid });
  counts.questionListShares = await deleteOwnShares(db, uid);
  counts.shareRecipients = await deleteOwnRecipientEntries(db, uid);
  counts.usernames = await deleteQueryResults(
    db,
    db.collection("usernames").where("uid", "==", uid)
  );

  await db.recursiveDelete(db.collection("aiUsageDaily").doc(uid));
  await deleteFilesWithPrefix(bucket, `profiles/${uid}/`);

  for (const name of ["aiQueries", "aiUsage", "notificationDevices"]) {
    await db.recursiveDelete(userRef.collection(name));
  }
  // Last: removes any other subcollection, then the user document itself.
  await db.recursiveDelete(userRef);

  // The very last step: a failure anywhere above leaves the account, so the user can retry.
  const authUserDeleted = await deleteAuthUser(auth, uid);

  return { success: true, profileImageURL, authUserDeleted, counts };
}

// MARK: - Auth

async function deleteAuthUser(auth, uid) {
  try {
    await auth.deleteUser(uid);
    return true;
  } catch (error) {
    // A retry after a run that got this far: the account is already gone.
    if (error?.code === "auth/user-not-found") {
      return false;
    }
    throw error;
  }
}

// MARK: - Favorites

async function removeFavorites(db, uid) {
  const snapshot = await db.collection("questions")
    .where("favoriteUserIds", "array-contains", uid)
    .get();

  await commitInBatches(db, snapshot.docs, (batch, document) => {
    batch.update(document.ref, { favoriteUserIds: FieldValue.arrayRemove(uid) });
  });
  return snapshot.size;
}

// MARK: - Community questions

async function deleteOwnQuestions({ db, bucket, uid }) {
  // Community questions only. An admin's official questions are `source: "seeded"` with the
  // admin's uid in createdBy (AdminQuestionView); they belong to the app and stay.
  const snapshot = await db.collection("questions")
    .where("createdBy", "==", uid)
    .where("source", "==", "userCreated")
    .get();

  for (const questionSnapshot of snapshot.docs) {
    const questionRef = questionSnapshot.ref;
    // Lists and shares first: once the question is gone these queries cannot find it again on
    // a retry.
    await removeQuestionFromLists(db, questionRef.id);
    await removeQuestionFromShares(db, questionRef.id);
    const answers = await questionRef.collection("userAnswers").get();
    for (const answer of answers.docs) {
      await deleteFilesWithPrefix(bucket, `answers/${answer.id}/${questionRef.id}/`);
    }

    // Deleting a document does not delete its subcollections; recursiveDelete does.
    await db.recursiveDelete(questionRef);
  }

  return snapshot.size;
}

async function removeQuestionFromLists(db, questionId) {
  const snapshot = await db.collection("questionLists")
    .where("questionIds", "array-contains", questionId)
    .get();

  await commitInBatches(db, snapshot.docs, (batch, document) => {
    batch.update(document.ref, {
      questionIds: FieldValue.arrayRemove(questionId),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

// A share copies the list's question ids (questionIds), the owner's answers per question
// (ownerAnswerSnapshots), and each recipient's reply per question (recipients/*
// latestReplyAnswerSnapshots), all in questionListShares.js. Drop the deleted question from each.
async function removeQuestionFromShares(db, questionId) {
  const snapshot = await db.collection("questionListShares")
    .where("questionIds", "array-contains", questionId)
    .get();

  for (const shareSnapshot of snapshot.docs) {
    // Recipients before the share: a retry finds the share again only while it still lists the
    // question.
    const recipients = await shareSnapshot.ref.collection("recipients").get();
    const repliedRecipients = recipients.docs.filter((recipient) =>
      Object.hasOwn(recipient.data()?.latestReplyAnswerSnapshots || {}, questionId)
    );
    await commitInBatches(db, repliedRecipients, (batch, recipient) => {
      batch.update(
        recipient.ref,
        new FieldPath("latestReplyAnswerSnapshots", questionId),
        FieldValue.delete()
      );
    });

    await shareSnapshot.ref.update(
      "questionIds", FieldValue.arrayRemove(questionId),
      new FieldPath("ownerAnswerSnapshots", questionId), FieldValue.delete(),
      "updatedAt", FieldValue.serverTimestamp()
    );
  }
}

// MARK: - Shares

async function deleteOwnShares(db, uid) {
  const snapshot = await db.collection("questionListShares").where("ownerId", "==", uid).get();
  for (const shareSnapshot of snapshot.docs) {
    // Removes the recipients subcollection too. The public link is the shareCode on this doc.
    await db.recursiveDelete(shareSnapshot.ref);
  }
  return snapshot.size;
}

async function deleteOwnRecipientEntries(db, uid) {
  const snapshot = await db.collectionGroup("recipients")
    .where("recipientId", "==", uid)
    .where("status", "in", RECIPIENT_STATUSES)
    .orderBy("updatedAt", "desc")
    .get();

  let deleted = 0;
  for (const recipientSnapshot of snapshot.docs) {
    const shareRef = recipientSnapshot.ref.parent.parent;
    if (!shareRef || recipientSnapshot.id !== uid) {
      continue;
    }

    const didDelete = await deleteRecipientEntry(db, shareRef, recipientSnapshot.ref);
    if (didDelete) {
      deleted += 1;
    }
  }
  return deleted;
}

async function deleteRecipientEntry(db, shareRef, recipientRef) {
  return db.runTransaction(async (transaction) => {
    const [shareSnapshot, recipientSnapshot] = await Promise.all([
      transaction.get(shareRef),
      transaction.get(recipientRef),
    ]);
    if (!recipientSnapshot.exists) {
      return false;
    }

    if (shareSnapshot.exists && recipientSnapshot.data()?.status === "accepted") {
      const count = numberOrZero(shareSnapshot.data()?.acceptedRecipientCount);
      transaction.update(shareRef, {
        acceptedRecipientCount: Math.max(0, count - 1),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.delete(recipientRef);
    return true;
  });
}

// MARK: - Answers

/**
 * Deletes the caller's answers and fixes each question's public counters. Moved from index.js,
 * where the older `purgeOwnAnswersForAccountDeletion` callable still uses it for app builds that
 * predate `deleteOwnAccountData`.
 */
async function purgeOwnAnswersForAccountDeletion({ db, bucket, userId }) {
  const snapshot = await db.collectionGroup("userAnswers")
    .where("userId", "==", userId)
    .get();

  let deletedAnswerCount = 0;

  for (const document of snapshot.docs) {
    const questionRef = document.ref.parent.parent;
    if (!questionRef) {
      continue;
    }

    await deleteAnswerImagesIfPresent(bucket, userId, questionRef.id);

    const didDelete = await deleteAnswerForAccountDeletion(db, questionRef, userId);
    if (didDelete) {
      deletedAnswerCount += 1;
    }
  }

  return deletedAnswerCount;
}

async function deleteAnswerImagesIfPresent(bucket, userId, questionId) {
  for (let slotIndex = 0; slotIndex < 3; slotIndex += 1) {
    const file = bucket.file(`answers/${userId}/${questionId}/slot_${slotIndex}.jpg`);
    await file.delete({ ignoreNotFound: true });
  }
}

async function deleteAnswerForAccountDeletion(db, questionRef, userId) {
  const userAnswerRef = questionRef.collection("userAnswers").doc(userId);
  const replacementLastAnsweredAt = await latestRemainingAnsweredAt(questionRef, userId);

  return db.runTransaction(async (transaction) => {
    const [questionSnapshot, userAnswerSnapshot] = await Promise.all([
      transaction.get(questionRef),
      transaction.get(userAnswerRef),
    ]);

    if (!userAnswerSnapshot.exists) {
      return false;
    }

    if (!questionSnapshot.exists) {
      transaction.delete(userAnswerRef);
      return true;
    }

    const questionData = questionSnapshot.data() || {};
    const userAnswerData = userAnswerSnapshot.data() || {};
    const answers = Array.isArray(userAnswerData.answers) ? userAnswerData.answers : [];
    const answeredAt = userAnswerData.answeredAt?.toDate?.() || new Date();

    const updatedState = applyQuestionAnswerDeletion(
      {
        answerStats: answerStatsFromFirestore(questionData.answerStats),
        totalRespondents: numberOrZero(questionData.totalRespondents),
        todayRespondents: numberOrZero(questionData.todayRespondents),
        todayDate: typeof questionData.todayDate === "string" ? questionData.todayDate : "",
        lastAnsweredAt: questionData.lastAnsweredAt?.toDate?.() || null,
      },
      answers,
      answeredAt,
      replacementLastAnsweredAt
    );

    transaction.update(questionRef, {
      answerStats: answerStatsForFirestore(updatedState.answerStats),
      totalRespondents: updatedState.totalRespondents,
      todayRespondents: updatedState.todayRespondents,
      todayDate: updatedState.todayDate,
      lastAnsweredAt: updatedState.lastAnsweredAt
        ? Timestamp.fromDate(updatedState.lastAnsweredAt)
        : FieldValue.delete(),
    });
    transaction.delete(userAnswerRef);
    return true;
  });
}

async function latestRemainingAnsweredAt(questionRef, excludingUserId) {
  const snapshot = await questionRef.collection("userAnswers")
    .orderBy("answeredAt", "desc")
    .limit(2)
    .get();

  for (const document of snapshot.docs) {
    if (document.id === excludingUserId) {
      continue;
    }

    const answeredAt = document.data()?.answeredAt?.toDate?.();
    if (answeredAt) {
      return answeredAt;
    }
  }

  return null;
}

function applyQuestionAnswerDeletion(state, answers, answeredAt, replacementLastAnsweredAt) {
  const updatedState = {
    answerStats: cloneAnswerStats(state.answerStats),
    totalRespondents: Math.max(0, numberOrZero(state.totalRespondents) - 1),
    todayRespondents: numberOrZero(state.todayRespondents),
    todayDate: typeof state.todayDate === "string" ? state.todayDate : "",
    lastAnsweredAt: replacementLastAnsweredAt,
  };

  answers.forEach((answer, index) => {
    if (typeof answer !== "string" || answer.length === 0) {
      return;
    }

    const slotKey = `${index}`;
    const slotStats = updatedState.answerStats[slotKey];
    if (!slotStats) {
      return;
    }

    const updatedCount = Math.max(0, numberOrZero(slotStats[answer]) - 1);
    if (updatedCount === 0) {
      delete slotStats[answer];
    } else {
      slotStats[answer] = updatedCount;
    }

    if (Object.keys(slotStats).length === 0) {
      delete updatedState.answerStats[slotKey];
    }
  });

  if (updatedState.todayDate === dateStringFor(answeredAt)) {
    updatedState.todayRespondents = Math.max(0, numberOrZero(state.todayRespondents) - 1);
    if (updatedState.todayRespondents === 0) {
      updatedState.todayDate = "";
    }
  }

  return updatedState;
}

function dateStringFor(date) {
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function answerStatsFromFirestore(value) {
  if (!value || typeof value !== "object") {
    return {};
  }

  const parsed = {};
  for (const [slotKey, slotValue] of Object.entries(value)) {
    if (!slotValue || typeof slotValue !== "object" || Array.isArray(slotValue)) {
      continue;
    }

    const typedSlot = {};
    for (const [answer, count] of Object.entries(slotValue)) {
      typedSlot[answer] = numberOrZero(count);
    }
    parsed[slotKey] = typedSlot;
  }
  return parsed;
}

function answerStatsForFirestore(answerStats) {
  const payload = {};
  for (const [slotKey, slotStats] of Object.entries(answerStats)) {
    payload[slotKey] = { ...slotStats };
  }
  return payload;
}

function cloneAnswerStats(answerStats) {
  const clone = {};
  for (const [slotKey, slotStats] of Object.entries(answerStats)) {
    clone[slotKey] = { ...slotStats };
  }
  return clone;
}

// MARK: - Helpers

async function deleteQueryResults(db, query) {
  const snapshot = await query.get();
  await commitInBatches(db, snapshot.docs, (batch, document) => {
    batch.delete(document.ref);
  });
  return snapshot.size;
}

async function commitInBatches(db, documents, write) {
  for (let start = 0; start < documents.length; start += BATCH_WRITE_LIMIT) {
    const batch = db.batch();
    for (const document of documents.slice(start, start + BATCH_WRITE_LIMIT)) {
      write(batch, document);
    }
    await batch.commit();
  }
}

async function deleteFilesWithPrefix(bucket, prefix) {
  // A missing prefix lists no files, so a retry is a no-op.
  await bucket.deleteFiles({ prefix, force: true });
}

function numberOrZero(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function stringOrNull(value) {
  return typeof value === "string" && value.length > 0 ? value : null;
}

module.exports = {
  BATCH_WRITE_LIMIT,
  applyQuestionAnswerDeletion,
  deleteOwnAccountData,
  purgeOwnAnswersForAccountDeletion,
};
