const crypto = require("node:crypto");
const { isDocId } = require("./firestoreIds");

let HttpsError;
try {
  ({ HttpsError } = require("firebase-functions/v2/https"));
} catch {
  HttpsError = class extends Error {
    constructor(code, message) {
      super(message);
      this.code = code;
    }
  };
}

const PEXELS_SEARCH_URL = "https://api.pexels.com/v1/search";
const PEXELS_IMAGE_HOST = "images.pexels.com";
const MAX_ANSWER_LENGTH = 120;
const VALID_SLOT_INDEXES = new Set([0, 1, 2]);
const MAX_SAVED_IMAGE_BYTES = 5 * 1024 * 1024;
// storage.rules accepts only JPEG from the app, so the server keeps to raster types too.
const SAVABLE_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

async function suggestAnswerImages({
  user,
  data,
  fetchImpl = fetch,
  pexelsApiKey,
}) {
  requireAuthenticated(user);

  const slotIndex = normalizedSlotIndex(data?.slotIndex);
  const answerText = normalizedAnswerText(data?.answerText);
  const locale = normalizedLocale(data?.locale);
  const apiKey = normalizedApiKey(pexelsApiKey);

  if (!VALID_SLOT_INDEXES.has(slotIndex)) {
    throw new HttpsError("invalid-argument", "slotIndex must be 0, 1, or 2.");
  }

  if (!answerText) {
    throw new HttpsError("invalid-argument", "answerText is required.");
  }

  const query = imageSearchQuery(answerText);
  const url = new URL(PEXELS_SEARCH_URL);
  url.searchParams.set("query", query);
  url.searchParams.set("per_page", "4");
  url.searchParams.set("orientation", "square");
  url.searchParams.set("locale", locale);

  const response = await fetchImpl(url, {
    headers: {
      Authorization: apiKey,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    throw new HttpsError("unavailable", "Image search is currently unavailable.");
  }

  const payload = await response.json();
  const suggestions = Array.isArray(payload.photos)
    ? payload.photos.map(normalizePexelsPhoto).filter(Boolean).slice(0, 4)
    : [];

  return {
    query,
    slotIndex,
    suggestions,
  };
}

async function saveSuggestedAnswerImage({
  db,
  user,
  data,
  bucket,
  fetchImpl = fetch,
}) {
  requireAuthenticated(user);

  const slotIndex = normalizedSlotIndex(data?.slotIndex);
  const questionId = normalizedQuestionId(data?.questionId);
  const suggestion = normalizedSuggestion(data?.suggestion);

  if (!VALID_SLOT_INDEXES.has(slotIndex)) {
    throw new HttpsError("invalid-argument", "slotIndex must be 0, 1, or 2.");
  }

  if (!questionId) {
    throw new HttpsError("invalid-argument", "questionId is required.");
  }

  const sourceURL = new URL(suggestion.fullSizeURL);
  if (sourceURL.protocol !== "https:" || sourceURL.hostname !== PEXELS_IMAGE_HOST) {
    throw new HttpsError("invalid-argument", "Only Pexels image URLs can be saved.");
  }

  // Without this check every call could add a new file under a made-up question id, and the
  // account-deletion purge only finds files for questions the user answered.
  const questionSnapshot = await db.collection("questions").doc(questionId).get();
  if (!questionSnapshot.exists) {
    throw new HttpsError("not-found", "Question not found.");
  }

  const response = await fetchImpl(sourceURL);
  if (!response.ok) {
    throw new HttpsError("unavailable", "Selected image could not be downloaded.");
  }

  // fetch follows redirects, so the host check must also hold for where the body came from.
  if (response.url) {
    const finalURL = new URL(response.url);
    if (finalURL.protocol !== "https:" || finalURL.hostname !== PEXELS_IMAGE_HOST) {
      throw new HttpsError("invalid-argument", "Only Pexels image URLs can be saved.");
    }
  }

  const contentType = (response.headers.get("content-type") || "image/jpeg").split(";")[0].trim();
  if (!SAVABLE_IMAGE_TYPES.has(contentType)) {
    throw new HttpsError("invalid-argument", "Selected URL is not an image.");
  }

  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_SAVED_IMAGE_BYTES) {
    throw new HttpsError("invalid-argument", "Selected image size is invalid.");
  }

  const buffer = await readBodyWithLimit(response, MAX_SAVED_IMAGE_BYTES);
  if (buffer.length === 0) {
    throw new HttpsError("invalid-argument", "Selected image size is invalid.");
  }

  const storagePath = `answers/${user.uid}/${questionId}/slot_${slotIndex}.jpg`;
  const token = crypto.randomUUID();
  const file = bucket.file(storagePath);

  await file.save(buffer, {
    resumable: false,
    contentType,
    metadata: {
      cacheControl: "public, max-age=31536000",
      metadata: {
        firebaseStorageDownloadTokens: token,
        provider: "pexels",
        photoId: suggestion.photoId,
      },
    },
  });

  return {
    downloadURL: firebaseDownloadURL(bucket.name, storagePath, token),
    attribution: {
      provider: "pexels",
      photoId: suggestion.photoId,
      photographer: suggestion.photographer,
      photographerURL: suggestion.photographerURL,
      photoURL: suggestion.photoURL,
    },
  };
}

function requireAuthenticated(user) {
  if (!user?.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
}

function normalizedAnswerText(value) {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim().replace(/\s+/g, " ").slice(0, MAX_ANSWER_LENGTH);
}

function normalizedQuestionId(value) {
  if (typeof value !== "string") {
    return "";
  }
  const trimmed = value.trim();
  return isDocId(trimmed) ? trimmed : "";
}

function normalizedSlotIndex(value) {
  return Number.isInteger(value) ? value : -1;
}

function normalizedLocale(value) {
  if (typeof value !== "string") {
    return "tr-TR";
  }

  const trimmed = value.trim();
  if (/^[a-z]{2}-[A-Z]{2}$/.test(trimmed)) {
    return trimmed;
  }
  if (trimmed.toLowerCase().startsWith("en")) {
    return "en-US";
  }
  return "tr-TR";
}

function normalizedApiKey(value) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("failed-precondition", "Pexels API key is not configured.");
  }
  return value.trim();
}

function normalizedSuggestion(value) {
  if (!value || typeof value !== "object") {
    throw new HttpsError("invalid-argument", "suggestion is required.");
  }

  const suggestion = {
    photoId: stringValue(value.photoId),
    thumbnailURL: stringValue(value.thumbnailURL),
    previewURL: stringValue(value.previewURL),
    fullSizeURL: stringValue(value.fullSizeURL),
    photographer: stringValue(value.photographer),
    photographerURL: stringValue(value.photographerURL),
    photoURL: stringValue(value.photoURL),
  };

  if (!suggestion.photoId || !suggestion.fullSizeURL) {
    throw new HttpsError("invalid-argument", "suggestion is invalid.");
  }

  return suggestion;
}

function imageSearchQuery(answerText) {
  const lowered = answerText.toLocaleLowerCase("tr-TR");
  const replacements = [
    [/^kahve\s+(içmek|icmek)$/u, "kahve"],
    [/^yürüyüş\s+yapmak$/u, "yürüyüş yapan insan"],
    [/^yuruyus\s+yapmak$/u, "yürüyüş yapan insan"],
    [/^uyumak$/u, "uyuyan insan"],
  ];

  for (const [pattern, replacement] of replacements) {
    if (pattern.test(lowered)) {
      return replacement;
    }
  }

  return lowered
    .replace(/\b(yapmak|etmek|içmek|icmek)\b/gu, "")
    .replace(/\s+/g, " ")
    .trim() || lowered;
}

function normalizePexelsPhoto(photo) {
  if (!photo || typeof photo !== "object" || !photo.src) {
    return null;
  }

  const photoId = String(photo.id || "");
  const thumbnailURL = stringValue(photo.src.tiny || photo.src.small || photo.src.medium);
  const previewURL = stringValue(photo.src.medium || photo.src.large || photo.src.original);
  const fullSizeURL = stringValue(photo.src.large2x || photo.src.large || photo.src.original);

  if (!photoId || !thumbnailURL || !previewURL || !fullSizeURL) {
    return null;
  }

  return {
    id: photoId,
    photoId,
    thumbnailURL,
    previewURL,
    fullSizeURL,
    photographer: stringValue(photo.photographer),
    photographerURL: stringValue(photo.photographer_url),
    photoURL: stringValue(photo.url),
  };
}

function stringValue(value) {
  return typeof value === "string" ? value : "";
}

// Reads at most limit bytes, so a missing or false Content-Length cannot make the function hold
// an arbitrarily large body in memory.
async function readBodyWithLimit(response, limit) {
  const reader = response.body?.getReader?.();
  if (!reader) {
    const buffer = Buffer.from(await response.arrayBuffer());
    if (buffer.length > limit) {
      throw new HttpsError("invalid-argument", "Selected image size is invalid.");
    }
    return buffer;
  }

  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    total += value.byteLength;
    if (total > limit) {
      await reader.cancel();
      throw new HttpsError("invalid-argument", "Selected image size is invalid.");
    }
    chunks.push(Buffer.from(value));
  }
  return Buffer.concat(chunks);
}

function firebaseDownloadURL(bucketName, storagePath, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(storagePath)}?alt=media&token=${token}`;
}

module.exports = {
  imageSearchQuery,
  saveSuggestedAnswerImage,
  suggestAnswerImages,
};
