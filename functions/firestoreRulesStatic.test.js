const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const { PLACEHOLDER_USERNAMES } = require("./usernameRegistry");

const rulesPath = path.join(__dirname, "..", "firestore.rules");

function compact(text) {
  return text.replace(/\s+/g, " ").trim();
}

test("question list share rules restrict reads to owners and accepted recipients", () => {
  const rules = compact(fs.readFileSync(rulesPath, "utf8"));

  assert.match(rules, /match \/questionListShares\/\{shareId\}/);
  assert.match(rules, /function isShareOwner\(\)/);
  assert.match(rules, /resource\.data\.ownerId == request\.auth\.uid/);
  assert.match(rules, /function isAcceptedShareRecipient\(\)/);
  assert.match(rules, /resource\.data\.status == 'active'/);
  assert.match(rules, /get\(acceptedRecipientPath\(\)\)\.data\.status == 'accepted'/);
  assert.match(rules, /get\(acceptedRecipientPath\(\)\)\.data\.recipientId == request\.auth\.uid/);
  assert.match(rules, /allow read: if isShareOwner\(\) \|\| isAcceptedShareRecipient\(\);/);
});

test("the AI spend counter is server-owned and closed to every client", () => {
  const rules = compact(fs.readFileSync(rulesPath, "utf8"));

  assert.match(rules, /match \/aiUsageDaily\/\{userId\} \{ allow read, write: if false; \}/);
});

test("the project-wide AI spend counter is server-owned and closed to every client", () => {
  const rules = compact(fs.readFileSync(rulesPath, "utf8"));

  assert.match(rules, /match \/aiUsageProjectDaily\/\{dayKey\} \{ allow read, write: if false; \}/);
});

test("AI config is admin-only, because anonymous sign-in makes any signed-in check free", () => {
  const rules = compact(fs.readFileSync(rulesPath, "utf8"));

  assert.match(rules, /match \/aiConfig\/\{configId\} \{ allow read, write: if isAdmin\(\); \}/);
});

test("question list share rules deny all direct client writes", () => {
  const rules = compact(fs.readFileSync(rulesPath, "utf8"));

  assert.match(rules, /match \/questionListShares\/\{shareId\} .* allow create, update, delete: if false;/);
  assert.match(rules, /match \/recipients\/\{recipientId\} .* allow create, update, delete: if false;/);
});

test("question list recipient rules allow owner or self reads only", () => {
  const rules = compact(fs.readFileSync(rulesPath, "utf8"));

  assert.match(rules, /match \/recipients\/\{recipientId\}/);
  assert.match(rules, /parentShare\(\)\.data\.ownerId == request\.auth\.uid/);
  assert.match(rules, /request\.auth\.uid == recipientId/);
  assert.match(rules, /resource\.data\.recipientId == request\.auth\.uid/);
  assert.match(rules, /resource\.data\.status == 'accepted'/);
  assert.match(rules, /parentShare\(\)\.data\.status == 'active'/);
});

test("question list recipient collection group reads are limited to accepted self", () => {
  const rules = compact(fs.readFileSync(rulesPath, "utf8"));
  const collectionGroupRule = rules.match(
    /match \/\{sharePath=\*\*\}\/recipients\/\{recipientId\} \{.*?allow create, update, delete: if false; \}/
  );

  assert.ok(collectionGroupRule, "collection group recipient rule exists");
  assert.match(collectionGroupRule[0], /allow list: if isPermanentUser\(\)/);
  assert.doesNotMatch(collectionGroupRule[0], /allow read:/);
  assert.match(collectionGroupRule[0], /resource\.data\.recipientId == request\.auth\.uid/);
  assert.match(collectionGroupRule[0], /resource\.data\.status == 'accepted'/);
});

test("question list recipient collection group reads do not require document ID wildcard", () => {
  const rules = compact(fs.readFileSync(rulesPath, "utf8"));
  const collectionGroupRule = rules.match(
    /match \/\{sharePath=\*\*\}\/recipients\/\{recipientId\} \{.*?allow create, update, delete: if false; \}/
  );

  assert.ok(collectionGroupRule, "collection group recipient rule exists");
  assert.doesNotMatch(collectionGroupRule[0], /request\.auth\.uid == recipientId/);
  assert.doesNotMatch(collectionGroupRule[0], /parentShare\(\)/);
  assert.doesNotMatch(collectionGroupRule[0], /get\(/);
});

test("every localized username placeholder is accepted by the users rules", () => {
  // AuthModelDependencies.defaultUserData writes these strings as the first username, and the
  // users create rule accepts only the names in isPlaceholderUsername. A language added to the
  // app without a rules update would block every sign-up in that language.
  const rules = compact(fs.readFileSync(rulesPath, "utf8"));
  const placeholderList = rules.match(/function isPlaceholderUsername\(name\) \{ return name in \[(.*?)\]; \}/);
  assert.ok(placeholderList, "isPlaceholderUsername exists");
  const accepted = [...placeholderList[1].matchAll(/'([^']*)'/g)].map((match) => match[1]);
  // claimUsername reserves the same names, so nobody can own a name every new account shows.
  assert.deepEqual([...PLACEHOLDER_USERNAMES].sort(), [...accepted].sort());

  const catalog = JSON.parse(
    fs.readFileSync(path.join(__dirname, "..", "TTB", "Localizable.xcstrings"), "utf8")
  );
  for (const key of ["auth.placeholder.guestUser", "auth.placeholder.user"]) {
    const localizations = catalog.strings[key]?.localizations ?? {};
    assert.ok(Object.keys(localizations).length > 0, `${key} has localizations`);
    for (const [language, entry] of Object.entries(localizations)) {
      const value = entry.stringUnit.value;
      assert.ok(
        accepted.includes(value),
        `${key} (${language}) "${value}" is missing from isPlaceholderUsername in firestore.rules`
      );
    }
  }
});
