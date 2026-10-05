const test = require("node:test");
const assert = require("node:assert/strict");

const {
  isInvalidMessagingTokenError,
  languageForLocaleCode,
  sendContentReleaseNotifications,
  sendTestContentReleaseNotification,
  sendTestContentReleaseNotificationForRequest,
} = require("./contentReleaseNotifications");

test("languageForLocaleCode buckets Turkish locales separately from default English", () => {
  assert.equal(languageForLocaleCode("tr"), "tr");
  assert.equal(languageForLocaleCode("tr-TR"), "tr");
  assert.equal(languageForLocaleCode("en-US"), "en");
  assert.equal(languageForLocaleCode(undefined), "en");
});

test("isInvalidMessagingTokenError recognizes stale token failures only", () => {
  assert.equal(
    isInvalidMessagingTokenError({ code: "messaging/registration-token-not-registered" }),
    true
  );
  assert.equal(
    isInvalidMessagingTokenError({ code: "messaging/invalid-registration-token" }),
    true
  );
  assert.equal(
    isInvalidMessagingTokenError({
      code: "messaging/invalid-argument",
      message: "The registration token is not a valid FCM registration token",
    }),
    true
  );
  assert.equal(
    isInvalidMessagingTokenError({
      code: "messaging/invalid-argument",
      message: "The APNS payload is invalid",
    }),
    false
  );
  assert.equal(
    isInvalidMessagingTokenError({ code: "messaging/quota-exceeded" }),
    false
  );
});

test("sendContentReleaseNotifications localizes by device locale and prunes invalid tokens", async () => {
  const db = createFakeNotificationDb([
    {
      id: "en-device",
      data: {
        fcmToken: "token-en",
        localeCode: "en-US",
        isPushEligible: true,
      },
    },
    {
      id: "tr-device",
      data: {
        fcmToken: "token-tr",
        localeCode: "tr-TR",
        isPushEligible: true,
      },
    },
    {
      id: "empty-token",
      data: {
        fcmToken: "",
        localeCode: "en-US",
        isPushEligible: true,
      },
    },
  ]);
  const sentPayloads = [];
  const messaging = {
    async sendEachForMulticast(payload) {
      sentPayloads.push(payload);
      return {
        successCount: payload.tokens.includes("token-en") ? 0 : payload.tokens.length,
        failureCount: payload.tokens.includes("token-en") ? 1 : 0,
        responses: payload.tokens.map((token) => {
          if (token === "token-en") {
            return {
              success: false,
              error: { code: "messaging/registration-token-not-registered" },
            };
          }

          return { success: true };
        }),
      };
    },
  };

  const result = await sendContentReleaseNotifications({
    db,
    messaging,
    releaseId: "release-1",
    localizedTitle: {
      en: "Fresh prompts",
      tr: "Yeni sorular",
    },
    localizedBody: {
      en: "Open the app",
      tr: "Uygulamayi ac",
    },
  });

  assert.equal(result.attemptedCount, 2);
  assert.equal(result.successCount, 1);
  assert.equal(result.failureCount, 1);
  assert.equal(result.prunedCount, 1);
  assert.equal(db.deletedPaths.length, 1);
  assert.equal(db.deletedPaths[0], "users/user-1/notificationDevices/en-device");
  assert.equal(sentPayloads.length, 2);

  const englishPayload = sentPayloads.find((payload) => payload.tokens.includes("token-en"));
  const turkishPayload = sentPayloads.find((payload) => payload.tokens.includes("token-tr"));

  assert.equal(englishPayload.notification.title, "Fresh prompts");
  assert.equal(englishPayload.notification.body, "Open the app");
  assert.deepEqual(englishPayload.data, { releaseId: "release-1" });
  assert.equal(turkishPayload.notification.title, "Yeni sorular");
  assert.equal(turkishPayload.notification.body, "Uygulamayi ac");
  assert.deepEqual(turkishPayload.apns.payload.aps, { sound: "default" });
});

test("sendContentReleaseNotifications keeps retryable failures for later attempts", async () => {
  const db = createFakeNotificationDb([
    {
      id: "rate-limited-device",
      data: {
        fcmToken: "token-rate-limited",
        localeCode: "en-US",
        isPushEligible: true,
      },
    },
  ]);
  const messaging = {
    async sendEachForMulticast(payload) {
      return {
        successCount: 0,
        failureCount: payload.tokens.length,
        responses: [
          {
            success: false,
            error: { code: "messaging/quota-exceeded" },
          },
        ],
      };
    },
  };

  const result = await sendContentReleaseNotifications({
    db,
    messaging,
    releaseId: "release-1",
    localizedTitle: { en: "Fresh prompts" },
    localizedBody: { en: "Open the app" },
  });

  assert.equal(result.attemptedCount, 1);
  assert.equal(result.failureCount, 1);
  assert.equal(result.prunedCount, 0);
  assert.deepEqual(db.deletedPaths, []);
});

test("sendContentReleaseNotifications does not call messaging when no eligible tokens exist", async () => {
  const db = createFakeNotificationDb([
    {
      id: "disabled-device",
      data: {
        fcmToken: "token-disabled",
        localeCode: "en-US",
        isPushEligible: false,
      },
    },
    {
      id: "empty-token",
      data: {
        fcmToken: "",
        localeCode: "tr-TR",
        isPushEligible: true,
      },
    },
  ]);
  let sendCount = 0;
  const messaging = {
    async sendEachForMulticast() {
      sendCount += 1;
      throw new Error("messaging should not be called");
    },
  };

  const result = await sendContentReleaseNotifications({
    db,
    messaging,
    releaseId: "release-1",
    localizedTitle: { en: "Fresh prompts" },
    localizedBody: { en: "Open the app" },
  });

  assert.deepEqual(result, {
    attemptedCount: 0,
    successCount: 0,
    failureCount: 0,
    prunedCount: 0,
  });
  assert.equal(sendCount, 0);
});

test("sendContentReleaseNotifications chunks multicast sends at Firebase token limits", async () => {
  const devices = Array.from({ length: 501 }, (_, index) => ({
    id: `device-${index}`,
    data: {
      fcmToken: `token-${index}`,
      localeCode: "en-US",
      isPushEligible: true,
    },
  }));
  const db = createFakeNotificationDb(devices);
  const chunkSizes = [];
  const messaging = {
    async sendEachForMulticast(payload) {
      chunkSizes.push(payload.tokens.length);
      return {
        successCount: payload.tokens.length,
        failureCount: 0,
        responses: payload.tokens.map(() => ({ success: true })),
      };
    },
  };

  const result = await sendContentReleaseNotifications({
    db,
    messaging,
    releaseId: "release-1",
    localizedTitle: { en: "Fresh prompts" },
    localizedBody: { en: "Open the app" },
  });

  assert.deepEqual(chunkSizes, [500, 1]);
  assert.equal(result.attemptedCount, 501);
  assert.equal(result.successCount, 501);
  assert.equal(result.failureCount, 0);
  assert.equal(result.prunedCount, 0);
});

test("sendContentReleaseNotifications falls back to English copy when localized copy is missing", async () => {
  const db = createFakeNotificationDb([
    {
      id: "tr-device",
      data: {
        fcmToken: "token-tr",
        localeCode: "tr-TR",
        isPushEligible: true,
      },
    },
  ]);
  let sentPayload;
  const messaging = {
    async sendEachForMulticast(payload) {
      sentPayload = payload;
      return {
        successCount: 1,
        failureCount: 0,
        responses: [{ success: true }],
      };
    },
  };

  await sendContentReleaseNotifications({
    db,
    messaging,
    releaseId: "release-1",
    localizedTitle: { en: "Fresh prompts" },
    localizedBody: { en: "Open the app" },
  });

  assert.equal(sentPayload.notification.title, "Fresh prompts");
  assert.equal(sentPayload.notification.body, "Open the app");
});

test("sendContentReleaseNotifications does not over-report pruned devices when prune commit fails", async () => {
  const db = createFakeNotificationDb([
    {
      id: "invalid-device",
      data: {
        fcmToken: "token-invalid",
        localeCode: "en-US",
        isPushEligible: true,
      },
    },
  ], { failBatchCommit: true });
  const messaging = {
    async sendEachForMulticast(payload) {
      return {
        successCount: 0,
        failureCount: payload.tokens.length,
        responses: [
          {
            success: false,
            error: { code: "messaging/registration-token-not-registered" },
          },
        ],
      };
    },
  };

  const result = await sendContentReleaseNotifications({
    db,
    messaging,
    releaseId: "release-1",
    localizedTitle: { en: "Fresh prompts" },
    localizedBody: { en: "Open the app" },
    logger: { warn: () => {} },
  });

  assert.equal(result.attemptedCount, 1);
  assert.equal(result.failureCount, 1);
  assert.equal(result.prunedCount, 0);
  assert.deepEqual(db.deletedPaths, []);
});

test("sendTestContentReleaseNotification sends only current admin eligible devices", async () => {
  const db = createFakeNotificationDb([
    {
      id: "admin-enabled",
      userId: "admin-1",
      data: {
        fcmToken: "token-admin-enabled",
        localeCode: "en-US",
        isPushEligible: true,
      },
    },
    {
      id: "admin-disabled",
      userId: "admin-1",
      data: {
        fcmToken: "token-admin-disabled",
        localeCode: "en-US",
        isPushEligible: false,
      },
    },
    {
      id: "other-user",
      userId: "user-2",
      data: {
        fcmToken: "token-other-user",
        localeCode: "en-US",
        isPushEligible: true,
      },
    },
  ]);
  const sentPayloads = [];
  const messaging = {
    async sendEachForMulticast(payload) {
      sentPayloads.push(payload);
      return {
        successCount: payload.tokens.length,
        failureCount: 0,
        responses: payload.tokens.map(() => ({ success: true })),
      };
    },
  };

  const result = await sendTestContentReleaseNotification({
    db,
    messaging,
    userId: "admin-1",
    localizedTitle: { en: "Test notification" },
    localizedBody: { en: "This goes only to you." },
  });

  assert.equal(result.attemptedCount, 1);
  assert.equal(result.successCount, 1);
  assert.equal(sentPayloads.length, 1);
  assert.deepEqual(sentPayloads[0].tokens, ["token-admin-enabled"]);
  assert.equal(sentPayloads[0].data, undefined);
});

test("sendTestContentReleaseNotification reports no eligible device without messaging call", async () => {
  const db = createFakeNotificationDb([
    {
      id: "admin-empty-token",
      userId: "admin-1",
      data: {
        fcmToken: "",
        localeCode: "en-US",
        isPushEligible: true,
      },
    },
    {
      id: "admin-disabled",
      userId: "admin-1",
      data: {
        fcmToken: "token-admin-disabled",
        localeCode: "en-US",
        isPushEligible: false,
      },
    },
  ]);
  let sendCount = 0;
  const messaging = {
    async sendEachForMulticast() {
      sendCount += 1;
      throw new Error("messaging should not be called");
    },
  };

  const result = await sendTestContentReleaseNotification({
    db,
    messaging,
    userId: "admin-1",
    localizedTitle: { en: "Test notification" },
    localizedBody: { en: "This goes only to you." },
  });

  assert.deepEqual(result, {
    attemptedCount: 0,
    successCount: 0,
    failureCount: 0,
    prunedCount: 0,
  });
  assert.equal(sendCount, 0);
});

test("sendTestContentReleaseNotification prunes invalid current-admin device tokens", async () => {
  const db = createFakeNotificationDb([
    {
      id: "admin-invalid",
      userId: "admin-1",
      data: {
        fcmToken: "token-admin-invalid",
        localeCode: "en-US",
        isPushEligible: true,
      },
    },
  ]);
  const messaging = {
    async sendEachForMulticast(payload) {
      return {
        successCount: 0,
        failureCount: payload.tokens.length,
        responses: [
          {
            success: false,
            error: { code: "messaging/registration-token-not-registered" },
          },
        ],
      };
    },
  };

  const result = await sendTestContentReleaseNotification({
    db,
    messaging,
    userId: "admin-1",
    localizedTitle: { en: "Test notification" },
    localizedBody: { en: "This goes only to you." },
  });

  assert.equal(result.attemptedCount, 1);
  assert.equal(result.failureCount, 1);
  assert.equal(result.prunedCount, 1);
  assert.deepEqual(db.deletedPaths, ["users/admin-1/notificationDevices/admin-invalid"]);
});

test("sendTestContentReleaseNotificationForRequest rejects unauthenticated callers", async () => {
  await assert.rejects(
    () => sendTestContentReleaseNotificationForRequest({
      request: { data: {} },
      userIsAdmin: async () => true,
      HttpsError: FakeHttpsError,
      sendTestNotification: async () => ({}),
    }),
    (error) => error.code === "unauthenticated"
  );
});

test("sendTestContentReleaseNotificationForRequest rejects non-admin callers", async () => {
  await assert.rejects(
    () => sendTestContentReleaseNotificationForRequest({
      request: {
        auth: { uid: "user-1" },
        data: {
          localizedTitle: { en: "Test" },
          localizedBody: { en: "Body" },
        },
      },
      userIsAdmin: async () => false,
      HttpsError: FakeHttpsError,
      sendTestNotification: async () => ({}),
    }),
    (error) => error.code === "permission-denied"
  );
});

test("sendTestContentReleaseNotificationForRequest validates English title and body", async () => {
  await assert.rejects(
    () => sendTestContentReleaseNotificationForRequest({
      request: {
        auth: { uid: "admin-1" },
        data: {
          localizedTitle: { tr: "Test" },
          localizedBody: { en: "Body" },
        },
      },
      userIsAdmin: async () => true,
      HttpsError: FakeHttpsError,
      sendTestNotification: async () => ({}),
    }),
    (error) => error.code === "invalid-argument"
  );
});

test("sendTestContentReleaseNotificationForRequest sends normalized copy as admin self-test", async () => {
  let receivedPayload;
  const result = await sendTestContentReleaseNotificationForRequest({
    request: {
      auth: { uid: "admin-1" },
      data: {
        localizedTitle: { en: " Test title ", tr: " Deneme " },
        localizedBody: { en: " Test body ", tr: "" },
      },
    },
    userIsAdmin: async (uid) => uid === "admin-1",
    HttpsError: FakeHttpsError,
    sendTestNotification: async (payload) => {
      receivedPayload = payload;
      return {
        attemptedCount: 1,
        successCount: 1,
        failureCount: 0,
        prunedCount: 0,
      };
    },
  });

  assert.deepEqual(receivedPayload, {
    userId: "admin-1",
    localizedTitle: { en: "Test title", tr: "Deneme" },
    localizedBody: { en: "Test body" },
  });
  assert.deepEqual(result, {
    success: true,
    attemptedCount: 1,
    successCount: 1,
    failureCount: 0,
    prunedCount: 0,
  });
});

class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function createFakeNotificationDb(devices, options = {}) {
  const fakeDb = {
    deletedPaths: [],
    collection(collectionName) {
      assert.equal(collectionName, "users");
      return {
        doc(userId) {
          return {
            collection(childCollectionName) {
              assert.equal(childCollectionName, "notificationDevices");
              return {
                where(field, operator, value) {
                  assert.equal(field, "isPushEligible");
                  assert.equal(operator, "==");
                  assert.equal(value, true);
                  return {
                    async get() {
                      const docs = devices
                        .filter((device) => (device.userId || "user-1") === userId)
                        .filter((device) => device.data.isPushEligible === true)
                        .map((device) => ({
                          data: () => ({ ...device.data }),
                          ref: {
                            path: `users/${userId}/notificationDevices/${device.id}`,
                          },
                        }));

                      return {
                        empty: docs.length === 0,
                        docs,
                      };
                    },
                  };
                },
              };
            },
          };
        },
      };
    },
    collectionGroup(collectionName) {
      assert.equal(collectionName, "notificationDevices");
      return {
        where(field, operator, value) {
          assert.equal(field, "isPushEligible");
          assert.equal(operator, "==");
          assert.equal(value, true);
          return {
            async get() {
              const docs = devices
                .filter((device) => device.data.isPushEligible === true)
                .map((device) => ({
                  data: () => ({ ...device.data }),
                  ref: {
                    path: `users/user-1/notificationDevices/${device.id}`,
                  },
                }));

              return {
                empty: docs.length === 0,
                docs,
              };
            },
          };
        },
      };
    },
    batch() {
      const refs = [];
      return {
        delete(ref) {
          refs.push(ref);
        },
        async commit() {
          if (options.failBatchCommit) {
            throw new Error("commit failed");
          }
          fakeDb.deletedPaths.push(...refs.map((ref) => ref.path));
        },
      };
    },
  };

  return fakeDb;
}
