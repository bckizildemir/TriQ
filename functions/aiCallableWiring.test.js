const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

// firebase-functions applies enforceAppCheck inside the callable handler at runtime, not in the
// deployed endpoint manifest, so __endpoint cannot be asserted against. These tests read the
// wiring from the source instead. They exist because both guards are invisible at the call site:
// a seventh AI callable added with a bare onCall would spend money with no attestation and no
// daily quota, and every test in this suite would still pass.

const indexPath = path.join(__dirname, "index.js");

const AI_CALLABLES = [
  "askAIQuestion",
  "suggestAIAnswers",
  "suggestQuickAnswers",
  "generateQuestionPrompt",
  "generateQuestionVariations",
  "generateTrioQuestionSuggestions",
];

function readIndex() {
  return fs.readFileSync(indexPath, "utf8");
}

test("the AI callable options require App Check", () => {
  const source = readIndex().replace(/\s+/g, " ");

  assert.match(
    source,
    /const AI_FUNCTION_OPTIONS = \{ region: REGION, secrets: \[GROQ_API_KEY, OPENROUTER_API_KEY\], enforceAppCheck: true, consumeAppCheckToken: true, \}/
  );
});

test("every paid AI callable goes through the quota wrapper", () => {
  const source = readIndex();

  for (const name of AI_CALLABLES) {
    assert.match(
      source,
      new RegExp(`exports\\.${name} = aiCallable\\((AI_QUERY_GROUP|QUICK_ANSWER_GROUP),`),
      `${name} must be declared with aiCallable and a usage group`
    );
  }
});

test("no callable uses the AI options without the quota wrapper", () => {
  const source = readIndex();

  assert.match(source, /const aiCallable = \(group, handler\) =>\s*onCall\(AI_FUNCTION_OPTIONS, withSingleUseAppCheck\(withDailyQuota\(\{ db, group \}, handler\)\)\);/);

  // The wrapper itself is the one permitted use. A second one is a callable that skipped the quota.
  const directUses = source.match(/onCall\(AI_FUNCTION_OPTIONS/g) ?? [];
  assert.equal(directUses.length, 1, "AI_FUNCTION_OPTIONS may only reach onCall through aiCallable");
});

// This is the test that actually protects against "a seventh paid callable skips attestation" —
// the two above only catch a callable that copies AI_FUNCTION_OPTIONS itself, which is exactly
// what suggestAnswerImages does NOT do: it has its own inline options with its own secret.
//
// ADR-0006 ("Not claimed") once left suggestAnswerImages unattested because it spends a third-party
// (Pexels) quota rather than money. It now enforces App Check with single-use tokens, because abuse
// on our key could get the key throttled for every user. A new callable that reaches for a secret
// must either go through aiCallable or be added here with a recorded reason, not silently.
test("every callable declaring its own secret is either quota-wrapped or an explicit, reasoned exception", () => {
  const source = readIndex();

  const EXPLICIT_EXCEPTIONS = new Set([]);

  const exportPattern = /exports\.(\w+)\s*=\s*onCall\(\s*\{([^}]*)\}/g;
  const secretBearingExports = [];
  let match;
  while ((match = exportPattern.exec(source))) {
    const [, name, optionsBody] = match;
    if (/secrets\s*:/.test(optionsBody)) {
      secretBearingExports.push({ name, optionsBody });
    }
  }

  assert.ok(
    secretBearingExports.length > 0,
    "expected at least one directly-declared, secret-bearing callable to exist to scan"
  );

  for (const { name, optionsBody } of secretBearingExports) {
    if (EXPLICIT_EXCEPTIONS.has(name)) continue;

    assert.match(
      optionsBody,
      /enforceAppCheck\s*:\s*true/,
      `${name} declares a secret but not enforceAppCheck — route it through aiCallable, or add it ` +
        "to EXPLICIT_EXCEPTIONS above with a reason like the one ADR-0006 records for Pexels"
    );
  }
});

test("resolveUsername requires App Check because it returns an email before sign-in", () => {
  const source = readIndex().replace(/\s+/g, " ");

  assert.match(source, /exports\.resolveUsername = onCall\(\{ region: REGION, enforceAppCheck: true \}/);
});

test("username and list-share write callables require App Check", () => {
  const source = readIndex().replace(/\s+/g, " ");

  for (const name of [
    "claimUsername",
    "releaseUsername",
    "createQuestionListShare",
    "sendQuestionListShareReply",
  ]) {
    assert.match(
      source,
      new RegExp(`exports\\.${name} = onCall\\(\\{ region: REGION, enforceAppCheck: true \\}`),
      `${name} must keep enforceAppCheck: true`
    );
  }
});

test("the callables that spend a provider quota accept each App Check token once", () => {
  const source = readIndex().replace(/\s+/g, " ");

  assert.match(
    source,
    /exports\.suggestAnswerImages = onCall\( \{ region: REGION, secrets: \[PEXELS_API_KEY\], enforceAppCheck: true, consumeAppCheckToken: true \}, withSingleUseAppCheck\(withDailyQuota\(/
  );
});
