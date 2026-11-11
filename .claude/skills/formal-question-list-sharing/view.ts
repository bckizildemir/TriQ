// statechart view: the owner's "share a list" flow, with one recipient beside it.
// Labels are what the owner or the recipient sees; no code names.

const linkLabel = (v: any): string => {
  if (v.status === "none") return "Not shared yet";
  // Revoke runs in parts (share first, recipients after); the recipient
  // loses read access at the first part, so the chart shows one state.
  if (v.status === "revoked") return "Share revoked";
  if (!v.linkEnabled) return "Link turned off";
  return v.code === 1 ? "First link live" : "New link live";
};

const recipientLabel = (v: any): string => {
  const r = Object.keys(v.rec)[0];
  const rpc = v.rpc[r];
  const sending = rpc === "replyShareChecked" || rpc === "replyRecipientChecked";
  if (v.status === "revoked") return sending ? "recipient sending answers" : "nobody has access";
  if (rpc === "previewing" || rpc === "accepting") return "recipient joining";
  // Remove Shared List while the reply is in flight keeps this label; the
  // check's report, not the chart, shows that path.
  if (sending) return "recipient sending answers";
  if (v.rec[r] === "accepted") return "recipient on the list";
  return "no recipient";
};

export const state = (v: any) => `${linkLabel(v)}, ${recipientLabel(v)}`;

const words: Record<string, string | null> = {
  OwnerSharesList: "owner taps Share",
  OwnerSendsLink: "owner sends the link",
  OwnerDisablesLink: "owner taps Disable Link",
  OwnerRegeneratesLink: "owner taps Regenerate Link",
  OwnerRevokesShare: "owner taps Revoke Share",
  RevokeReadsRecipients: "revoke reads the recipients",
  RevokeCommitsBatch: "revoke finishes",
  RevokeStopsHalfway: "revoke stops halfway",
  OwnerOpensReply: "owner opens the reply",
  RecipientOpensLink: "recipient opens the link",
  RecipientClosesPreview: "recipient gives up",
  RecipientTapsAccept: "recipient taps Accept",
  AcceptTransaction: "server answers the accept",
  RecipientTapsSendAnswers: "recipient taps Send Answers",
  ReplyChecksRecipient: "server checks the recipient",
  ReplyWritten: "server saves the reply",
  RecipientLeaves: "recipient taps Remove Shared List",
};

// Steps the chart hides (all steps of each hidden arrow, decided from the
// chart state they leave): tapping Revoke again on a revoked share, Disable or
// Regenerate while the recipient's reply is in flight, Regenerate while the
// recipient is already on the list, and Revoke while the recipient is joining
// (the accept is then refused, which the Disable arrows already show), and the
// recipient closing the preview.
const hidden = (action: string, from: any): boolean => {
  const who = recipientLabel(from);
  if (action === "OwnerRevokesShare") return from.status === "revoked" || who === "recipient joining";
  if (action === "OwnerDisablesLink") return who === "recipient sending answers";
  if (action === "OwnerRegeneratesLink")
    return who === "recipient sending answers" || who === "recipient on the list";
  if (action === "RecipientClosesPreview") return true;
  return false;
};

export const step = (action: string, from: any, to: any) => {
  if (hidden(action, from)) return null;
  if (action === "AcceptTransaction") {
    const r = Object.keys(to.rec)[0];
    return to.rec[r] === "accepted" && from.rec[r] !== "accepted"
      ? "server lets the recipient in"
      : "server refuses the accept";
  }
  if (action === "ReplyChecksRecipient") {
    const r = Object.keys(to.rpc)[0];
    return to.rpc[r] === "idle" ? "server refuses the reply" : "server checks the recipient";
  }
  return words[action] === undefined ? action : words[action];
};

export const group = (v: any) =>
  v.status === "none" ? "start" : v.status === "active" ? "shared" : "revoked";

export const colors = { start: "tan", shared: "blue", revoked: "orange" };

export const title = "Owner shares a question list (one recipient)";
