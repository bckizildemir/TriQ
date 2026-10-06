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

// The per-uid limits do not bound the total: a new guest uid is free, so a script that signs in
// again every few calls still spends without limit. These caps bound the whole project for the
// groups that call the AI provider. They sit under the provider's own free-tier limits (Groq,
// openai/gpt-oss-120b: 30 requests a minute, 1000 a day, 200K tokens a day; at up to ~800 tokens
// a call, 200 calls is ~160K tokens), so an attacker meets our 429 before the provider sees abuse
// traffic from our key. Guests and verified accounts have separate pools, so an attacker who
// spends the guest pool does not take AI away from verified users. The pool is not the per-uid
// tier above: an email account whose address is not verified costs an attacker as little as an
// anonymous one, so it draws from the guest pool (isGuestToken) while it keeps the permanent
// per-uid limit. A group without an entry has no project cap. Recheck these numbers if the
// provider, the model or maxTokens changes.
const PROJECT_DAILY_LIMITS = {
  [AI_QUERY_GROUP]: { guest: 30, verified: 60 },
  [QUICK_ANSWER_GROUP]: { guest: 50, verified: 60 },
};

// Every capped call in a minute, both pools and all groups together. Below the provider's 30
// requests a minute, so a burst cannot trip its rate limiter.
const PROJECT_MINUTE_LIMIT = 20;

/**
 * The day a request counts against, in UTC. The client resets on the device's calendar day, which
 * a caller controls; the server must not.
 */
function dayKeyFor(now) {
  return now.toISOString().slice(0, 10);
}

/** The minute a request counts against, in UTC: "2026-07-31T09:05". */
function minuteKeyFor(now) {
  return now.toISOString().slice(0, 16);
}

function poolFor(isGuest) {
  return isGuest ? "guest" : "verified";
}

function limitFor(group, isAnonymous) {
  const limits = DAILY_LIMITS[group];
  if (!limits) {
    throw new HttpsError("internal", `Unknown AI usage group: ${group}.`);
  }
  return isAnonymous ? limits.anonymous : limits.permanent;
}

/**
 * The project pool for this caller, read from the verified ID token, never from the request body.
 * Only a non-anonymous account with email_verified === true draws from the verified pool.
 */
function isGuestToken(token) {
  return token?.firebase?.sign_in_provider === "anonymous" || token?.email_verified !== true;
}

/**
 * Records one attempt for this caller and group, or rejects when the day's limit is spent.
 * Attempts count, not successes: the money goes out when we call the provider, so a caller who
 * retries into a provider error must not get those calls for free.
 */
async function consumeDailyQuota({ db, uid, group, isAnonymous, isGuest = isAnonymous, now }) {
  const limit = limitFor(group, isAnonymous);
  const dayKey = dayKeyFor(now);
  const reference = db.collection(USAGE_COLLECTION).doc(uid);
  const projectLimits = PROJECT_DAILY_LIMITS[group];
  const projectReference = projectLimits === undefined
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

    let projectDocument;
    if (projectReference) {
      projectDocument = nextProjectDocument({
        stored: projectSnapshot.exists ? projectSnapshot.data() : undefined,
        group,
        pool: poolFor(isGuest),
        limit: projectLimits[poolFor(isGuest)],
        dayKey,
        now,
      });
    }

    counts[group] = used + 1;
    transaction.set(reference, {
      dayKey,
      counts,
      updatedAt: now.toISOString(),
    });
    if (projectDocument) {
      transaction.set(projectReference, projectDocument);
    }

    return { used: counts[group], limit };
  });
}

/**
 * The project document after one more call in this group and pool, or a rejection when the pool's
 * day or the project's minute is spent. Counts are keyed "group:pool", for example "aiQuery:guest".
 */
function nextProjectDocument({ stored, group, pool, limit, dayKey, now }) {
  const counts = { ...stored?.counts };
  const countKey = `${group}:${pool}`;
  const used = typeof counts[countKey] === "number" ? counts[countKey] : 0;

  if (used >= limit) {
    throw new HttpsError("resource-exhausted", "Daily limit reached.", {
      reason: "project-daily-limit",
      group,
    });
  }

  const minuteKey = minuteKeyFor(now);
  const minuteCount = stored?.minuteKey === minuteKey && typeof stored.minuteCount === "number"
    ? stored.minuteCount
    : 0;

  if (minuteCount >= PROJECT_MINUTE_LIMIT) {
    throw new HttpsError("resource-exhausted", "Too many requests. Try again in a minute.", {
      reason: "project-minute-limit",
      group,
    });
  }

  counts[countKey] = used + 1;
  return {
    dayKey,
    counts,
    minuteKey,
    minuteCount: minuteCount + 1,
    updatedAt: now.toISOString(),
  };
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
      isGuest: isGuestToken(request.auth?.token),
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
  PROJECT_MINUTE_LIMIT,
  PROJECT_USAGE_COLLECTION,
  SHARE_WRITE_GROUP,
  QUICK_ANSWER_GROUP,
  USAGE_COLLECTION,
  consumeDailyQuota,
  dayKeyFor,
  isGuestToken,
  limitFor,
  minuteKeyFor,
  withDailyQuota,
};
