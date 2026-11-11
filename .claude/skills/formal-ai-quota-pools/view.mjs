// View for /statechart on chart.cfg: one caller, told from what the caller and the bill see.
const first = (o) => (o && typeof o === "object" ? Object.values(o)[0] : o);
const kinds = { anonymous: "Guest", email: "Email account (unverified)", verified: "Verified account" };

export const title = "AI quota: one caller across a UTC midnight";

export const state = (v) => {
  const calls = Object.values(first(v.call));
  const doc = first(v.uidDoc);
  const waiting = calls.filter((c) => c.phase === "stamped" || c.phase === "charged").length;
  const stale = calls.some((c) => c.phase === "stamped" && c.day < v.day);
  const paid = [1, 2].map((d) => calls.filter((c) => c.paid && c.day === d).length);
  const passed = calls.filter((c) => c.passed && c.day === v.day).length;
  // The counter is shown only when it disagrees with the calls it let through today.
  const counted = doc.dayKey === v.day ? doc.count : 0;
  const counter = doc.dayKey !== 0 && doc.dayKey !== v.day ? ` · counter still on day ${doc.dayKey}`
    : counted !== passed ? ` · counter says ${counted}` : "";
  const answers = v.day === 2 || paid[1] ? `answers day 1: ${paid[0]}, day 2: ${paid[1]}` : `answers: ${paid[0]}`;
  return [
    `Day ${v.day}`,
    `${kinds[first(v.account)]}${first(v.deleted) ? ", data deleted" : ""} · ${answers}${counter}` +
      (waiting ? ` · ${waiting} in flight${stale ? " (one sent before midnight)" : ""}` : ""),
  ];
};

export const step = (action) => ({
  SendCall: "the app asks the AI",
  QuotaTransaction: "the server checks and counts the quota",
  ProviderCall: "the AI provider answers or fails (no refund)",
  Midnight: "UTC midnight passes",
  LinkEmail: "the guest links an email",
  VerifyEmail: "the user verifies the email",
  DeleteAccountData: "the user deletes the account (token still valid)",
  Finished: null,
}[action] ?? action);

export const group = (v) => {
  const calls = Object.values(first(v.call));
  const lim = (c) => (c.anon ? 1 : 2);
  for (const d of [1, 2]) {
    const mine = calls.filter((c) => c.phase !== "idle" && c.day === d);
    const limit = mine.length === 0 ? 0 : Math.max(...mine.map(lim));
    if (mine.filter((c) => c.paid).length > limit) return "Over the daily limit";
  }
  return "Within the daily limit";
};
export const colors = { "Over the daily limit": "orange", "Within the daily limit": "blue" };
