const { HttpsError } = require("firebase-functions/v2/https");

const MAX_DOC_ID_LENGTH = 128;

// True when value can name exactly one document in one collection. The Admin SDK reads "/" in
// doc(id) as a path separator, so an unchecked "Q/userAnswers/<uid>" from a caller would reach
// another user's document. Firestore also reserves ".", ".." and "__name__"-style ids.
function isDocId(value) {
  return typeof value === "string"
    && value.length > 0
    && value.length <= MAX_DOC_ID_LENGTH
    && !value.includes("/")
    && value !== "."
    && value !== ".."
    && !/^__.*__$/.test(value);
}

function requiredDocId(value, field) {
  const id = typeof value === "string" ? value.trim() : "";
  if (!isDocId(id)) {
    throw new HttpsError("invalid-argument", `${field} is not a valid id.`);
  }
  return id;
}

module.exports = {
  MAX_DOC_ID_LENGTH,
  isDocId,
  requiredDocId,
};
