const { HttpsError } = require("firebase-functions/v2/https");

// The paid AI callables used to have no server-side brake at all: their only guard was "the
// caller has a uid", and the daily limit lived in the client (TTB/Utilities/GuestCapabilityPolicy.swift
// and TTB/Models/AIUsageStats.swift), which also owned the counter document it checked itself
// against. Anonymous sign-in makes a uid free, so one account could spend without any bound.
// This module is the server-side authority. The client-side limit stays as fast UX feedback.

const AI_QUERY_GROUP = "aiQuery";
const QUICK_ANSWER_GROUP = "quickAnswers";

// Server-owned; no client can read or write it. See the aiUsageDaily rule in firestore.rules.
const USAGE_COLLECTION = "aiUsageDaily";

// aiQuery mirrors the client-side policy: 20 a day, or AppConfig.guestDailyAIQueryLimit for a
// guest. quickAnswers is a separate bucket because the client asks for answer chips once per
// question opened (QuestionCardExpandedView), never counts them, and falls back to local
// candidates when the call fails. Its numbers bound abuse rather than shape real use, so they sit
// well above a heavy session. Keep both in step with the Swift values if either side moves.
const DAILY_LIMITS = {
  [AI_QUERY_GROUP]: { anonymous: 5, permanent: 20 },
  [QUICK_ANSWER_GROUP]: { anonymous: 60, permanent: 200 },
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

  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const stored = snapshot.exists ? snapshot.data() : undefined;
    const counts = stored?.dayKey === dayKey ? { ...stored.counts } : {};
    const used = typeof counts[group] === "number" ? counts[group] : 0;

    if (used >= limit) {
      throw new HttpsError("resource-exhausted", "Daily AI limit reached.", {
        reason: "daily-limit",
        group,
        limit,
      });
    }

    counts[group] = used + 1;
    transaction.set(reference, {
      dayKey,
      counts,
      updatedAt: now.toISOString(),
    });

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
  QUICK_ANSWER_GROUP,
  USAGE_COLLECTION,
  consumeDailyQuota,
  dayKeyFor,
  limitFor,
  withDailyQuota,
};
