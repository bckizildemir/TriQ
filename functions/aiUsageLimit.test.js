const test = require("node:test");
const assert = require("node:assert/strict");

const {
  AI_QUERY_GROUP,
  IMAGE_SUGGESTION_GROUP,
  PROJECT_DAILY_LIMITS,
  PROJECT_MINUTE_LIMIT,
  PROJECT_USAGE_COLLECTION,
  QUICK_ANSWER_GROUP,
  USAGE_COLLECTION,
  consumeDailyQuota,
  dayKeyFor,
  isGuestToken,
  limitFor,
  withDailyQuota,
} = require("./aiUsageLimit");

test("the day key is UTC, so the reset point does not follow the caller's device clock", () => {
  assert.equal(dayKeyFor(new Date("2026-07-31T23:30:00Z")), "2026-07-31");
  assert.equal(dayKeyFor(new Date("2026-08-01T00:30:00Z")), "2026-08-01");
});

test("anonymous callers get the guest limit and permanent callers get the full limit", () => {
  assert.equal(limitFor(AI_QUERY_GROUP, true), 5);
  assert.equal(limitFor(AI_QUERY_GROUP, false), 20);
  assert.equal(limitFor(QUICK_ANSWER_GROUP, true), 60);
  assert.equal(limitFor(QUICK_ANSWER_GROUP, false), 200);
});

test("an unknown group is a programming error, not a request the caller can make", () => {
  assert.throws(
    () => limitFor("notAGroup", false),
    (error) => error.code === "internal"
  );
});

test("the first call of the day records one attempt against today's key", async () => {
  const db = createFakeDb();

  const result = await consumeDailyQuota({
    db,
    uid: "user-1",
    group: AI_QUERY_GROUP,
    isAnonymous: false,
    now: new Date("2026-07-31T09:00:00Z"),
  });

  assert.deepEqual(result, { used: 1, limit: 20 });
  assert.deepEqual(db.documents.get(`${USAGE_COLLECTION}/user-1`), {
    dayKey: "2026-07-31",
    counts: { [AI_QUERY_GROUP]: 1 },
    updatedAt: "2026-07-31T09:00:00.000Z",
  });
});

test("a caller at the limit is rejected and the stored count does not move", async () => {
  const db = createFakeDb({
    [`${USAGE_COLLECTION}/user-1`]: {
      dayKey: "2026-07-31",
      counts: { [AI_QUERY_GROUP]: 20 },
      updatedAt: "2026-07-31T08:00:00.000Z",
    },
  });

  await assert.rejects(
    () => consumeDailyQuota({
      db,
      uid: "user-1",
      group: AI_QUERY_GROUP,
      isAnonymous: false,
      now: new Date("2026-07-31T09:00:00Z"),
    }),
    (error) => error.code === "resource-exhausted"
      && error.details.reason === "daily-limit"
      && error.details.limit === 20
  );

  assert.equal(
    db.documents.get(`${USAGE_COLLECTION}/user-1`).counts[AI_QUERY_GROUP],
    20
  );
});

test("a count stored under an earlier day key resets instead of carrying over", async () => {
  const db = createFakeDb({
    [`${USAGE_COLLECTION}/user-1`]: {
      dayKey: "2026-07-30",
      counts: { [AI_QUERY_GROUP]: 20 },
      updatedAt: "2026-07-30T22:00:00.000Z",
    },
  });

  const result = await consumeDailyQuota({
    db,
    uid: "user-1",
    group: AI_QUERY_GROUP,
    isAnonymous: false,
    now: new Date("2026-07-31T09:00:00Z"),
  });

  assert.deepEqual(result, { used: 1, limit: 20 });
  assert.deepEqual(
    db.documents.get(`${USAGE_COLLECTION}/user-1`).counts,
    { [AI_QUERY_GROUP]: 1 }
  );
});

test("the two groups count separately, so answer chips cannot drain the AI query quota", async () => {
  const db = createFakeDb({
    [`${USAGE_COLLECTION}/user-1`]: {
      dayKey: "2026-07-31",
      counts: { [QUICK_ANSWER_GROUP]: 199 },
      updatedAt: "2026-07-31T08:00:00.000Z",
    },
  });

  const result = await consumeDailyQuota({
    db,
    uid: "user-1",
    group: AI_QUERY_GROUP,
    isAnonymous: false,
    now: new Date("2026-07-31T09:00:00Z"),
  });

  assert.deepEqual(result, { used: 1, limit: 20 });
  assert.deepEqual(db.documents.get(`${USAGE_COLLECTION}/user-1`).counts, {
    [QUICK_ANSWER_GROUP]: 199,
    [AI_QUERY_GROUP]: 1,
  });
});

test("an anonymous caller is rejected at the guest limit, well before the permanent one", async () => {
  const db = createFakeDb({
    [`${USAGE_COLLECTION}/guest-1`]: {
      dayKey: "2026-07-31",
      counts: { [AI_QUERY_GROUP]: 5 },
      updatedAt: "2026-07-31T08:00:00.000Z",
    },
  });

  await assert.rejects(
    () => consumeDailyQuota({
      db,
      uid: "guest-1",
      group: AI_QUERY_GROUP,
      isAnonymous: true,
      now: new Date("2026-07-31T09:00:00Z"),
    }),
    (error) => error.code === "resource-exhausted" && error.details.limit === 5
  );
});

test("an unauthenticated request is rejected before the counter is touched", async () => {
  const db = createFakeDb();
  const guarded = withDailyQuota(
    { db, group: AI_QUERY_GROUP, now: () => new Date("2026-07-31T09:00:00Z") },
    async () => "handler ran"
  );

  await assert.rejects(
    () => guarded({ data: {} }),
    (error) => error.code === "unauthenticated"
  );
  assert.equal(db.stats.transactions, 0);
});

test("a permitted request reaches the handler and consumes exactly one attempt", async () => {
  const db = createFakeDb();
  const received = [];
  const guarded = withDailyQuota(
    { db, group: AI_QUERY_GROUP, now: () => new Date("2026-07-31T09:00:00Z") },
    async (request) => {
      received.push(request);
      return { answer: "ok" };
    }
  );

  const result = await guarded({
    auth: { uid: "user-1", token: { firebase: { sign_in_provider: "password" }, email_verified: true } },
    data: { question: "Why?" },
  });

  assert.deepEqual(result, { answer: "ok" });
  assert.equal(received.length, 1);
  assert.deepEqual(received[0].data, { question: "Why?" });
  assert.equal(
    db.documents.get(`${USAGE_COLLECTION}/user-1`).counts[AI_QUERY_GROUP],
    1
  );
});

test("an anonymous sign-in provider is read from the token, not from the request body", async () => {
  const db = createFakeDb({
    [`${USAGE_COLLECTION}/guest-1`]: {
      dayKey: "2026-07-31",
      counts: { [AI_QUERY_GROUP]: 5 },
      updatedAt: "2026-07-31T08:00:00.000Z",
    },
  });
  const guarded = withDailyQuota(
    { db, group: AI_QUERY_GROUP, now: () => new Date("2026-07-31T09:00:00Z") },
    async () => "handler ran"
  );

  await assert.rejects(
    () => guarded({
      auth: { uid: "guest-1", token: { firebase: { sign_in_provider: "anonymous" } } },
      data: { isAnonymous: false },
    }),
    (error) => error.code === "resource-exhausted" && error.details.limit === 5
  );
});

test("a failed handler still consumes the attempt, because the provider call is what costs money", async () => {
  const db = createFakeDb();
  const guarded = withDailyQuota(
    { db, group: AI_QUERY_GROUP, now: () => new Date("2026-07-31T09:00:00Z") },
    async () => {
      throw new Error("provider exploded");
    }
  );

  await assert.rejects(
    () => guarded({
      auth: { uid: "user-1", token: { firebase: { sign_in_provider: "password" }, email_verified: true } },
      data: {},
    }),
    (error) => error.message === "provider exploded"
  );

  assert.equal(
    db.documents.get(`${USAGE_COLLECTION}/user-1`).counts[AI_QUERY_GROUP],
    1
  );
});

const PROJECT_DOC = `${PROJECT_USAGE_COLLECTION}/2026-07-31`;
const NINE_AM = new Date("2026-07-31T09:00:00Z");

function consume(db, { uid = "user-1", group = AI_QUERY_GROUP, isAnonymous = false, isGuest = isAnonymous, now = NINE_AM } = {}) {
  return consumeDailyQuota({ db, uid, group, isAnonymous, isGuest, now });
}

test("the limits stay under the provider's free tier: 1000 requests a day and 30 a minute", () => {
  let dailyTotal = 0;
  for (const pools of Object.values(PROJECT_DAILY_LIMITS)) {
    dailyTotal += pools.guest + pools.verified;
  }
  assert.ok(dailyTotal <= 200, `project daily total ${dailyTotal} must stay at or under 200`);
  assert.ok(PROJECT_MINUTE_LIMIT < 30);
});

test("only a non-anonymous account with a verified email is outside the guest pool", () => {
  assert.equal(isGuestToken({ firebase: { sign_in_provider: "anonymous" } }), true);
  assert.equal(isGuestToken({ firebase: { sign_in_provider: "password" } }), true);
  assert.equal(isGuestToken({ firebase: { sign_in_provider: "password" }, email_verified: false }), true);
  assert.equal(isGuestToken({ firebase: { sign_in_provider: "password" }, email_verified: "true" }), true);
  assert.equal(isGuestToken(undefined), true);
  assert.equal(isGuestToken({ firebase: { sign_in_provider: "password" }, email_verified: true }), false);
  assert.equal(isGuestToken({ firebase: { sign_in_provider: "anonymous" }, email_verified: true }), true);
});

test("an unverified email account keeps the permanent per-uid limit but draws from the guest pool", async () => {
  const db = createFakeDb({
    [`${USAGE_COLLECTION}/user-1`]: {
      dayKey: "2026-07-31",
      counts: { [AI_QUERY_GROUP]: 5 },
      updatedAt: "2026-07-31T08:00:00.000Z",
    },
  });
  const guarded = withDailyQuota({ db, group: AI_QUERY_GROUP, now: () => NINE_AM }, async () => "ran");

  const result = await guarded({ auth: { uid: "user-1", token: { firebase: { sign_in_provider: "password" } } }, data: {} });

  assert.equal(result, "ran");
  assert.equal(db.documents.get(`${USAGE_COLLECTION}/user-1`).counts[AI_QUERY_GROUP], 6);
  assert.deepEqual(db.documents.get(PROJECT_DOC).counts, { [`${AI_QUERY_GROUP}:guest`]: 1 });
});

test("a capped call counts in its pool and in the minute for the UTC day", async () => {
  const db = createFakeDb();

  await consume(db, { isGuest: true });

  assert.deepEqual(db.documents.get(PROJECT_DOC), {
    dayKey: "2026-07-31",
    counts: { [`${AI_QUERY_GROUP}:guest`]: 1 },
    minuteKey: "2026-07-31T09:00",
    minuteCount: 1,
    updatedAt: "2026-07-31T09:00:00.000Z",
  });
});

test("a fresh guest uid is rejected once the guest pool is spent, and nothing is written", async () => {
  const guestLimit = PROJECT_DAILY_LIMITS[AI_QUERY_GROUP].guest;
  const db = createFakeDb({
    [PROJECT_DOC]: { dayKey: "2026-07-31", counts: { [`${AI_QUERY_GROUP}:guest`]: guestLimit } },
  });

  await assert.rejects(
    () => consume(db, { uid: "fresh-guest", isGuest: true }),
    (error) => error.code === "resource-exhausted" && error.details.reason === "project-daily-limit"
  );

  assert.equal(db.documents.get(`${USAGE_COLLECTION}/fresh-guest`), undefined);
  assert.equal(db.documents.get(PROJECT_DOC).counts[`${AI_QUERY_GROUP}:guest`], guestLimit);
});

test("a spent guest pool does not block verified accounts", async () => {
  const db = createFakeDb({
    [PROJECT_DOC]: {
      dayKey: "2026-07-31",
      counts: { [`${AI_QUERY_GROUP}:guest`]: PROJECT_DAILY_LIMITS[AI_QUERY_GROUP].guest },
    },
  });

  const result = await consume(db, { isGuest: false });

  assert.deepEqual(result, { used: 1, limit: 20 });
  assert.equal(db.documents.get(PROJECT_DOC).counts[`${AI_QUERY_GROUP}:verified`], 1);
});

test("the minute limit covers every pool and group together", async () => {
  const db = createFakeDb({
    [PROJECT_DOC]: { dayKey: "2026-07-31", counts: {}, minuteKey: "2026-07-31T09:00", minuteCount: PROJECT_MINUTE_LIMIT },
  });

  await assert.rejects(
    () => consume(db, { group: QUICK_ANSWER_GROUP, isGuest: false, now: new Date("2026-07-31T09:00:59Z") }),
    (error) => error.code === "resource-exhausted" && error.details.reason === "project-minute-limit"
  );
  assert.equal(db.documents.get(`${USAGE_COLLECTION}/user-1`), undefined);
});

test("the minute count starts again in the next minute", async () => {
  const db = createFakeDb({
    [PROJECT_DOC]: { dayKey: "2026-07-31", counts: {}, minuteKey: "2026-07-31T09:00", minuteCount: PROJECT_MINUTE_LIMIT },
  });

  await consume(db, { now: new Date("2026-07-31T09:01:00Z") });

  assert.equal(db.documents.get(PROJECT_DOC).minuteKey, "2026-07-31T09:01");
  assert.equal(db.documents.get(PROJECT_DOC).minuteCount, 1);
});

test("the project pools start again on a new UTC day", async () => {
  const db = createFakeDb({
    [`${PROJECT_USAGE_COLLECTION}/2026-07-30`]: {
      dayKey: "2026-07-30",
      counts: { [`${AI_QUERY_GROUP}:verified`]: PROJECT_DAILY_LIMITS[AI_QUERY_GROUP].verified },
    },
  });

  const result = await consume(db, { now: new Date("2026-07-31T00:10:00Z") });

  assert.deepEqual(result, { used: 1, limit: 20 });
});

test("a caller over their own limit does not spend the project pool", async () => {
  const db = createFakeDb({
    [`${USAGE_COLLECTION}/user-1`]: {
      dayKey: "2026-07-31",
      counts: { [AI_QUERY_GROUP]: 20 },
      updatedAt: "2026-07-31T08:00:00.000Z",
    },
  });

  await assert.rejects(() => consume(db), (error) => error.details.reason === "daily-limit");
  assert.equal(db.documents.get(PROJECT_DOC), undefined);
});

test("a group without a project cap writes no project document", async () => {
  assert.equal(PROJECT_DAILY_LIMITS[IMAGE_SUGGESTION_GROUP], undefined);
  const db = createFakeDb();

  await consumeDailyQuota({
    db,
    uid: "user-1",
    group: IMAGE_SUGGESTION_GROUP,
    isAnonymous: false,
    now: new Date("2026-07-31T09:00:00Z"),
  });

  assert.equal(db.documents.get(`${PROJECT_USAGE_COLLECTION}/2026-07-31`), undefined);
});

function createFakeDb(initialDocuments = {}) {
  const documents = new Map(
    Object.entries(initialDocuments).map(([path, data]) => [path, structuredClone(data)])
  );
  const stats = { transactions: 0 };

  return {
    documents,
    stats,
    collection(collectionPath) {
      return {
        doc(id) {
          return { id, path: `${collectionPath}/${id}` };
        },
      };
    },
    async runTransaction(callback) {
      stats.transactions += 1;
      const writes = [];
      const transaction = {
        async get(reference) {
          const data = documents.get(reference.path);
          return {
            exists: data !== undefined,
            data: () => (data === undefined ? undefined : structuredClone(data)),
          };
        },
        set(reference, data) {
          writes.push({ path: reference.path, data: structuredClone(data) });
        },
      };

      // A real transaction discards buffered writes when the callback throws.
      const result = await callback(transaction);
      for (const write of writes) {
        documents.set(write.path, write.data);
      }
      return result;
    },
  };
}
