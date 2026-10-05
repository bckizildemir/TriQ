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
