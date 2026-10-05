const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

test("apple app site association includes question list share links", () => {
  const file = path.join(__dirname, "..", "Website", ".well-known", "apple-app-site-association");
  const association = JSON.parse(fs.readFileSync(file, "utf8"));
  const components = association.applinks.details.flatMap((detail) => detail.components);
  const paths = components.map((component) => component["/"]);

  assert.ok(paths.includes("/q/*"));
  assert.ok(paths.includes("/share/lists/*"));
  assert.ok(paths.includes("/l/*"));
});
