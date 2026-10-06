const { HttpsError } = require("firebase-functions/v2/https");

// App Check alone proves a request came from our app once; a token captured from one real device
// can be replayed from a script until it expires. With consumeAppCheckToken: true on the callable,
// firebase-functions marks each token used and reports request.app.alreadyConsumed, but it does
// not reject a replay itself (enforceAppCheck only rejects a missing or invalid token). This
// wrapper does. The client must ask for limited-use tokens (HTTPSCallableOptions
// requireLimitedUseAppCheckTokens), or its second call with a cached token is refused.

/**
 * Rejects the call unless App Check reports this token as used for the first time. Anything else
 * than an explicit false (a replay, or a callable deployed without consumeAppCheckToken) fails
 * closed.
 */
function withSingleUseAppCheck(handler) {
  return async (request) => {
    if (request.app?.alreadyConsumed !== false) {
      throw new HttpsError("unauthenticated", "App Check token is not single-use.", {
        reason: "app-check-replay",
      });
    }
    return handler(request);
  };
}

module.exports = { withSingleUseAppCheck };
