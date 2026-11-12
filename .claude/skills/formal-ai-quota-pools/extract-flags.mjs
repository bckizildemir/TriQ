// Reads the covered code and prints the TLA+ constants that the model takes from it.
// Exits 2 when the code no longer has a shape the model encodes: then the model needs a look
// (see "When the code changed" in SKILL.md), not a rerun.
//
// usage: node extract-flags.mjs <repo root>
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = process.argv[2];
const read = (p) => readFileSync(join(root, p), "utf8");
const limits = read("functions/aiUsageLimit.js");
const index = read("functions/index.js");
const deletion = read("functions/accountDeletion.js");
const rules = read("firestore.rules");

const problems = [];

function body(source, name) {
  const start = source.indexOf(`function ${name}(`);
  if (start < 0) {
    problems.push(`function ${name} not found in functions/aiUsageLimit.js`);
    return "";
  }
  const next = source.indexOf("\nfunction ", start + 1);
  const nextAsync = source.indexOf("\nasync function ", start + 1);
  const ends = [next, nextAsync, source.indexOf("\nmodule.exports", start)].filter((i) => i > 0);
  return source.slice(start, Math.min(...ends));
}

function comparison(text, where) {
  if (/if \(used >= limit\)/.test(text)) return "TRUE";
  if (/if \(used > limit\)/.test(text)) return "FALSE";
  problems.push(`${where}: no "if (used >= limit)" or "if (used > limit)"`);
  return "TRUE";
}

function need(text, pattern, what) {
  if (!(typeof pattern === "string" ? text.includes(pattern) : pattern.test(text))) {
    problems.push(`missing: ${what}`);
  }
}

const consume = body(limits, "consumeDailyQuota");
const project = body(limits, "nextProjectDocument");
const wrapper = body(limits, "withDailyQuota");
const guest = body(limits, "isGuestToken");

const uidRefusesAtLimit = comparison(consume, "consumeDailyQuota");
const poolRefusesAtLimit = comparison(project, "nextProjectDocument");

const charge = wrapper.indexOf("await consumeDailyQuota(");
const handler = wrapper.indexOf("handler(request)");
if (charge < 0 || handler < 0) {
  problems.push("withDailyQuota: no `await consumeDailyQuota(` or no `handler(request)`");
}
const chargeBeforeProvider = charge >= 0 && handler >= 0 && charge < handler ? "TRUE" : "FALSE";

// Shapes the model encodes as fixed. If one goes, the model may no longer describe the code.
need(consume, "db.runTransaction(", "consumeDailyQuota runs one Firestore transaction (QuotaTransaction is one step)");
need(consume, "transaction.get(reference)", "the per-uid read is inside the transaction");
need(consume, "transaction.get(projectReference)", "the pool read is inside the same transaction");
need(consume, "transaction.set(reference,", "the per-uid write is inside the transaction");
need(consume, "transaction.set(projectReference,", "the pool write is inside the same transaction");
need(consume, "const clock = readClock();", "the clock is read inside the transaction (QuotaTransaction takes the current day)");
need(consume, "const dayKey = laterKey(dayKeyFor(clock), stored?.dayKey);", "the day is the clock's, never behind the stored day");
need(consume, "stored?.dayKey === dayKey ? { ...stored.counts } : {}", "a count under another dayKey counts as 0");
need(consume, ".doc(dayKey)", "one pool document per UTC day");
if (/dayKeyFor\(now\)/.test(consume.split("db.runTransaction(")[0])) {
  problems.push("consumeDailyQuota reads the day before its transaction: the model reads it inside (TriQ#153)");
}
need(consume, "poolFor(isGuest)", "the pool comes from isGuest");
need(wrapper, "isGuest: isGuestToken(request.auth?.token)", "isGuest comes from the ID token");
need(wrapper, 'isAnonymous: request.auth?.token?.firebase?.sign_in_provider === "anonymous"', "the per-uid tier comes from sign_in_provider");
need(guest, 'token?.firebase?.sign_in_provider === "anonymous" || token?.email_verified !== true', "isGuestToken: anonymous or unverified email");
need(index, "onCall(AI_FUNCTION_OPTIONS, withSingleUseAppCheck(withDailyQuota({ db, group }, handler)))", "aiCallable wraps every AI handler in the quota");
need(deletion, "await deleteAiUsageCounter({ db, uid, now });", "account deletion calls deleteAiUsageCounter (DeleteAccountData)");
need(deletion, "storedDay >= today", "deleteAiUsageCounter keeps today's counter (DeleteAccountData)");
if (/recursiveDelete\(db\.collection\("aiUsageDaily"\)/.test(deletion)) {
  problems.push("account deletion deletes the per-uid counter outright: the model keeps today's (TriQ#153)");
}
need(rules, /match \/aiUsageDaily\/\{userId\} \{\s*allow read, write: if false;/, "firestore.rules: no client may touch aiUsageDaily (only the server moves the counter)");
need(rules, /match \/aiUsageProjectDaily\/\{dayKey\} \{\s*allow read, write: if false;/, "firestore.rules: no client may touch aiUsageProjectDaily");
if (/refund|FieldValue\.increment\(-/.test(limits)) {
  problems.push("aiUsageLimit.js mentions a refund: the model assumes none");
}

if (problems.length > 0) {
  console.error("The covered code no longer matches the model:\n  - " + problems.join("\n  - "));
  process.exit(2);
}

console.log(`UidRefusesAtLimit = ${uidRefusesAtLimit}`);
console.log(`PoolRefusesAtLimit = ${poolRefusesAtLimit}`);
console.log(`ChargeBeforeProvider = ${chargeBeforeProvider}`);
