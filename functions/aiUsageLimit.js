const { HttpsError } = require("firebase-functions/v2/https");

// The paid AI callables used to have no server-side brake at all: their only guard was "the
// caller has a uid", and the daily limit lived in the client (TTB/Utilities/GuestCapabilityPolicy.swift
// and TTB/Models/AIUsageStats.swift), which also owned the counter document it checked itself
// against. Anonymous sign-in makes a uid free, so one account could spend without any bound.
// This module is the server-side authority. The client-side limit stays as fast UX feedback.

const AI_QUERY_GROUP = "aiQuery";
const QUICK_ANSWER_GROUP = "quickAnswers";
// Not AI, but the same per-uid daily counter bounds them. Pexels has an hourly quota shared by
// every user, each saved image is a Storage object, and each share fans out to one read per
// listed question.
const IMAGE_SUGGESTION_GROUP = "imageSuggestions";
const IMAGE_SAVE_GROUP = "answerImageSaves";
const SHARE_WRITE_GROUP = "shareWrites";

// Server-owned; no client can read or write it. See the aiUsageDaily rule in firestore.rules.
const USAGE_COLLECTION = "aiUsageDaily";
// One document per UTC day that counts every caller together. Server-owned like the per-uid
// counter; see the aiUsageProjectDaily rule in firestore.rules.
const PROJECT_USAGE_COLLECTION = "aiUsageProjectDaily";

// aiQuery mirrors the client-side policy: 20 a day, or AppConfig.guestDailyAIQueryLimit for a
// guest. quickAnswers is a separate bucket because the client asks for answer chips once per
// question opened (QuestionCardExpandedView), never counts them, and falls back to local
// candidates when the call fails. Its numbers bound abuse rather than shape real use, so they sit
// well above a heavy session. Keep both in step with the Swift values if either side moves.
const DAILY_LIMITS = {
  [AI_QUERY_GROUP]: { anonymous: 5, permanent: 20 },
  [QUICK_ANSWER_GROUP]: { anonymous: 60, permanent: 200 },
  [IMAGE_SUGGESTION_GROUP]: { anonymous: 30, permanent: 100 },
  [IMAGE_SAVE_GROUP]: { anonymous: 15, permanent: 60 },
  [SHARE_WRITE_GROUP]: { anonymous: 5, permanent: 50 },
};

// The per-uid limits do not bound the total: anonymous sign-in makes a new uid free, so a script
// that signs in again for every few calls still spends without limit. This cap is the project-wide
// ceiling on the groups that cost money per call (the AI provider). It sits far above real use and
// exists to stop a runaway bill, not to shape traffic. A group without an entry has no project cap.
// Every capped call writes the same document, and Firestore sustains about one write per second
// on one document, so raise these numbers or shard the document before traffic gets near that.
const PROJECT_DAILY_LIMITS = {
  [AI_QUERY_GROUP]: 1000,
  [QUICK_ANSWER_GROUP]: 5000,
};

/**
 * The day a request counts against, in UTC. The client resets on the device's calendar day, which
 * a caller controls; the server must not.
 */
function dayKeyFor(now) {
  return now.toISOString().slice(0, 10);
}

function limitFor(group, isAnonymous) {
  const limits = DAILY_LIMITS[group];
  if (!limits) {
    throw new HttpsError("internal", `Unknown AI usage group: ${group}.`);
  }
  return isAnonymous ? limits.anonymous : limits.permanent;
}

/**
 * Records one attempt for this caller and group, or rejects when the day's limit is spent.
 * Attempts count, not successes: the money goes out when we call the provider, so a caller who
 * retries into a provider error must not get those calls for free.
 */
async function consumeDailyQuota({ db, uid, group, isAnonymous, now }) {
  const limit = limitFor(group, isAnonymous);
  const dayKey = dayKeyFor(now);
  const reference = db.collection(USAGE_COLLECTION).doc(uid);
  const projectLimit = PROJECT_DAILY_LIMITS[group];
  const projectReference = projectLimit === undefined
    ? undefined
    : db.collection(PROJECT_USAGE_COLLECTION).doc(dayKey);

  return db.runTransaction(async (transaction) => {
    // A transaction must finish every read before its first write.
    const snapshot = await transaction.get(reference);
    const projectSnapshot = projectReference ? await transaction.get(projectReference) : undefined;

    const stored = snapshot.exists ? snapshot.data() : undefined;
    const counts = stored?.dayKey === dayKey ? { ...stored.counts } : {};
    const used = typeof counts[group] === "number" ? counts[group] : 0;

    if (used >= limit) {
      throw new HttpsError("resource-exhausted", "Daily limit reached.", {
        reason: "daily-limit",
        group,
        limit,
      });
    }

    let projectCounts;
    if (projectReference) {
      projectCounts = projectSnapshot.exists ? { ...projectSnapshot.data().counts } : {};
      const projectUsed = typeof projectCounts[group] === "number" ? projectCounts[group] : 0;
      if (projectUsed >= projectLimit) {
        throw new HttpsError("resource-exhausted", "Daily limit reached.", {
          reason: "project-daily-limit",
          group,
        });
      }
      projectCounts[group] = projectUsed + 1;
    }

    counts[group] = used + 1;
    transaction.set(reference, {
      dayKey,
      counts,
      updatedAt: now.toISOString(),
    });
    if (projectReference) {
      transaction.set(projectReference, {
        dayKey,
        counts: projectCounts,
        updatedAt: now.toISOString(),
      });
    }

    return { used: counts[group], limit };
  });
}

/**
 * Wraps a callable handler so the request spends quota before it reaches the provider. Auth is
 * checked here as well as in the handler, so an unauthenticated caller costs no transaction.
 */
function withDailyQuota({ db, group, now = () => new Date() }, handler) {
  return async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentication is required.");
    }

    await consumeDailyQuota({
      db,
      uid,
      group,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
      now: now(),
    });

    return handler(request);
  };
}

module.exports = {
  AI_QUERY_GROUP,
  DAILY_LIMITS,
  IMAGE_SAVE_GROUP,
  IMAGE_SUGGESTION_GROUP,
  PROJECT_DAILY_LIMITS,
  PROJECT_USAGE_COLLECTION,
  SHARE_WRITE_GROUP,
  QUICK_ANSWER_GROUP,
  USAGE_COLLECTION,
  consumeDailyQuota,
  dayKeyFor,
  limitFor,
  withDailyQuota,
};
