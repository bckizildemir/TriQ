export const title = "TriQ: guest becomes an account and leaves";
export const state = (v) => {
  switch (v.screen) {
    case "home": return v.account === "guest" ? "Home (guest)" : "Home (signed in)";
    case "limit": return "You've reached 10 favorites! sheet";
    case "gprofile": return "Profile (guest)";
    case "upgrade": return v.upErr ? "Create Account form, error shown" : "Create Account form";
    case "aprofile": return "Profile (signed in)";
    case "edit": return "Edit Profile";
    case "deletesheet": return "Delete My Account Permanently sheet";
    case "password": return "Enter your password again";
    case "signin": return "Sign-in screen";
  }
};
export const group = (v) =>
  v.account === "guest" ? "Guest" : v.account === "account" ? "Signed in" : "Signed out";
export const colors = { Guest: "orange", "Signed in": "teal", "Signed out": "tan" };
export const step = (a, f, t) => {
  switch (a) {
    case "StarSaved": return "you tap a star";
    case "StarTenth":
    case "StarOverCap": return "you star a 10th question (saved) or an 11th (not saved)";
    case "MaybeLater": return "you tap Maybe Later";
    case "CreateFromLimit": return "you tap Create Free Account";
    case "OpenProfile": return "you tap Profile";
    case "CloseProfile": return "you tap Close";
    case "UpgradeFromProfile": return "you tap Save your progress";
    case "CancelUpgrade": return f.upErr ? null : "you tap Cancel";
    case "CreateWorks": return f.upErr ? "you fix it and tap Create Account, it works" : "you tap Create Account, it works";
    case "CreateFails": return "you tap Create Account, it fails";
    case "GuestDelete": return "you tap Delete Account, then Delete Guest Account";
    case "EditProfile": return "you tap Edit Profile";
    case "LeaveEdit": return "you go back";
    case "DeleteAccount": return "you tap Delete Account";
    case "CancelDeleteSheet": return null;
    case "DeletePermanently": return "you tap Delete My Account Permanently";
    case "CancelPassword": return null;
    case "ConfirmWithPassword": return "you type your password and confirm";
    case "Done": return "the end";
  }
};
