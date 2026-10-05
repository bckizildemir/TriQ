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

  await db.runTransaction(async (transaction) => {
    const usernameSnapshot = await transaction.get(usernameRef);
    const usernameData = usernameSnapshot.data() || {};
    if (usernameSnapshot.exists && usernameData.uid === user.uid) {
      transaction.delete(usernameRef);
    }

    const restorePatch = { updatedAt: now };
    const cleanedRestoreUsername = cleanedUsername(restoreUsername);
    if (cleanedRestoreUsername) {
      restorePatch.username = cleanedRestoreUsername;
      restorePatch.usernameNormalized = normalizeUsername(cleanedRestoreUsername);
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
  claimUsername,
  cleanedUsername,
  normalizeUsername,
  releaseUsername,
  resolveUsername,
};
