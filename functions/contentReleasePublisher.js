function normalizeLocalizedMap(value) {
  const source = value && typeof value === "object" ? value : {};
  const en = normalizedString(source.en)
    || normalizedString(source.tr)
    || "What's New";
  const tr = normalizedString(source.tr) || en;

  return { en, tr };
}

function mergeLocalizedCopy(suggested, overrides) {
  const normalizedSuggested = normalizeLocalizedMap(suggested);
  const normalizedOverrides = cleanedLocalizedMap(overrides);

  return normalizeLocalizedMap({
    en: normalizedOverrides.en || normalizedSuggested.en,
    tr: normalizedOverrides.tr || normalizedSuggested.tr,
  });
}

function buildSuggestedCopy({ categories, questionCount }) {
  const categoryNamesEN = categories
    .map((category) => localizedCategoryName(category, "en"))
    .filter(Boolean);
  const categoryNamesTR = categories
    .map((category) => localizedCategoryName(category, "tr"))
    .filter(Boolean);

  const categoryCount = categories.length;

  let enTitle;
  let trTitle;

  switch (true) {
  case categoryCount === 0 && questionCount > 0:
    enTitle = questionCount === 1 ? "1 new question is live" : `${questionCount} new questions are live`;
    trTitle = questionCount === 1 ? "1 yeni soru yayında" : `${questionCount} yeni soru yayında`;
    break;
  case questionCount === 0:
    enTitle = categoryCount === 1 ? "A new category is live" : `${categoryCount} new categories are live`;
    trTitle = categoryCount === 1 ? "Yeni bir kategori yayında" : `${categoryCount} yeni kategori yayında`;
    break;
  default:
    enTitle = "Fresh prompts just landed";
    trTitle = "Yeni sorular seni bekliyor";
    break;
  }

  let enBody;
  let trBody;

  if (categoryNamesEN.length > 0 && questionCount > 0) {
    enBody = `Explore ${categoryNamesEN.join(", ")} and discover ${questionCount} fresh question${questionCount === 1 ? "" : "s"}.`;
    trBody = `${categoryNamesTR.join(", ")} kategorilerinde ${questionCount} yeni soru seni bekliyor.`;
  } else if (categoryNamesEN.length > 0) {
    enBody = `Explore ${categoryNamesEN.join(", ")} in the app.`;
    trBody = `${categoryNamesTR.join(", ")} kategorilerini uygulamada keşfet.`;
  } else {
    enBody = "Open the app to see the latest curated questions.";
    trBody = "En yeni özenle seçilmiş soruları görmek için uygulamayı aç.";
  }

  return {
    title: { en: enTitle, tr: trTitle },
    body: { en: enBody, tr: trBody },
  };
}

async function publishPendingContentRelease({
  db,
  createServerTimestamp,
  sendNotifications,
  logger = console,
  localizedTitleOverrides,
  localizedBodyOverrides,
  createdBy,
}) {
  const [pendingCategories, pendingQuestions] = await Promise.all([
    fetchPendingCategories(db),
    fetchPendingSeededQuestions(db),
  ]);

  const categoryIds = pendingCategories.map((category) => category.id);
  const questionIds = pendingQuestions.map((question) => question.id);

  if (categoryIds.length === 0 && questionIds.length === 0) {
    return {
      success: true,
      didPublish: false,
      reason: "no-pending-content",
      categoryCount: 0,
      questionCount: 0,
    };
  }

  const suggestedCopy = buildSuggestedCopy({
    categories: pendingCategories,
    questionCount: questionIds.length,
  });
  const localizedTitle = mergeLocalizedCopy(suggestedCopy.title, localizedTitleOverrides);
  const localizedBody = mergeLocalizedCopy(suggestedCopy.body, localizedBodyOverrides);

  const releaseRef = db.collection("contentReleases").doc();
  const now = createServerTimestamp();
  const releasePayload = {
    localizedTitle,
    localizedBody,
    categoryIds,
    questionIds,
    status: "published",
    createdAt: now,
    updatedAt: now,
    publishedAt: now,
  };

  if (normalizedString(createdBy)) {
    releasePayload.createdBy = createdBy;
  }

  await commitReleaseWrites({
    db,
    releaseRef,
    releasePayload,
    categoryIds,
    questionIds,
    now,
  });

  let notificationStatus = "sent";
  try {
    await sendNotifications({
      releaseId: releaseRef.id,
      localizedTitle,
      localizedBody,
    });
  } catch (error) {
    notificationStatus = "failed";
    logger.warn?.("Content release published but notifications failed", {
      releaseId: releaseRef.id,
      error,
    });
  }

  return {
    success: true,
    didPublish: true,
    releaseId: releaseRef.id,
    categoryCount: categoryIds.length,
    questionCount: questionIds.length,
    notificationStatus,
  };
}

async function commitReleaseWrites({
  db,
  releaseRef,
  releasePayload,
  categoryIds,
  questionIds,
  now,
}) {
  const maxWritesPerBatch = 450;
  let batch = db.batch();
  let writeCount = 0;

  async function commitIfFull() {
    if (writeCount < maxWritesPerBatch) {
      return;
    }

    await commitCurrentBatch();
  }

  async function commitCurrentBatch() {
    if (writeCount === 0) {
      return;
    }

    await batch.commit();
    batch = db.batch();
    writeCount = 0;
  }

  async function set(documentRef, data, options) {
    batch.set(documentRef, data, options);
    writeCount += 1;
    await commitIfFull();
  }

  await set(releaseRef, releasePayload);

  for (const categoryId of categoryIds) {
    await set(
      db.collection("categories").doc(categoryId),
      {
        isAnnounced: true,
        announcedAt: now,
        announcedInReleaseId: releaseRef.id,
        updatedAt: now,
      },
      { merge: true }
    );
  }

  for (const questionId of questionIds) {
    await set(
      db.collection("questions").doc(questionId),
      {
        isAnnounced: true,
        announcedAt: now,
        announcedInReleaseId: releaseRef.id,
      },
      { merge: true }
    );
  }

  await commitCurrentBatch();
}

async function fetchPendingCategories(db) {
  const snapshot = await db.collection("categories")
    .where("isAnnounced", "==", false)
    .get();

  return snapshot.docs
    .map((document) => ({
      id: document.id,
      ...document.data(),
    }))
    .sort(sortPendingCategories);
}

async function fetchPendingSeededQuestions(db) {
  const snapshot = await db.collection("questions")
    .where("isAnnounced", "==", false)
    .where("source", "==", "seeded")
    .get();

  return snapshot.docs
    .map((document) => ({
      id: document.id,
      ...document.data(),
    }))
    .sort(sortPendingQuestions);
}

function cleanedLocalizedMap(value) {
  const source = value && typeof value === "object" ? value : {};
  const result = {};

  if (normalizedString(source.en)) {
    result.en = source.en.trim();
  }

  if (normalizedString(source.tr)) {
    result.tr = source.tr.trim();
  }

  return result;
}

function localizedCategoryName(category, language) {
  const localizedNames = category?.localizedNames && typeof category.localizedNames === "object"
    ? category.localizedNames
    : {};

  return normalizedString(localizedNames[language])
    || normalizedString(localizedNames.en)
    || normalizedString(localizedNames.tr)
    || normalizedString(category?.id)
    || "Category";
}

function sortPendingCategories(left, right) {
  const sortOrderDelta = numberOrMax(left.sortOrder) - numberOrMax(right.sortOrder);
  if (sortOrderDelta !== 0) {
    return sortOrderDelta;
  }

  const createdAtDelta = timestampToMillis(left.createdAt) - timestampToMillis(right.createdAt);
  if (createdAtDelta !== 0) {
    return createdAtDelta;
  }

  return `${left.id}`.localeCompare(`${right.id}`);
}

function sortPendingQuestions(left, right) {
  const createdAtDelta = timestampToMillis(right.createdAt) - timestampToMillis(left.createdAt);
  if (createdAtDelta !== 0) {
    return createdAtDelta;
  }

  return `${left.id}`.localeCompare(`${right.id}`);
}

function timestampToMillis(value) {
  if (value instanceof Date) {
    return value.getTime();
  }

  if (typeof value?.toMillis === "function") {
    return value.toMillis();
  }

  if (typeof value?.toDate === "function") {
    return value.toDate().getTime();
  }

  return 0;
}

function normalizedString(value) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : "";
}

function numberOrMax(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : Number.MAX_SAFE_INTEGER;
}

module.exports = {
  buildSuggestedCopy,
  mergeLocalizedCopy,
  normalizeLocalizedMap,
  publishPendingContentRelease,
};
