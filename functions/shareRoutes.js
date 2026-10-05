const LIST_SHARE_ROUTE_PREFIX = "/share/lists";
const LEGACY_LIST_SHARE_ROUTE_PREFIX = "/l";
const QUESTION_ROUTE_PREFIX = "/q";
const PUBLIC_HOST = "https://ttbp-9d652.web.app";

function questionIdFromPath(path) {
  const pathname = String(path).split("?")[0];
  const match = pathname.match(/\/q\/([^/]+)/);
  return match ? decodeURIComponent(match[1]) : null;
}

function listShareCodeFromPath(path) {
  const pathname = String(path).split("?")[0];
  const modernMatch = pathname.match(/\/share\/lists\/([^/]+)/);
  if (modernMatch) {
    return decodeURIComponent(modernMatch[1]);
  }

  const legacyMatch = pathname.match(/\/l\/([^/]+)/);
  return legacyMatch ? decodeURIComponent(legacyMatch[1]) : null;
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
