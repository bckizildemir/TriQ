export const title = "TriQ: write a Trio question";
const who = (v) => (v.account === "guest" ? "guest" : "signed in");
export const state = (v) => {
  switch (v.screen) {
    case "home": return `Home (${who(v)})`;
    case "disclosure": return `Before You Use Trio (${who(v)})`;
    case "feed": return `Trio feed (${who(v)})`;
    case "upgrade": return "Create Account form";
    case "toast": return "Submitted for review (toast)";
    case "composer":
      if (v.err) return "Composer, submit error shown";
      if (v.draft === "empty") return "Composer, empty, Submit off";
      if (v.draft === "short") return "Composer, Use at least 8 characters";
      if (v.ideas === "shown") return "Composer with 3 AI ideas";
      if (v.ideas === "picked") return "Composer, AI idea picked";
      return "Composer, ready to submit";
  }
};
export const group = (v) => (v.account === "guest" ? "Guest" : "Signed in");
export const colors = { Guest: "orange", "Signed in": "teal" };
export const step = (a, f, t) => {
  switch (a) {
    case "OpenTrio": return "you tap the Trio tab";
    case "ContinueDisclosure": return "you tap Continue";
    case "TapPlus": return "you tap +";
    case "CancelUpgrade": return "you tap Cancel";
    case "TypeShort": return "you type under 8 characters";
    case "TypeEnough": return "you type a question of 8+ characters";
    case "GenerateIdeas": return f.err ? null : "you tap Generate ideas";
    case "PickIdea": return "you tap an idea";
    case "SubmitWorks":
      if (f.err) return "you tap Submit again, it works";
      return f.ideas === "shown" ? null : "you tap Submit, it works";
    case "SubmitFails": return f.ideas === "none" ? "you tap Submit, it fails" : null;
    case "ToastEnds": return "the toast goes away";
    case "CancelComposer": return f.draft === "empty" || (f.draft === "ok" && f.ideas === "none" && !f.err) ? "you tap Cancel" : null;
  }
};
