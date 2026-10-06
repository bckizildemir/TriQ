const test = require("node:test");
const assert = require("node:assert/strict");

const { withSingleUseAppCheck } = require("./appCheckReplay");

test("a token used for the first time reaches the handler", async () => {
  const guarded = withSingleUseAppCheck(async () => "handler ran");

  assert.equal(await guarded({ app: { appId: "app", alreadyConsumed: false } }), "handler ran");
});

test("a replayed token is rejected before the handler runs", async () => {
  let ran = false;
  const guarded = withSingleUseAppCheck(async () => {
    ran = true;
  });

  await assert.rejects(
    () => guarded({ app: { appId: "app", alreadyConsumed: true } }),
    (error) => error.code === "unauthenticated" && error.details.reason === "app-check-replay"
  );
  assert.equal(ran, false);
});

test("a request with no consume result fails closed", async () => {
  const guarded = withSingleUseAppCheck(async () => "handler ran");

  await assert.rejects(() => guarded({ app: { appId: "app" } }), (error) => error.code === "unauthenticated");
  await assert.rejects(() => guarded({}), (error) => error.code === "unauthenticated");
});
