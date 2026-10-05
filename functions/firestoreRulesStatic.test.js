const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

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
