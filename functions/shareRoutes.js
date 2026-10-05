const { isDocId } = require("./firestoreIds");

const LIST_SHARE_ROUTE_PREFIX = "/share/lists";
const LEGACY_LIST_SHARE_ROUTE_PREFIX = "/l";
const QUESTION_ROUTE_PREFIX = "/q";
const PUBLIC_HOST = "https://ttbp-9d652.web.app";

// A malformed escape ("%E0") makes decodeURIComponent throw, and a decoded "%2F" would turn one
// path segment into a Firestore sub-path. Either way the URL names no document.
function decodedDocIdOrNull(segment) {
  let decoded;
  try {
    decoded = decodeURIComponent(segment);
  } catch {
    return null;
  }
  return isDocId(decoded) ? decoded : null;
}

function questionIdFromPath(path) {
  const pathname = String(path).split("?")[0];
  const match = pathname.match(/\/q\/([^/]+)/);
  return match ? decodedDocIdOrNull(match[1]) : null;
}

function listShareCodeFromPath(path) {
  const pathname = String(path).split("?")[0];
  const modernMatch = pathname.match(/\/share\/lists\/([^/]+)/);
  if (modernMatch) {
    return decodedDocIdOrNull(modernMatch[1]);
  }

  const legacyMatch = pathname.match(/\/l\/([^/]+)/);
  return legacyMatch ? decodedDocIdOrNull(legacyMatch[1]) : null;
}

function canonicalQuestionUrl(questionId) {
  return `${PUBLIC_HOST}${QUESTION_ROUTE_PREFIX}/${encodeURIComponent(questionId)}`;
}

function canonicalListShareUrl(shareCode) {
  return `${PUBLIC_HOST}${LIST_SHARE_ROUTE_PREFIX}/${encodeURIComponent(shareCode)}`;
}

function appQuestionUrl(questionId) {
  return `ttbp://q/${encodeURIComponent(questionId)}`;
}

function appListShareUrl(shareCode) {
  return `ttbp://l/${encodeURIComponent(shareCode)}`;
}

module.exports = {
  appListShareUrl,
  appQuestionUrl,
  canonicalListShareUrl,
  canonicalQuestionUrl,
  listShareCodeFromPath,
  questionIdFromPath,
};
