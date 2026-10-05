const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {
  publishPendingContentRelease,
} = require("./contentReleasePublisher");
const {
  sendContentReleaseNotifications,
  sendTestContentReleaseNotification,
  sendTestContentReleaseNotificationForRequest,
} = require("./contentReleaseNotifications");
const {
  claimUsername,
  releaseUsername,
  resolveUsername,
} = require("./usernameRegistry");
const {
  saveSuggestedAnswerImage,
  suggestAnswerImages,
} = require("./pexelsImageSuggestions");
const {
  addQuestionFavorites,
  saveQuestionAnswers,
  toggleQuestionFavorite,
} = require("./questionMutations");
const {
  createQuestionList,
  deleteQuestionList,
  setQuestionInList,
  updateQuestionList,
} = require("./questionLists");
const {
  acceptQuestionListShare,
  createQuestionListShare,
  disableQuestionListShare,
  leaveQuestionListShare,
  markQuestionListShareReplySeen,
  previewQuestionListShare,
  regenerateQuestionListShareLink,
  revokeQuestionListShare,
  revokeSharesForSourceList,
  sendQuestionListShareReply,
} = require("./questionListShares");
const {
  askAIQuestion,
  generateQuestionPrompt,
  generateQuestionVariations,
  generateTrioQuestionSuggestions,
  suggestAIAnswers,
  suggestQuickAnswers,
} = require("./aiProviderProxy");
const {
  AI_QUERY_GROUP,
  QUICK_ANSWER_GROUP,
  withDailyQuota,
} = require("./aiUsageLimit");
const {
  appListShareUrl,
  appQuestionUrl,
  canonicalListShareUrl,
  canonicalQuestionUrl,
  listShareCodeFromPath,
  questionIdFromPath,
} = require("./shareRoutes");
const {
  questionPreviewsForListShare,
  renderListSharePage: renderListSharePageForList,
} = require("./listSharePage");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();
const storage = admin.storage();
const REGION = "europe-west1";

// This codebase deploys 30 second-generation functions into one region. Cloud Run counts CPU
// against a per-project-per-region quota as CPU times max instances summed over every service,
// so on the default instance ceiling the project sits at the quota before a deploy starts — and
// a deploy needs headroom for the new revision alongside the old one. Capping max instances
// keeps that total well inside the quota. Raise this if real traffic ever needs it.
//
// 10 was not low enough. A service keeps its old revision's reservation until the new revision
// passes its health check, so the eleven services that never got past the first capped deploy
// still sit on the v2 default of 100 and hold roughly 1100 CPU between them. That leaves no room
// to start even one replacement, which is why retrying one function at a time also failed. At 3,
// redeploying the services that are already capped frees enough headroom for a straggler to
// start, and each straggler that lands frees about 97 more. 3 instances at the v2 default of 80
// concurrent requests each is ~240 in flight per function, still far above current traffic.
setGlobalOptions({ maxInstances: 3 });

const PEXELS_API_KEY = defineSecret("PEXELS_API_KEY");
const GROQ_API_KEY = defineSecret("GROQ_API_KEY");
const OPENROUTER_API_KEY = defineSecret("OPENROUTER_API_KEY");

// These six callables spend money per call against a paid provider, so they are the first to
// require App Check: an authenticated uid alone says nothing about which client is calling, and
// anonymous sign-in makes a uid free to obtain. Enforcement rejects any caller that does not
// attest, so a build without the App Check SDK cannot use the AI features at all. The other
// callables stay unenforced for now; their blast radius is the caller's own data.
const AI_FUNCTION_OPTIONS = {
  region: REGION,
  secrets: [GROQ_API_KEY, OPENROUTER_API_KEY],
  enforceAppCheck: true,
};

// App Check answers "is this our app". The daily quota answers "how much may this account spend".
// Both are needed: an attested copy of our app can still be driven in a loop.
const aiCallable = (group, handler) =>
  onCall(AI_FUNCTION_OPTIONS, withDailyQuota({ db, group }, handler));

exports.questionSharePage = onRequest({ region: REGION }, async (request, response) => {
  const listShareCode = listShareCodeFromPath(request.path || request.originalUrl || request.url || "");
  if (listShareCode) {
    await renderListSharePageResponse(listShareCode, response);
    return;
  }

  const questionId = questionIdFromPath(request.path || request.originalUrl || request.url || "");
  if (!questionId || questionId === "demo") {
    response.status(200).send(renderQuestionSharePage({
      title: "TTB",
      description: "Her gun uc cevaplik bir soru. TTB'de kendi trio'nu olustur.",
      questionText: "Kendini en cok hangi uc yerde evinde hissediyorsun?",
      category: "Gunluk yasam",
      questionUrl: canonicalQuestionUrl(questionId || "demo"),
      appUrl: appQuestionUrl(questionId || "demo"),
      isDemo: true,
    }));
    return;
  }

  try {
    const snapshot = await db.collection("questions").doc(questionId).get();
    if (!snapshot.exists) {
      response.status(404).send(renderQuestionSharePage({
        title: "Soru bulunamadi - TTB",
        description: "Bu TTB sorusu bulunamadi veya artik yayinda degil.",
        questionText: "Soru bulunamadi.",
        category: "TTB",
        questionUrl: canonicalQuestionUrl(questionId),
        appUrl: appQuestionUrl(questionId),
      }));
      return;
    }

    const question = snapshot.data() || {};
    if (!isShareableQuestion(question)) {
      response.status(404).send(renderQuestionSharePage({
        title: "Soru yayinda degil - TTB",
        description: "Bu soru henuz paylasima acik degil.",
        questionText: "Bu soru henuz paylasima acik degil.",
        category: "TTB",
        questionUrl: canonicalQuestionUrl(questionId),
        appUrl: appQuestionUrl(questionId),
      }));
      return;
    }

    const questionText = localizedQuestionText(question);
    response.status(200).send(renderQuestionSharePage({
      title: `${questionText} - TTB`,
      description: "Bu soruyu TTB'de uc cevapla yanitla.",
      questionText,
      category: question.category || "TTB",
      questionUrl: canonicalQuestionUrl(questionId),
      appUrl: appQuestionUrl(questionId),
    }));
  } catch (error) {
    logger.error("Failed to render question share page", { questionId, error });
    response.status(500).send(renderQuestionSharePage({
      title: "TTB",
      description: "Soru sayfasi su anda yuklenemedi.",
      questionText: "Soru sayfasi su anda yuklenemedi.",
      category: "TTB",
      questionUrl: canonicalQuestionUrl(questionId),
      appUrl: appQuestionUrl(questionId),
    }));
  }
});

exports.publishPendingContentRelease = onCall({ region: REGION }, async (request) => {
  try {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication is required.");
    }

    const isAdmin = await userIsAdmin(request.auth.uid);
    if (!isAdmin) {
      throw new HttpsError("permission-denied", "Admin privileges are required.");
    }

    return await publishPendingContentRelease({
      db,
      createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
      sendNotifications,
      logger,
      localizedTitleOverrides: request.data?.localizedTitle,
      localizedBodyOverrides: request.data?.localizedBody,
      createdBy: request.auth.uid,
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }

    logger.error("Failed to publish pending content release", serializeError(error));
    throw mapPublishError(error);
  }
});

exports.sendTestContentReleaseNotification = onCall({ region: REGION }, async (request) => {
  try {
    return await sendTestContentReleaseNotificationForRequest({
      request,
      userIsAdmin,
      HttpsError,
      sendTestNotification: ({ userId, localizedTitle, localizedBody }) =>
        sendTestContentReleaseNotification({
          db,
          messaging,
          userId,
          localizedTitle,
          localizedBody,
          logger,
        }),
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }

    logger.error("Failed to send test content release notification", serializeError(error));
    throw mapPublishError(error);
  }
});

exports.purgeOwnAnswersForAccountDeletion = onCall({ region: REGION }, async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }

  const deletedAnswerCount = await purgeOwnAnswersForAccountDeletion(request.auth.uid);
  return {
    success: true,
    deletedAnswerCount,
  };
});

exports.toggleQuestionFavorite = onCall({ region: REGION }, async (request) => {
  return toggleQuestionFavorite({
    db,
    user: { uid: request.auth?.uid },
    data: request.data,
  });
});

exports.addQuestionFavorites = onCall({ region: REGION }, async (request) => {
  return addQuestionFavorites({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
  });
});

exports.saveQuestionAnswers = onCall({ region: REGION }, async (request) => {
  return saveQuestionAnswers({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
    createTimestampFromDate: (date) => admin.firestore.Timestamp.fromDate(date),
  });
});

exports.createQuestionList = onCall({ region: REGION }, async (request) => {
  return createQuestionList({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.updateQuestionList = onCall({ region: REGION }, async (request) => {
  return updateQuestionList({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.deleteQuestionList = onCall({ region: REGION }, async (request) => {
  const result = await deleteQuestionList({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
  });
  await revokeSharesForSourceList({
    db,
    ownerId: request.auth.uid,
    sourceListId: request.data?.listId,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
  return result;
});

exports.setQuestionInList = onCall({ region: REGION }, async (request) => {
  return setQuestionInList({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.createQuestionListShare = onCall({ region: REGION }, async (request) => {
  return createQuestionListShare({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.previewQuestionListShare = onCall({ region: REGION }, async (request) => {
  return previewQuestionListShare({
    db,
    user: { uid: request.auth?.uid },
    data: request.data,
  });
});

exports.acceptQuestionListShare = onCall({ region: REGION }, async (request) => {
  return acceptQuestionListShare({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.disableQuestionListShare = onCall({ region: REGION }, async (request) => {
  return disableQuestionListShare({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.regenerateQuestionListShareLink = onCall({ region: REGION }, async (request) => {
  return regenerateQuestionListShareLink({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.revokeQuestionListShare = onCall({ region: REGION }, async (request) => {
  return revokeQuestionListShare({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.leaveQuestionListShare = onCall({ region: REGION }, async (request) => {
  return leaveQuestionListShare({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.sendQuestionListShareReply = onCall({ region: REGION }, async (request) => {
  return sendQuestionListShareReply({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.markQuestionListShareReplySeen = onCall({ region: REGION }, async (request) => {
  return markQuestionListShareReplySeen({
    db,
    user: {
      uid: request.auth?.uid,
      isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous",
    },
    data: request.data,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.suggestAnswerImages = onCall(
  { region: REGION, secrets: [PEXELS_API_KEY] },
  async (request) => {
    return suggestAnswerImages({
      user: { uid: request.auth?.uid },
      data: request.data,
      pexelsApiKey: PEXELS_API_KEY.value() || process.env.PEXELS_API_KEY,
    });
  }
);

exports.saveSuggestedAnswerImage = onCall({ region: REGION }, async (request) => {
  return saveSuggestedAnswerImage({
    user: { uid: request.auth?.uid },
    data: request.data,
    bucket: storage.bucket(),
  });
});

exports.askAIQuestion = aiCallable(AI_QUERY_GROUP, async (request) => {
  return askAIQuestion(aiFunctionContext(request));
});

exports.suggestAIAnswers = aiCallable(AI_QUERY_GROUP, async (request) => {
  return suggestAIAnswers(aiFunctionContext(request));
});

// Answer chips are asked for once per question the reader opens, and they fall back to local
// candidates when the call fails, so they get their own bucket rather than the AI query one.
exports.suggestQuickAnswers = aiCallable(QUICK_ANSWER_GROUP, async (request) => {
  return suggestQuickAnswers(aiFunctionContext(request));
});

exports.generateQuestionPrompt = aiCallable(AI_QUERY_GROUP, async (request) => {
  return generateQuestionPrompt(aiFunctionContext(request));
});

exports.generateQuestionVariations = aiCallable(AI_QUERY_GROUP, async (request) => {
  return generateQuestionVariations(aiFunctionContext(request));
});

exports.generateTrioQuestionSuggestions = aiCallable(AI_QUERY_GROUP, async (request) => {
  return generateTrioQuestionSuggestions(aiFunctionContext(request));
});

exports.claimUsername = onCall({ region: REGION }, async (request) => {
  const signInProvider = request.auth?.token?.firebase?.sign_in_provider;
  return claimUsername({
    db,
    user: { uid: request.auth?.uid },
    username: request.data?.username,
    email: request.data?.email || request.auth?.token?.email || "",
    isAnonymous: typeof request.data?.isAnonymous === "boolean"
      ? request.data.isAnonymous
      : signInProvider === "anonymous",
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

exports.resolveUsername = onCall({ region: REGION }, async (request) => {
  return resolveUsername({
    db,
    username: request.data?.username,
  });
});

exports.releaseUsername = onCall({ region: REGION }, async (request) => {
  return releaseUsername({
    db,
    user: { uid: request.auth?.uid },
    username: request.data?.username,
    restoreUsername: request.data?.restoreUsername,
    restoreEmail: request.data?.restoreEmail,
    restoreIsAnonymous: request.data?.restoreIsAnonymous,
    createServerTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  });
});

function aiFunctionContext(request) {
  return {
    user: { uid: request.auth?.uid },
    data: request.data,
    provider: process.env.AI_PROVIDER,
    model: process.env.AI_MODEL,
    groqApiKey: GROQ_API_KEY.value() || process.env.GROQ_API_KEY,
    openRouterApiKey: OPENROUTER_API_KEY.value() || process.env.OPENROUTER_API_KEY,
  };
}

async function renderListSharePageResponse(shareCode, response) {
  try {
    const snapshot = await db.collection("questionListShares")
      .where("shareCode", "==", shareCode)
      .limit(1)
      .get();
    const shareSnapshot = snapshot.docs[0];

    if (!shareSnapshot) {
      response.status(404).send(renderListSharePageForList({
        title: "Liste bulunamadi - TTB",
        description: "Bu TTB soru listesi bulunamadi veya artik paylasima acik degil.",
        listName: "Liste bulunamadi",
        ownerDisplayName: "TTB",
        questionCount: 0,
        includesAnswers: false,
        shareUrl: canonicalListShareUrl(shareCode),
        appUrl: appListShareUrl(shareCode),
      }));
      return;
    }

    const share = shareSnapshot.data() || {};
    const active = share.status === "active" && share.isLinkEnabled === true;
    if (!active) {
      response.status(404).send(renderListSharePageForList({
        title: "Liste paylasima kapali - TTB",
        description: "Bu TTB soru listesi artik yeni alicilar kabul etmiyor.",
        listName: share.listName || "TTB soru listesi",
        ownerDisplayName: share.ownerDisplayName || "TTB",
        questionCount: Array.isArray(share.questionIds) ? share.questionIds.length : 0,
        includesAnswers: share.includeOwnerAnswers === true,
        shareUrl: canonicalListShareUrl(shareCode),
        appUrl: appListShareUrl(shareCode),
      }));
      return;
    }

    const questionPreviewResult = await questionPreviewsForListShare(db, share.questionIds, 3);

    response.status(200).send(renderListSharePageForList({
      title: `${share.listName || "Soru listesi"} - TTB`,
      description: `${share.ownerDisplayName || "Bir TTB kullanicisi"} sana ${Array.isArray(share.questionIds) ? share.questionIds.length : 0} soruluk bir liste gonderdi.`,
      listName: share.listName || "TTB soru listesi",
      ownerDisplayName: share.ownerDisplayName || "TTB user",
      questionCount: Array.isArray(share.questionIds) ? share.questionIds.length : 0,
      includesAnswers: share.includeOwnerAnswers === true,
      shareUrl: canonicalListShareUrl(shareCode),
      appUrl: appListShareUrl(shareCode),
      questionPreviews: questionPreviewResult.previews,
      overflowCount: questionPreviewResult.overflowCount,
    }));
  } catch (error) {
    logger.error("Failed to render list share page", { shareCode, error });
    response.status(500).send(renderListSharePageForList({
      title: "TTB",
      description: "Liste sayfasi su anda yuklenemedi.",
      listName: "TTB soru listesi",
      ownerDisplayName: "TTB",
      questionCount: 0,
      includesAnswers: false,
      shareUrl: canonicalListShareUrl(shareCode),
      appUrl: appListShareUrl(shareCode),
    }));
  }
}

function isShareableQuestion(question) {
  const source = question.source || "seeded";
  if (source === "seeded") {
    return true;
  }

  return source === "userCreated" &&
    (!question.moderationStatus || question.moderationStatus === "approved");
}

function localizedQuestionText(question) {
  const localizedTexts = question.localizedTexts || {};
  return localizedTexts.tr || localizedTexts.en || question.text || "TTB sorusu";
}

function renderQuestionSharePage({
  title,
  description,
  questionText,
  category,
  questionUrl,
  appUrl,
  isDemo = false,
}) {
  const escapedTitle = escapeHtml(title);
  const escapedDescription = escapeHtml(description);
  const escapedQuestionText = escapeHtml(questionText);
  const escapedCategory = escapeHtml(category);
  const escapedQuestionUrl = escapeHtml(questionUrl);
  const escapedAppUrl = escapeHtml(appUrl || questionUrl);
  const appCopy = isDemo ? "Ornek paylasim sayfasi" : "Soruyu uygulamada ac";

  return `<!doctype html>
<html lang="tr">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapedTitle}</title>
    <meta name="description" content="${escapedDescription}">
    <meta property="og:title" content="${escapedTitle}">
    <meta property="og:description" content="${escapedDescription}">
    <meta property="og:type" content="article">
    <meta property="og:url" content="${escapedQuestionUrl}">
    <meta property="og:image" content="https://ttbp-9d652.web.app/assets/launch-logo.png">
    <meta name="twitter:card" content="summary">
    <meta name="theme-color" content="#F7F1E8">
    <link rel="canonical" href="${escapedQuestionUrl}">
    <link rel="icon" href="/assets/launch-logo.png">
    <style>
      :root {
        --paper: #f7f1e8;
        --ink: #202124;
        --muted: #65625d;
        --line: #ddd4c7;
        --accent: #326a5f;
        --card: #fffaf2;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        padding: 28px;
        background: var(--paper);
        color: var(--ink);
        font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        letter-spacing: 0;
      }
      main {
        width: min(680px, 100%);
      }
      .brand {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        color: inherit;
        text-decoration: none;
        font-weight: 850;
      }
      .brand img {
        width: 38px;
        height: 38px;
        border-radius: 9px;
      }
      .panel {
        margin-top: 28px;
        padding: clamp(24px, 6vw, 46px);
        border: 1px solid var(--line);
        border-radius: 8px;
        background: var(--card);
      }
      .category {
        color: var(--muted);
        font-size: 0.9rem;
        font-weight: 760;
      }
      h1 {
        margin: 18px 0 0;
        font-size: clamp(2.1rem, 8vw, 4.5rem);
        line-height: 0.98;
        letter-spacing: 0;
      }
      p {
        margin: 18px 0 0;
        color: var(--muted);
        font-size: 1.08rem;
        line-height: 1.55;
      }
      .actions {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
        margin-top: 30px;
      }
      .button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 48px;
        padding: 0 18px;
        border: 1px solid var(--accent);
        border-radius: 8px;
        background: var(--accent);
        color: white;
        text-decoration: none;
        font-weight: 800;
      }
      .button.secondary {
        border-color: var(--line);
        background: transparent;
        color: var(--ink);
      }
    </style>
  </head>
  <body>
    <main>
      <a class="brand" href="/">
        <img src="/assets/launch-logo.png" alt="">
        <span>TTB</span>
      </a>
      <section class="panel">
        <div class="category">${escapedCategory}</div>
        <h1>${escapedQuestionText}</h1>
        <p>${escapedDescription}</p>
        <div class="actions">
          <a class="button" href="${escapedAppUrl}">${escapeHtml(appCopy)}</a>
          <a class="button secondary" href="/">TTB'yi kesfet</a>
        </div>
      </section>
    </main>
  </body>
</html>`;
}

function renderListSharePage({
  title,
  description,
  listName,
  ownerDisplayName,
  questionCount,
  includesAnswers,
  shareUrl,
  appUrl,
}) {
  const escapedTitle = escapeHtml(title);
  const escapedDescription = escapeHtml(description);
  const escapedListName = escapeHtml(listName);
  const escapedOwnerDisplayName = escapeHtml(ownerDisplayName);
  const escapedShareUrl = escapeHtml(shareUrl);
  const escapedAppUrl = escapeHtml(appUrl || shareUrl);
  const answerCopy = includesAnswers ? "Gonderenin cevaplari dahil" : "Sorular bos gonderildi";

  return `<!doctype html>
<html lang="tr">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapedTitle}</title>
    <meta name="description" content="${escapedDescription}">
    <meta property="og:title" content="${escapedTitle}">
    <meta property="og:description" content="${escapedDescription}">
    <meta property="og:type" content="article">
    <meta property="og:url" content="${escapedShareUrl}">
    <meta property="og:image" content="https://ttbp-9d652.web.app/assets/launch-logo.png">
    <meta name="twitter:card" content="summary">
    <meta name="theme-color" content="#F7F1E8">
    <link rel="canonical" href="${escapedShareUrl}">
    <link rel="icon" href="/assets/launch-logo.png">
    <style>
      :root {
        --paper: #f7f1e8;
        --ink: #202124;
        --muted: #65625d;
        --line: #ddd4c7;
        --accent: #326a5f;
        --card: #fffaf2;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        padding: 28px;
        background: var(--paper);
        color: var(--ink);
        font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        letter-spacing: 0;
      }
      main { width: min(680px, 100%); }
      .brand {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        color: inherit;
        text-decoration: none;
        font-weight: 850;
      }
      .brand img {
        width: 38px;
        height: 38px;
        border-radius: 9px;
      }
      .panel {
        margin-top: 28px;
        padding: clamp(24px, 6vw, 46px);
        border: 1px solid var(--line);
        border-radius: 8px;
        background: var(--card);
      }
      .meta {
        color: var(--muted);
        font-size: 0.95rem;
        font-weight: 760;
      }
      h1 {
        margin: 18px 0 0;
        font-size: clamp(2.1rem, 8vw, 4.4rem);
        line-height: 0.98;
        letter-spacing: 0;
      }
      p {
        margin: 18px 0 0;
        color: var(--muted);
        font-size: 1.08rem;
        line-height: 1.55;
      }
      .button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 48px;
        margin-top: 30px;
        padding: 0 18px;
        border: 1px solid var(--accent);
        border-radius: 8px;
        background: var(--accent);
        color: white;
        font-weight: 760;
        text-decoration: none;
      }
    </style>
  </head>
  <body>
    <main>
      <a class="brand" href="https://ttbp-9d652.web.app/">
        <img src="/assets/launch-logo.png" alt="">
        <span>TTB</span>
      </a>
      <section class="panel">
        <div class="meta">${escapedOwnerDisplayName} · ${questionCount} soru · ${escapeHtml(answerCopy)}</div>
        <h1>${escapedListName}</h1>
        <p>Bu soru listesini TTB uygulamasinda kabul ederek yanitlayabilir ve cevaplarini geri gonderebilirsin.</p>
        <a class="button" href="${escapedAppUrl}">Uygulamada ac</a>
      </section>
    </main>
  </body>
</html>`;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

async function sendNotifications({ releaseId, localizedTitle, localizedBody }) {
  return sendContentReleaseNotifications({
    db,
    messaging,
    releaseId,
    localizedTitle,
    localizedBody,
    logger,
  });
}

function mapPublishError(error) {
  const code = error?.code;
  const message = `${error?.message || ""}`;

  if (code === 9 || code === "failed-precondition" || message.includes("requires an index")) {
    return new HttpsError(
      "failed-precondition",
      "Publish failed because a required Firestore index is not ready. Check Firebase indexes and try again."
    );
  }

  if (code === 3 || code === "invalid-argument" || message.includes("maximum 500 writes")) {
    return new HttpsError(
      "invalid-argument",
      "Publish failed because the release payload is too large. Try again after the backend update is deployed."
    );
  }

  if (code === 4 || code === "deadline-exceeded") {
    return new HttpsError(
      "deadline-exceeded",
      "Publish timed out while contacting Firebase. Check logs before retrying."
    );
  }

  if (code === 14 || code === "unavailable") {
    return new HttpsError(
      "unavailable",
      "Firebase is temporarily unavailable. Try again shortly."
    );
  }

  return new HttpsError(
    "internal",
    "Publish failed unexpectedly. Check Firebase function logs for details."
  );
}

function serializeError(error) {
  return {
    name: error?.name,
    code: error?.code,
    message: error?.message,
    stack: error?.stack,
    details: error?.details,
  };
}

async function purgeOwnAnswersForAccountDeletion(userId) {
  const snapshot = await db.collectionGroup("userAnswers")
    .where("userId", "==", userId)
    .get();

  let deletedAnswerCount = 0;

  for (const document of snapshot.docs) {
    const questionRef = document.ref.parent.parent;
    if (!questionRef) {
      continue;
    }

    await deleteAnswerImagesIfPresent(userId, questionRef.id);

    const didDelete = await deleteAnswerForAccountDeletion(questionRef, userId);
    if (didDelete) {
      deletedAnswerCount += 1;
    }
  }

  return deletedAnswerCount;
}

async function deleteAnswerImagesIfPresent(userId, questionId) {
  const bucket = storage.bucket();

  for (let slotIndex = 0; slotIndex < 3; slotIndex += 1) {
    const file = bucket.file(`answers/${userId}/${questionId}/slot_${slotIndex}.jpg`);
    await file.delete({ ignoreNotFound: true });
  }
}

async function deleteAnswerForAccountDeletion(questionRef, userId) {
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

    const questionUpdates = {
      answerStats: answerStatsForFirestore(updatedState.answerStats),
      totalRespondents: updatedState.totalRespondents,
      todayRespondents: updatedState.todayRespondents,
      todayDate: updatedState.todayDate,
      lastAnsweredAt: updatedState.lastAnsweredAt
        ? admin.firestore.Timestamp.fromDate(updatedState.lastAnsweredAt)
        : admin.firestore.FieldValue.delete(),
    };

    transaction.update(questionRef, questionUpdates);
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

function numberOrZero(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

async function userIsAdmin(userId) {
  const snapshot = await db.collection("users").doc(userId).get();
  return snapshot.exists && snapshot.get("isAdmin") === true;
}
