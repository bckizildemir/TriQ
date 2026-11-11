// Statechart view for GuestUpgradeIdentity.tla: "a Guest becomes an account", in the owner's words.
// Three regions: what the person on the device is doing, who holds the username N, and what the
// Guest's profile shows.

export const title = "TriQ: a Guest becomes an account, and who holds the username";

function you(v) {
  if (v.device === "none") return "Signed out";
  if (v.device === "s") {
    if (v.su === "claim") return "Signing up, saving the username";
    if (v.su === "cleanup") return "Sign-up failed, deleting the new account";
    return "Account (signed up)";
  }
  // device === "g"
  const guest = v.gAcct === "anonymous";
  switch (v.up) {
    case "claim1":
      return "Guest, saving the username";
    case "link":
      return "Guest, name saved, linking the email";
    case "refresh":
    case "claim2":
      return "Account, finishing the upgrade";
    case "release":
      return guest ? "Guest, letting the name go" : "Account, letting the name go";
    default:
      return guest ? "Guest" : "Account (upgraded)";
  }
}

const live = (acct) => acct === "anonymous" || acct === "permanent";

// What is wrong right now, in the owner's words. Empty when nothing is.
function problems(v) {
  const out = [];
  if ((v.owner === "g" && v.gAcct === "abandoned") || (v.owner === "s" && v.sAcct === "deleted"))
    out.push("the name is stuck on an account nobody can use");
  // Away from the Guest's session, only a stuck name is shown: the Guest's own problems
  // already show on the path that led here, and repeating them multiplies the chart.
  if (v.device !== "g") return out;
  if (v.gName === "N" && live(v.gAcct) && v.owner !== "g")
    out.push("the profile shows a name it does not hold");
  if (v.up === "idle" && v.gAcct === "anonymous" && (v.owner === "g" || v.gName === "N"))
    out.push("the Guest kept the name");
  if (v.up === "idle" && v.gAcct === "permanent" && !(v.owner === "g" && v.gName === "N"))
    out.push("the upgraded account has no username");
  return out;
}

export const state = (v) => {
  const issues = problems(v);
  const phase = you(v);
  const taken = v.owner === "o" && (v.device === "g" || v.su !== "idle") ? " (name taken by someone else)" : "";
  return issues.length ? `${phase}: ${issues.join("; ")}` : phase + taken;
};

export function step(action, from, to) {
  switch (action) {
    case "GuestTapsCreateAccount":
      return to.prev === "nil"
        ? "you tap Create account; the profile read fails"
        : "you tap Create account";
    case "Claim1Taken":
      return "the name is taken";
    case "Claim1Fails":
      return "saving the name fails";
    case "Claim1Commits":
      return "the name is saved";
    case "Claim1CommitsAnswerLost":
      return "the name is saved, but the app gets an error";
    case "LinkSucceeds":
      return "the email links";
    case "LinkFails":
      return "linking the email fails";
    case "RefreshSucceeds":
      return "the sign-in token refreshes";
    case "RefreshFails":
      return "the token refresh fails";
    case "Claim2Succeeds":
      return "the name is confirmed";
    case "Claim2Fails":
      return "confirming the name fails";
    case "ReleaseLands":
      return to.gName === "N"
        ? "the name is let go, the old name is not put back"
        : "the name is let go";
    case "ReleaseFails":
      return "letting the name go fails";
    case "SignUpCreatesUser":
      return "you sign up";
    case "SignUpClaimCommits":
      return "the name is saved";
    case "SignUpClaimRefused":
      return "the name is taken, or saving it fails";
    case "SignUpClaimCommitsAnswerLost":
      return "the name is saved, but the app gets an error";
    case "SignUpCleanup":
      return "the app deletes the new account";
    case "AppKilled":
      // Hidden: from each step it lands where "saving fails" or "the name is saved, but the app
      // gets an error" already lands, and it doubles the arrows. The model still checks it.
      return null;
    case "SignOut":
      return "you sign out";
    case "SomeoneElseClaims":
      return "someone else takes the name";
    case "Done":
      return null;
  }
  return action;
}
