const { appListShareUrl, canonicalListShareUrl } = require("./shareRoutes");

const LOGO_PATH = "/assets/launch-logo.png";
const LOGO_URL = `https://ttbp-9d652.web.app${LOGO_PATH}`;
const TESTFLIGHT_URL = "https://testflight.apple.com/join/zc6p4XqX";

async function questionPreviewsForListShare(db, questionIds, limit = 3) {
  const previews = [];
  const ids = normalizedQuestionIds(questionIds);

  for (const questionId of ids) {
    if (previews.length >= limit) {
      break;
    }

    const snapshot = await db.collection("questions").doc(questionId).get();
    if (!snapshot.exists) {
      continue;
    }

    const question = snapshot.data() || {};
    if (!isShareableQuestion(question)) {
      continue;
    }

    previews.push({
      id: questionId,
      text: localizedQuestionText(question),
      category: question.category || "TTB",
    });
  }

  return {
    previews,
    overflowCount: Math.max(0, ids.length - previews.length),
  };
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
  questionPreviews = [],
  overflowCount = 0,
}) {
  const escapedTitle = escapeHtml(title);
  const escapedDescription = escapeHtml(description);
  const escapedListName = escapeHtml(listName);
  const escapedOwnerDisplayName = escapeHtml(ownerDisplayName);
  const escapedShareUrl = escapeHtml(shareUrl);
  const escapedAppUrl = escapeHtml(appUrl || shareUrl);
  const answerCopy = includesAnswers ? "Gonderenin cevaplari kabulden sonra uygulamada gorunur" : "Sorular bos gonderildi";
  const previewMarkup = renderQuestionPreviews(questionPreviews, overflowCount);

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
    <meta property="og:image" content="${LOGO_URL}">
    <meta name="twitter:card" content="summary">
    <meta name="theme-color" content="#F7F1E8">
    <link rel="canonical" href="${escapedShareUrl}">
    <link rel="icon" href="${LOGO_PATH}">
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
      main { width: min(760px, 100%); }
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
      .preview-list {
        display: grid;
        gap: 10px;
        margin-top: 24px;
        padding: 0;
        list-style: none;
      }
      .preview {
        padding: 14px;
        border: 1px solid var(--line);
        border-radius: 8px;
        background: rgba(255, 255, 255, 0.42);
      }
      .preview-category {
        color: var(--muted);
        font-size: 0.82rem;
        font-weight: 760;
      }
      .preview-text {
        margin-top: 5px;
        color: var(--ink);
        font-size: 1rem;
        line-height: 1.4;
        font-weight: 680;
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
        font-weight: 760;
        text-decoration: none;
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
      <a class="brand" href="https://ttbp-9d652.web.app/">
        <img src="${LOGO_PATH}" alt="">
        <span>TTB</span>
      </a>
      <section class="panel">
        <div class="meta">${escapedOwnerDisplayName} · ${questionCount} soru · ${escapeHtml(answerCopy)}</div>
        <h1>${escapedListName}</h1>
        <p>Bu soru listesini TTB uygulamasinda kabul ederek yanitlayabilir ve cevaplarini geri gonderebilirsin.</p>
        ${previewMarkup}
        <div class="actions">
          <a class="button" href="${escapedAppUrl}">Uygulamada ac</a>
          <a class="button secondary" href="${TESTFLIGHT_URL}">TestFlight ile yukle</a>
        </div>
      </section>
    </main>
  </body>
</html>`;
}

function renderQuestionPreviews(questionPreviews, overflowCount) {
  const items = questionPreviews.map((preview) => {
    return `<li class="preview">
          <div class="preview-category">${escapeHtml(preview.category)}</div>
          <div class="preview-text">${escapeHtml(preview.text)}</div>
        </li>`;
  });

  if (overflowCount > 0) {
    items.push(`<li class="preview">
          <div class="preview-text">+${overflowCount} soru daha</div>
        </li>`);
  }

  return items.length > 0 ? `<ul class="preview-list">
        ${items.join("\n        ")}
        </ul>` : "";
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

function normalizedQuestionIds(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((questionId) => typeof questionId === "string")
    .map((questionId) => questionId.trim())
    .filter((questionId, index, all) => questionId.length > 0 && all.indexOf(questionId) === index)
    .slice(0, 500);
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

module.exports = {
  appListShareUrl,
  canonicalListShareUrl,
  questionPreviewsForListShare,
  renderListSharePage,
};
