export const title = "TriQ: first open to first answer (guest)";
export const state = (v) => {
  switch (v.screen) {
    case "signin": return "Sign-in screen";
    case "intro":
      if (v.step < 5) return "Intro steps 1-4";
      return v.legal ? "Last intro step, legal terms agreed" : "Last intro step, button off";
    case "home": return v.saveFailed ? (v.told ? "Home with Error alert, answers rolled back" : "Home, answers lost, no message") : "Home";
    case "card": return v.typed === 0 ? "Question card, empty" : "Question card, answers typed (up to 3)";
    case "dialog": return "Save and Close / Close Without Saving";
  }
};
export const group = (v) =>
  v.screen === "signin" || v.screen === "intro" ? "Getting started" : v.screen === "home" ? "Home" : "Answering";
export const colors = { "Getting started": "blue", Home: "teal", Answering: "orange" };
export const step = (a, f, t) => {
  const dlg = f.screen === "dialog";
  switch (a) {
    case "ContinueAsGuest": return "you tap Continue as Guest";
    case "Continue": return "you tap Continue";
    case "Skip": return "you tap Skip";
    case "Back": return "you tap Back";
    case "ToggleLegal": return t.legal ? "you tick Agree to the legal terms" : "you untick the legal terms";
    case "Finish": return "you tap See Today's Questions";
    case "OpenCard": return "you tap a question card";
    case "TypeAnswer": return "you type an answer";
    case "SaveWorks": return dlg ? "you tap Save and Close, it saves" : "you tap Save, it saves";
    case "SaveFails": return dlg ? "you tap Save and Close, the save fails" : "you tap Save, the save fails";
    case "CloseEmpty": return "you tap Close";
    case "CloseWithText": return "you tap Close";
    case "CloseWithoutSaving": return "you tap Close Without Saving";
    case "DismissError": return "you tap OK";
  }
};
