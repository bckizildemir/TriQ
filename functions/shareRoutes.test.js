const test = require("node:test");
const assert = require("node:assert/strict");

const {
  canonicalListShareUrl,
  listShareCodeFromPath,
} = require("./shareRoutes");

test("list share routes parse modern and legacy paths", () => {
  assert.equal(listShareCodeFromPath("/share/lists/share-code"), "share-code");
  assert.equal(listShareCodeFromPath("/l/share-code"), "share-code");
  assert.equal(listShareCodeFromPath("/share/lists/share%20code?utm=test"), "share code");
});

test("canonical list share URL uses product route", () => {
  assert.equal(
    canonicalListShareUrl("share code"),
    "https://ttbp-9d652.web.app/share/lists/share%20code"
  );
});

test("share routes return null for malformed or path-walking ids", () => {
  const { questionIdFromPath, listShareCodeFromPath } = require("./shareRoutes");

  assert.equal(questionIdFromPath("/q/%E0"), null);
  assert.equal(questionIdFromPath("/q/Q%2FuserAnswers%2Fvictim"), null);
  assert.equal(listShareCodeFromPath("/share/lists/%E0"), null);
  assert.equal(listShareCodeFromPath("/l/a%2Fb"), null);
  assert.equal(questionIdFromPath("/q/abc123"), "abc123");
});
