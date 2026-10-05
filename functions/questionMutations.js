const { HttpsError } = require("firebase-functions/v2/https");

// A guest can hold at most 10 favorites, so this only has to cover migration plus headroom.
const MAX_FAVORITE_ADDITIONS = 50;

async function toggleQuestionFavorite({ db, user, data }) {
  const uid = authenticatedUID(user);
  const questionId = requiredString(data?.questionId, "questionId");
  const questionRef = db.collection("questions").doc(questionId);

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(questionRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Question not found.");
    }

    const question = snapshot.data() || {};
    if (!questionAllowsUserInteraction(question)) {
      throw new HttpsError("permission-denied", "Question is not available.");
    }

    const favoriteUserIds = Array.isArray(question.favoriteUserIds)
      ? question.favoriteUserIds.filter((value) => typeof value === "string")
      : [];
    const isFavorite = favoriteUserIds.includes(uid);
    const updatedFavorites = isFavorite
      ? favoriteUserIds.filter((value) => value !== uid)
      : [...favoriteUserIds, uid];

    transaction.update(questionRef, {
      favoriteUserIds: updatedFavorites,
    });

    return {
      isFavorite: !isFavorite,
      favoriteCount: updatedFavorites.length,
    };
  });
}

// Adds the caller to `favoriteUserIds` on each question. Guest favorites migrate through here
// when a guest upgrades: a direct client batch write cannot do it, because firestore.rules only
// lets a non-admin update `creatorUsername` on `/questions/{questionId}`.
//
// Idempotent by construction — a question the caller already favorited is counted and left
// alone, so a retried migration is harmless. Questions that are missing or not available to
// users are skipped rather than failing the whole batch: a guest can have favorited a community
// question that was unapproved since, and that must not strand the rest of their favorites.
async function addQuestionFavorites({ db, user, data }) {
  const uid = permanentUID(user);
  const questionIds = requiredIDList(data?.questionIds, "questionIds", MAX_FAVORITE_ADDITIONS);

  return db.runTransaction(async (transaction) => {
    const questionRefs = questionIds.map((questionId) => db.collection("questions").doc(questionId));
    const snapshots = await Promise.all(questionRefs.map((ref) => transaction.get(ref)));

    let added = 0;
    let alreadyFavorite = 0;
    const unavailableQuestionIds = [];

    snapshots.forEach((snapshot, index) => {
      if (!snapshot.exists) {
        unavailableQuestionIds.push(questionIds[index]);
        return;
      }

      const question = snapshot.data() || {};
      if (!questionAllowsUserInteraction(question)) {
        unavailableQuestionIds.push(questionIds[index]);
        return;
      }

      const favoriteUserIds = Array.isArray(question.favoriteUserIds)
        ? question.favoriteUserIds.filter((value) => typeof value === "string")
        : [];
      if (favoriteUserIds.includes(uid)) {
        alreadyFavorite += 1;
        return;
      }

      transaction.update(questionRefs[index], {
        favoriteUserIds: [...favoriteUserIds, uid],
      });
      added += 1;
    });

    // `unavailableQuestionIds` lets the caller retain exactly the ids the account did not
    // accept, instead of losing them — see FavoriteStore.migrateGuestFavorites.
    return {
      added,
      alreadyFavorite,
      unavailable: unavailableQuestionIds.length,
      unavailableQuestionIds,
    };
  });
}

async function saveQuestionAnswers({
  db,
  user,
  data,
  createTimestampFromDate,
}) {
  const uid = authenticatedUID(user);
  const questionId = requiredString(data?.questionId, "questionId");
  const answers = normalizedStringSlots(data?.answers, "answers");
  const imageURLs = normalizedOptionalStringSlots(data?.imageURLs);
  const imageAttributions = normalizedAttributionSlots(data?.imageAttributions);
  const filledCount = answers.filter((answer) => answer.length > 0).length;
  const requestContainsContent = filledCount > 0
    || imageURLs.some((url) => url.length > 0)
    || imageAttributions.some((attribution) => Object.keys(attribution).length > 0);
  const isAnonymous = user?.isAnonymous === true;
  const badgeDefinitions = isAnonymous || filledCount < 3
    ? []
    : await fetchBadgeDefinitions(db);

  const questionRef = db.collection("questions").doc(questionId);
  const userAnswerRef = questionRef.collection("userAnswers").doc(uid);
  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (transaction) => {
    const userAnswerSnapshot = await transaction.get(userAnswerRef);
    if (!userAnswerSnapshot.exists && !requestContainsContent) {
      return { didWrite: false };
    }

    const questionSnapshot = await transaction.get(questionRef);
    if (!questionSnapshot.exists) {
      throw new HttpsError("not-found", "Question not found.");
    }

    const question = questionSnapshot.data() || {};
    if (!questionAllowsUserInteraction(question)) {
      throw new HttpsError("permission-denied", "Question is not available.");
    }

    const previousAnswerData = userAnswerSnapshot.data() || {};
    const previousAnswers = Array.isArray(previousAnswerData.answers)
      ? previousAnswerData.answers.filter((answer) => typeof answer === "string")
      : [];
    const previousFilledCount = previousAnswers.filter((answer) => answer.length > 0).length;
    const answeredAt = timestampToDate(previousAnswerData.answeredAt);
    const answeredToday = answeredAt ? sameUTCDate(answeredAt, new Date()) : false;
    const isExistingUser = userAnswerSnapshot.exists;

    const answerStats = answerStatsFromFirestore(question.answerStats);
    decrementAnswerStats(answerStats, previousAnswers);
    incrementAnswerStats(answerStats, answers);

    const today = todayDateString();
    const storedTodayDate = typeof question.todayDate === "string" ? question.todayDate : "";
    let totalRespondents = numberOrZero(question.totalRespondents);
    let todayRespondents = numberOrZero(question.todayRespondents);

    if (!isExistingUser && requestContainsContent) {
      totalRespondents += 1;
    }

    if (requestContainsContent) {
      if (storedTodayDate !== today) {
        todayRespondents = 1;
      } else if (!isExistingUser || !answeredToday) {
        todayRespondents += 1;
      }
    }

    const nowDate = new Date();
    const now = createTimestampFromDate(nowDate);
    let completionUserUpdates = null;
    const isCompletionCandidate = !isAnonymous && previousFilledCount < 3 && filledCount === 3;
    if (isCompletionCandidate) {
      const userSnapshot = await transaction.get(userRef);
      const userData = userSnapshot.data() || {};
      const completedQuestionIds = new Set(arrayOfStrings(userData.completedQuestionIds));

      if (!completedQuestionIds.has(questionId)) {
        const currentTotal = numberOrZero(userData.totalAnswered || userData.totalAnswers);
        const newTotal = currentTotal + 1;
        const categoryAnswers = intMap(userData.categoryAnswers);
        if (typeof question.category === "string" && question.category.length > 0) {
          categoryAnswers[question.category] = (categoryAnswers[question.category] || 0) + 1;
        }

        const currentStreak = numberOrZero(userData.currentStreak);
        const lastAnsweredDate = timestampToDate(userData.lastAnsweredDate);
        const newStreak = updatedStreak(lastAnsweredDate, currentStreak, nowDate);
        const updatedCompletedQuestionIds = [...completedQuestionIds, questionId];
        completionUserUpdates = {
          totalAnswered: newTotal,
          dailyAnswers: numberOrZero(userData.dailyAnswers) + 1,
          weeklyAnswers: numberOrZero(userData.weeklyAnswers) + 1,
          completedQuestionIds: updatedCompletedQuestionIds,
          categoryAnswers,
          currentStreak: newStreak,
          lastAnsweredDate: now,
        };

        if (badgeDefinitions.length > 0) {
          const unlockedBadges = arrayOfStrings(userData.unlockedBadges);
          const badgeProgress = doubleMap(userData.badgeProgress);

          for (const badge of badgeDefinitions) {
            const progress = badgeProgressValue(badge, {
              totalAnswered: newTotal,
              categoryAnswers,
              currentStreak: newStreak,
            });
            badgeProgress[badge.id] = progress;
            if (progress >= 1 && !unlockedBadges.includes(badge.id)) {
              unlockedBadges.push(badge.id);
            }
          }

          completionUserUpdates.unlockedBadges = unlockedBadges;
          completionUserUpdates.badgeProgress = badgeProgress;
        }
      }
    }

    transaction.update(questionRef, {
      lastAnsweredAt: now,
      answerStats: answerStatsForFirestore(answerStats),
      totalRespondents,
      todayRespondents,
      todayDate: today,
    });

    transaction.set(userAnswerRef, {
      answers,
      answeredAt: now,
      userId: uid,
      imageURLs,
      imageAttributions,
    });

    if (completionUserUpdates) {
      transaction.set(userRef, completionUserUpdates, { merge: true });
    }

    return {
      didWrite: true,
    };
  });
}

function authenticatedUID(user) {
  if (!user?.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  return user.uid;
}

function permanentUID(user) {
  const uid = authenticatedUID(user);
  if (user.isAnonymous === true) {
    throw new HttpsError("permission-denied", "Adding favorites requires a permanent account.");
  }
  return uid;
}

function requiredString(value, field) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value.trim();
}

function requiredIDList(value, field, maximumCount) {
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", `${field} must be an array.`);
  }

  const ids = [...new Set(
    value
      .filter((item) => typeof item === "string")
      .map((item) => item.trim())
      .filter((item) => item.length > 0)
  )];

  if (ids.length === 0) {
    throw new HttpsError("invalid-argument", `${field} must contain at least one id.`);
  }
  if (ids.length > maximumCount) {
    throw new HttpsError("invalid-argument", `${field} accepts at most ${maximumCount} ids.`);
  }
  return ids;
}

function normalizedStringSlots(value, field) {
  if (!Array.isArray(value)) {
    throw new HttpsError("invalid-argument", `${field} must be an array.`);
  }

  const slots = value.map((item) => typeof item === "string" ? item.trim() : "");
  while (slots.length < 3) {
    slots.push("");
  }
  return slots.slice(0, 3);
}

function normalizedOptionalStringSlots(value) {
  const slots = Array.isArray(value) ? value : [];
  const normalized = slots.map((item) => typeof item === "string" ? item.trim() : "");
  while (normalized.length < 3) {
    normalized.push("");
  }
  return normalized.slice(0, 3);
}

function normalizedAttributionSlots(value) {
  const slots = Array.isArray(value) ? value : [];
  const normalized = slots.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      return {};
    }
    return Object.fromEntries(
      Object.entries(item).filter(([, entry]) => typeof entry === "string")
    );
  });
  while (normalized.length < 3) {
    normalized.push({});
  }
  return normalized.slice(0, 3);
}

function questionAllowsUserInteraction(question) {
  const source = question.source || "seeded";
  return source !== "userCreated" || !question.moderationStatus || question.moderationStatus === "approved";
}

async function fetchBadgeDefinitions(db) {
  const snapshot = await db.collection("badges").get();
  return snapshot.docs
    .map((document) => {
      const data = document.data() || {};
      return {
        id: document.id,
        targetCount: numberOrZero(data.targetCount),
        type: typeof data.type === "string" ? data.type : "total",
        category: typeof data.category === "string" ? data.category : null,
      };
    })
    .filter((badge) => badge.id && badge.targetCount > 0);
}

function answerStatsFromFirestore(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  return Object.fromEntries(
    Object.entries(value).map(([slot, slotStats]) => [slot, intMap(slotStats)])
  );
}

function answerStatsForFirestore(answerStats) {
  return Object.fromEntries(
    Object.entries(answerStats).filter(([, slotStats]) => Object.keys(slotStats).length > 0)
  );
}

function decrementAnswerStats(answerStats, answers) {
  answers.forEach((answer, index) => {
    if (typeof answer !== "string" || answer.length === 0) {
      return;
    }
    const slot = `${index}`;
    const slotStats = answerStats[slot] || {};
    const updatedCount = Math.max(0, numberOrZero(slotStats[answer]) - 1);
    if (updatedCount === 0) {
      delete slotStats[answer];
    } else {
      slotStats[answer] = updatedCount;
    }
    answerStats[slot] = slotStats;
  });
}

function incrementAnswerStats(answerStats, answers) {
  answers.forEach((answer, index) => {
    if (answer.length === 0) {
      return;
    }
    const slot = `${index}`;
    const slotStats = answerStats[slot] || {};
    slotStats[answer] = numberOrZero(slotStats[answer]) + 1;
    answerStats[slot] = slotStats;
  });
}

function intMap(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  return Object.fromEntries(
    Object.entries(value)
      .filter(([, entry]) => Number.isFinite(Number(entry)))
      .map(([key, entry]) => [key, Number(entry)])
  );
}

function doubleMap(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }
  return Object.fromEntries(
    Object.entries(value)
      .filter(([, entry]) => Number.isFinite(Number(entry)))
      .map(([key, entry]) => [key, Number(entry)])
  );
}

function arrayOfStrings(value) {
  return Array.isArray(value) ? value.filter((item) => typeof item === "string") : [];
}

function numberOrZero(value) {
  return Number.isFinite(Number(value)) ? Number(value) : 0;
}

function timestampToDate(value) {
  if (value instanceof Date) {
    return value;
  }
  if (typeof value?.toDate === "function") {
    return value.toDate();
  }
  return null;
}

function todayDateString(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

function sameUTCDate(left, right) {
  return todayDateString(left) === todayDateString(right);
}

function updatedStreak(lastAnsweredDate, currentStreak, now) {
  if (!lastAnsweredDate) {
    return 1;
  }
  const lastDay = Date.UTC(
    lastAnsweredDate.getUTCFullYear(),
    lastAnsweredDate.getUTCMonth(),
    lastAnsweredDate.getUTCDate()
  );
  const currentDay = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const dayDelta = Math.floor((currentDay - lastDay) / 86_400_000);
  if (dayDelta === 0) {
    return currentStreak;
  }
  if (dayDelta === 1) {
    return currentStreak + 1;
  }
  return 1;
}

function badgeProgressValue(badge, state) {
  if (badge.targetCount <= 0) {
    return 0;
  }

  switch (badge.type) {
  case "category":
    return clampProgress(numberOrZero(state.categoryAnswers[badge.category]) / badge.targetCount);
  case "streak":
    return clampProgress(state.currentStreak / badge.targetCount);
  case "total":
  default:
    return clampProgress(state.totalAnswered / badge.targetCount);
  }
}

function clampProgress(value) {
  return Math.max(0, Math.min(Number.isFinite(value) ? value : 0, 1));
}

module.exports = {
  addQuestionFavorites,
  saveQuestionAnswers,
  toggleQuestionFavorite,
};
