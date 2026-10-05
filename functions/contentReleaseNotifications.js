const INVALID_MESSAGING_TOKEN_ERROR_CODES = new Set([
  "messaging/invalid-registration-token",
  "messaging/registration-token-not-registered",
]);

async function sendContentReleaseNotifications({
  db,
  messaging,
  releaseId,
  localizedTitle,
  localizedBody,
  logger = console,
}) {
  const snapshot = await db.collectionGroup("notificationDevices")
    .where("isPushEligible", "==", true)
    .get();

  if (snapshot.empty) {
    return {
      attemptedCount: 0,
      successCount: 0,
      failureCount: 0,
      prunedCount: 0,
    };
  }

  return sendNotificationDocuments({
    db,
    messaging,
    documents: snapshot.docs,
    localizedTitle,
    localizedBody,
    data: { releaseId },
    logger,
  });
}

async function sendTestContentReleaseNotification({
  db,
  messaging,
  userId,
  localizedTitle,
  localizedBody,
  logger = console,
}) {
  const snapshot = await db.collection("users")
    .doc(userId)
    .collection("notificationDevices")
    .where("isPushEligible", "==", true)
    .get();

  if (snapshot.empty) {
    return emptySendResult();
  }

  return sendNotificationDocuments({
    db,
    messaging,
    documents: snapshot.docs,
    localizedTitle,
    localizedBody,
    data: {},
    logger,
  });
}

async function sendTestContentReleaseNotificationForRequest({
  request,
  userIsAdmin,
  HttpsError,
  sendTestNotification,
}) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }

  const isAdmin = await userIsAdmin(request.auth.uid);
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Admin privileges are required.");
  }

  const localizedTitle = requiredLocalizedCopy(request.data?.localizedTitle, "localizedTitle", HttpsError);
  const localizedBody = requiredLocalizedCopy(request.data?.localizedBody, "localizedBody", HttpsError);

  return {
    success: true,
    ...await sendTestNotification({
      userId: request.auth.uid,
      localizedTitle,
      localizedBody,
    }),
  };
}

async function sendNotificationDocuments({
  db,
  messaging,
  documents,
  localizedTitle,
  localizedBody,
  data = {},
  logger = console,
}) {
  const deviceBuckets = bucketNotificationDevices(documents);

  const jobs = Object.entries(deviceBuckets).flatMap(([language, devices]) => {
    return chunk(devices, 500).map(async (deviceChunk) => {
      const payload = {
        tokens: deviceChunk.map((device) => device.token),
        notification: {
          title: localizedTitle[language] || localizedTitle.en,
          body: localizedBody[language] || localizedBody.en,
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
      };

      if (Object.keys(data).length > 0) {
        payload.data = data;
      }

      const response = await messaging.sendEachForMulticast(payload);

      const prunedCount = await pruneInvalidNotificationDevices({
        db,
        devices: deviceChunk,
        responses: response.responses || [],
        logger,
      });

      return {
        attemptedCount: deviceChunk.length,
        successCount: response.successCount || 0,
        failureCount: response.failureCount || 0,
        prunedCount,
      };
    });
  });

  const results = await Promise.all(jobs);
  return results.reduce(
    (total, result) => ({
      attemptedCount: total.attemptedCount + result.attemptedCount,
      successCount: total.successCount + result.successCount,
      failureCount: total.failureCount + result.failureCount,
      prunedCount: total.prunedCount + result.prunedCount,
    }),
    emptySendResult()
  );
}

function bucketNotificationDevices(documents) {
  const deviceBuckets = {
    en: [],
    tr: [],
  };

  for (const document of documents) {
    const data = document.data() || {};
    const token = data.fcmToken;
    if (typeof token !== "string" || token.length === 0) {
      continue;
    }

    const language = languageForLocaleCode(data.localeCode);
    deviceBuckets[language].push({
      token,
      ref: document.ref,
    });
  }

  return deviceBuckets;
}

function emptySendResult() {
  return {
    attemptedCount: 0,
    successCount: 0,
    failureCount: 0,
    prunedCount: 0,
  };
}

async function pruneInvalidNotificationDevices({
  db,
  devices,
  responses,
  logger = console,
}) {
  const invalidRefs = [];

  responses.forEach((response, index) => {
    if (response?.success) {
      return;
    }

    if (isInvalidMessagingTokenError(response?.error)) {
      const ref = devices[index]?.ref;
      if (ref) {
        invalidRefs.push(ref);
      }
    }
  });

  let prunedCount = 0;
  for (const refChunk of chunk(invalidRefs, 450)) {
    const batch = db.batch();
    for (const ref of refChunk) {
      batch.delete(ref);
    }

    try {
      await batch.commit();
      prunedCount += refChunk.length;
    } catch (error) {
      logger.warn?.("Failed to prune invalid notification devices", {
        count: refChunk.length,
        error,
      });
    }
  }

  return prunedCount;
}

function isInvalidMessagingTokenError(error) {
  const code = error?.code;
  if (INVALID_MESSAGING_TOKEN_ERROR_CODES.has(code)) {
    return true;
  }

  if (code !== "messaging/invalid-argument") {
    return false;
  }

  const message = `${error?.message || ""}`.toLowerCase();
  return message.includes("registration token") || message.includes("fcm token");
}

function languageForLocaleCode(localeCode) {
  const normalizedLocale = typeof localeCode === "string" ? localeCode.toLowerCase() : "en";
  return normalizedLocale.startsWith("tr") ? "tr" : "en";
}

function requiredLocalizedCopy(value, fieldName, HttpsError) {
  if (!value || typeof value !== "object") {
    throw new HttpsError("invalid-argument", `${fieldName} is required.`);
  }

  const copy = {};
  for (const [language, text] of Object.entries(value)) {
    if (typeof text !== "string") {
      continue;
    }

    const normalizedText = text.trim();
    if (normalizedText.length > 0) {
      copy[language] = normalizedText;
    }
  }

  if (!copy.en) {
    throw new HttpsError("invalid-argument", `${fieldName}.en is required.`);
  }

  return copy;
}

function chunk(values, size) {
  const chunks = [];
  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size));
  }
  return chunks;
}

module.exports = {
  sendContentReleaseNotifications,
  sendTestContentReleaseNotification,
  sendTestContentReleaseNotificationForRequest,
  isInvalidMessagingTokenError,
  languageForLocaleCode,
};
