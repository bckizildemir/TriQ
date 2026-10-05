const { HttpsError } = require("firebase-functions/v2/https");

const MAX_QUESTION_LIST_ITEMS = 500;

async function createQuestionList({
  db,
  user,
  data,
  createServerTimestamp,
  createDocumentId = () => db.collection("questionLists").doc().id,
}) {
  const uid = permanentUID(user);
  const name = normalizedListName(data?.name);
  const listId = createDocumentId();
  const listRef = db.collection("questionLists").doc(listId);
  const now = createServerTimestamp();

  await db.runTransaction(async (transaction) => {
    transaction.set(listRef, {
      ownerId: uid,
      name,
      questionIds: [],
      visibility: "private",
      createdAt: now,
      updatedAt: now,
    });
  });

  return { listId };
}

async function updateQuestionList({ db, user, data, createServerTimestamp }) {
  const uid = permanentUID(user);
  const listId = requiredString(data?.listId, "listId");
  const name = normalizedListName(data?.name);
  const listRef = db.collection("questionLists").doc(listId);

  await db.runTransaction(async (transaction) => {
    const listSnapshot = await transaction.get(listRef);
    assertOwnedQuestionList(listSnapshot, uid);

    transaction.update(listRef, {
      name,
      updatedAt: createServerTimestamp(),
    });
  });

  return { success: true };
}

async function deleteQuestionList({ db, user, data }) {
  const uid = permanentUID(user);
  const listId = requiredString(data?.listId, "listId");
  const listRef = db.collection("questionLists").doc(listId);

  await db.runTransaction(async (transaction) => {
    const listSnapshot = await transaction.get(listRef);
    assertOwnedQuestionList(listSnapshot, uid);
    transaction.delete(listRef);
  });

  return { success: true };
}

async function setQuestionInList({ db, user, data, createServerTimestamp }) {
  const uid = permanentUID(user);
  const listId = requiredString(data?.listId, "listId");
  const questionId = requiredString(data?.questionId, "questionId");
  const isIncluded = requiredBoolean(data?.isIncluded, "isIncluded");
  const listRef = db.collection("questionLists").doc(listId);
  const questionRef = db.collection("questions").doc(questionId);

  await db.runTransaction(async (transaction) => {
    const [listSnapshot, questionSnapshot] = await Promise.all([
      transaction.get(listRef),
      transaction.get(questionRef),
    ]);
    const list = assertOwnedQuestionList(listSnapshot, uid);
    const question = questionSnapshot.data() || {};

    if (!questionSnapshot.exists || !questionAllowsListMembership(question)) {
      throw new HttpsError("permission-denied", "Question is not available.");
    }

    const currentIds = Array.isArray(list.questionIds)
      ? list.questionIds.filter((value) => typeof value === "string")
      : [];
    const hasQuestion = currentIds.includes(questionId);
    const nextIds = isIncluded
      ? (hasQuestion ? currentIds : [...currentIds, questionId])
      : currentIds.filter((value) => value !== questionId);

    if (nextIds.length > MAX_QUESTION_LIST_ITEMS) {
      throw new HttpsError(
        "failed-precondition",
        `Question lists can contain at most ${MAX_QUESTION_LIST_ITEMS} questions.`
      );
    }

    transaction.update(listRef, {
      questionIds: nextIds,
      updatedAt: createServerTimestamp(),
    });
  });

  return { success: true };
}

function permanentUID(user) {
  if (!user?.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  if (user.isAnonymous === true) {
    throw new HttpsError("permission-denied", "Question lists require a permanent account.");
  }
  return user.uid;
}

function requiredString(value, field) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}

function requiredBoolean(value, field) {
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", `${field} must be a boolean.`);
  }
  return value;
}

function normalizedListName(value) {
  const name = requiredString(value, "name");
  if (name.length > 80) {
    throw new HttpsError("invalid-argument", "name must be 80 characters or fewer.");
  }
  return name;
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

function questionAllowsListMembership(question) {
  const source = question.source || "seeded";
  return source !== "userCreated" || !question.moderationStatus || question.moderationStatus === "approved";
}

module.exports = {
  createQuestionList,
  deleteQuestionList,
  setQuestionInList,
  updateQuestionList,
};
