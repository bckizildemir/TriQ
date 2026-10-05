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

// The first username AuthModelDependencies.defaultUserData writes, one pair per app language
// (auth.placeholder.guestUser / auth.placeholder.user). firestore.rules isPlaceholderUsername holds
// the same list; firestoreRulesStatic.test.js fails when the two drift apart.
const PLACEHOLDER_USERNAMES = Object.freeze(["Guest User", "User", "Misafir Kullanıcı", "Kullanıcı"]);

function isPlaceholderUsername(username) {
  return PLACEHOLDER_USERNAMES.includes(username);
}

function normalizeUsername(username) {
  return String(username || "").trim().toLowerCase();
}

function cleanedUsername(username) {
  return String(username || "").trim();
}

function validateNormalizedUsername(normalizedUsername) {
  if (!normalizedUsername) {
    throw new HttpsError("invalid-argument", "Username is required.");
  }

  if (normalizedUsername.includes("/")) {
    throw new HttpsError("invalid-argument", "Username cannot contain '/'.");
  }

  if (normalizedUsername.length > 64) {
    throw new HttpsError("invalid-argument", "Username is too long.");
  }

  // Every new account shows a placeholder, so nobody may own one.
  if (PLACEHOLDER_USERNAMES.some((placeholder) => normalizeUsername(placeholder) === normalizedUsername)) {
    throw new HttpsError("invalid-argument", "This username is reserved.");
  }
}

// New names only: Latin letters (which covers English and Turkish), ASCII digits, single spaces,
// ".", "_" and "-". Other scripts, invisible format characters and compatibility forms are what
// let one name look like another ("аlice" with a Cyrillic а, "alice\u200B", a fullwidth "ａlice").
// Existing names are not re-checked, so resolveUsername and releaseUsername keep working for them.
const CLAIMABLE_USERNAME = /^[\p{Script=Latin}0-9._-]+(?: [\p{Script=Latin}0-9._-]+)*$/u;

function isClaimableUsername(displayUsername) {
  return displayUsername.normalize("NFKC") === displayUsername && CLAIMABLE_USERNAME.test(displayUsername);
}

function validateClaimableUsername(displayUsername) {
  if (!isClaimableUsername(displayUsername)) {
    throw new HttpsError(
      "invalid-argument",
      "Usernames may use Latin letters, digits, single spaces, '.', '_' and '-'."
    );
  }
}

async function claimUsername({
  db,
  user,
  username,
  email,
  isAnonymous,
  createServerTimestamp,
}) {
  if (!user?.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }

  const displayUsername = cleanedUsername(username);
  const normalizedUsername = normalizeUsername(displayUsername);
  validateNormalizedUsername(normalizedUsername);
  validateClaimableUsername(displayUsername);

  const now = createServerTimestamp();
  const userRef = db.collection("users").doc(user.uid);
  const usernameRef = db.collection("usernames").doc(normalizedUsername);

  await db.runTransaction(async (transaction) => {
    const [usernameSnapshot, userSnapshot] = await Promise.all([
      transaction.get(usernameRef),
      transaction.get(userRef),
    ]);

    const usernameData = usernameSnapshot.data() || {};
    if (usernameSnapshot.exists && usernameData.uid !== user.uid) {
      throw new HttpsError("already-exists", "This username is already taken.");
    }

    const userData = userSnapshot.data() || {};
    const previousNormalizedUsername =
      normalizeUsername(userData.usernameNormalized) || normalizeUsername(userData.username);

    let previousUsernameSnapshot = null;
    let previousUsernameRef = null;
    if (previousNormalizedUsername && previousNormalizedUsername !== normalizedUsername) {
      previousUsernameRef = db.collection("usernames").doc(previousNormalizedUsername);
      previousUsernameSnapshot = await transaction.get(previousUsernameRef);
    }

    if (previousUsernameSnapshot?.exists && previousUsernameSnapshot.data()?.uid === user.uid) {
      transaction.delete(previousUsernameRef);
    }

    const nextEmail = typeof email === "string" ? email.trim() : userData.email || "";
    const nextIsAnonymous =
      typeof isAnonymous === "boolean" ? isAnonymous : Boolean(userData.isAnonymous);

    transaction.set(
      usernameRef,
      {
        uid: user.uid,
        username: displayUsername,
        usernameNormalized: normalizedUsername,
        email: nextEmail,
        isAnonymous: nextIsAnonymous,
        updatedAt: now,
        createdAt: usernameSnapshot.exists
          ? usernameData.createdAt || now
          : now,
      },
      { merge: true }
    );

    transaction.set(
      userRef,
      {
        username: displayUsername,
        usernameNormalized: normalizedUsername,
        email: nextEmail,
        isAnonymous: nextIsAnonymous,
        updatedAt: now,
      },
      { merge: true }
    );
  });

  return {
    username: displayUsername,
    usernameNormalized: normalizedUsername,
  };
}

async function resolveUsername({ db, username }) {
  const normalizedUsername = normalizeUsername(username);
  validateNormalizedUsername(normalizedUsername);

  const snapshot = await db.collection("usernames").doc(normalizedUsername).get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "No user was found for this username.");
  }

  const data = snapshot.data() || {};
  if (typeof data.email !== "string" || data.email.trim().length === 0) {
    throw new HttpsError("not-found", "No email was found for this username.");
  }

  return {
    email: data.email.trim(),
  };
}

async function releaseUsername({
  db,
  user,
  username,
  restoreUsername,
  restoreEmail,
  restoreIsAnonymous,
  createServerTimestamp,
}) {
  if (!user?.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }

  const normalizedUsername = normalizeUsername(username);
  validateNormalizedUsername(normalizedUsername);

  const usernameRef = db.collection("usernames").doc(normalizedUsername);
  const userRef = db.collection("users").doc(user.uid);
  const now = createServerTimestamp();

  const cleanedRestoreUsername = cleanedUsername(restoreUsername);
  const normalizedRestoreUsername = normalizeUsername(cleanedRestoreUsername);
  // The client chooses restoreUsername, so it may only bring back a placeholder or a name that is
  // free or already the caller's. Anything else would let a caller wear another user's name.
  const restoreRef = cleanedRestoreUsername
    && !isPlaceholderUsername(cleanedRestoreUsername)
    && normalizedRestoreUsername !== normalizedUsername
    && !normalizedRestoreUsername.includes("/")
    && normalizedRestoreUsername.length <= 64
    && isClaimableUsername(cleanedRestoreUsername)
    ? db.collection("usernames").doc(normalizedRestoreUsername)
    : null;

  await db.runTransaction(async (transaction) => {
    const usernameSnapshot = await transaction.get(usernameRef);
    const restoreSnapshot = restoreRef ? await transaction.get(restoreRef) : null;
    const usernameData = usernameSnapshot.data() || {};
    if (usernameSnapshot.exists && usernameData.uid === user.uid) {
      transaction.delete(usernameRef);
    }

    const restorePatch = { updatedAt: now };
    if (cleanedRestoreUsername && isPlaceholderUsername(cleanedRestoreUsername)) {
      restorePatch.username = cleanedRestoreUsername;
      restorePatch.usernameNormalized = normalizedRestoreUsername;
    } else if (restoreSnapshot && (!restoreSnapshot.exists || restoreSnapshot.data()?.uid === user.uid)) {
      restorePatch.username = cleanedRestoreUsername;
      restorePatch.usernameNormalized = normalizedRestoreUsername;
      transaction.set(
        restoreRef,
        {
          uid: user.uid,
          username: cleanedRestoreUsername,
          usernameNormalized: normalizedRestoreUsername,
          ...(typeof restoreEmail === "string" ? { email: restoreEmail.trim() } : {}),
          ...(typeof restoreIsAnonymous === "boolean" ? { isAnonymous: restoreIsAnonymous } : {}),
          updatedAt: now,
          createdAt: restoreSnapshot.exists ? restoreSnapshot.data()?.createdAt || now : now,
        },
        { merge: true }
      );
    }

    if (typeof restoreEmail === "string") {
      restorePatch.email = restoreEmail.trim();
    }

    if (typeof restoreIsAnonymous === "boolean") {
      restorePatch.isAnonymous = restoreIsAnonymous;
    }

    transaction.set(userRef, restorePatch, { merge: true });
  });

  return { success: true };
}

module.exports = {
  PLACEHOLDER_USERNAMES,
  claimUsername,
  cleanedUsername,
  normalizeUsername,
  releaseUsername,
  resolveUsername,
};
