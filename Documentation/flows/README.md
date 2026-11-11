# TriQ user flows
Statecharts of the most important user flows, checked with TLA+ (TLC) and drawn with the `/statechart` skill on 2026-11-12. Each state is what the user sees; each arrow is what the user does. Every rule listed holds in the model. The models are read from the feature files of the verify skill and the code; they are not proof of the app (the verify skill is).
Make a chart again from its folder: `TLA2TOOLS=~/.local/share/tlaplus/tla2tools.jar ~/.claude/skills/statechart/scripts/statechart <Spec>.tla --config <Spec>.cfg --view view.mjs --out out`.

## First open to first answer

```mermaid
---
title: "TriQ: first open to first answer (guest)"
---
stateDiagram-v2
  state "Legend" as legend {
    lg0: Getting started
    lg1: Home
    lg2: Answering
  }
  class lg0 blue
  class lg1 teal
  class lg2 orange
  s0: Sign-in screen
  s1: Intro steps 1-4
  s2: Last intro step, button off
  s3: Last intro step, legal terms agreed
  s4: Home
  s5: Question card, empty
  s6: Question card, answers typed (up to 3)
  s7: Home with Error alert, answers rolled back
  s8: Save and Close / Close Without Saving
  [*] --> s0
  s0 --> s1: you tap Continue as Guest
  s1 --> s2: you tap Skip or you tap Continue
  s2 --> s1: you tap Back
  s2 --> s3: you tick Agree to the legal terms
  s3 --> s2: you untick the legal terms
  s3 --> s1: you tap Back
  s3 --> s4: you tap See Today's Questions
  s1 --> s3: you tap Continue or you tap Skip
  s4 --> s5: you tap a question card
  s5 --> s4: you tap Close
  s5 --> s6: you type an answer
  s6 --> s4: you tap Save, it saves
  s6 --> s7: you tap Save, the save fails
  s6 --> s8: you tap Close
  s7 --> s4: you tap OK
  s8 --> s4: you tap Close Without Saving or you tap Save and Close, it saves
  s8 --> s7: you tap Save and Close, the save fails
  class s0 blue
  class s1 blue
  class s2 blue
  class s3 blue
  class s4 teal
  class s5 orange
  class s6 orange
  class s7 teal
  class s8 orange
```

Rules and paths: [`1-first-answer/report.md`](1-first-answer/report.md).

## Guest becomes an account and leaves

```mermaid
---
title: "TriQ: guest becomes an account and leaves"
---
stateDiagram-v2
  state "Legend" as legend {
    lg0: Guest
    lg1: Signed in
    lg2: Signed out
  }
  class lg0 orange
  class lg1 teal
  class lg2 tan
  s0: Home (guest)
  s1: Profile (guest)
  s2: Create Account form
  s3: Sign-in screen
  s4: Home (signed in)
  s5: Create Account form, error shown
  s6: Profile (signed in)
  s7: Edit Profile
  s8: Delete My Account Permanently sheet
  s9: Enter your password again
  s10: You've reached 10 favorites! sheet
  [*] --> s0
  s0 --> s1: you tap Profile
  s1 --> s0: you tap Close
  s1 --> s2: you tap Save your progress
  s1 --> s3: you tap Delete Account, then Delete Guest Account
  s2 --> s4: you tap Create Account, it works
  s2 --> s1: you tap Cancel
  s2 --> s5: you tap Create Account, it fails
  s4 --> s6: you tap Profile
  s5 --> s4: you fix it and tap Create Account, it works
  s6 --> s4: you tap Close
  s6 --> s7: you tap Edit Profile
  s7 --> s6: you go back
  s7 --> s8: you tap Delete Account
  s8 --> s9: you tap Delete My Account Permanently
  s9 --> s3: you type your password and confirm
  s0 --> s10: you star a 10th question (saved) or an 11th (not saved)
  s10 --> s0: you tap Maybe Later
  s10 --> s2: you tap Create Free Account
  s2 --> s0: you tap Cancel
  class s0 orange
  class s1 orange
  class s2 orange
  class s3 tan
  class s4 teal
  class s5 orange
  class s6 teal
  class s7 teal
  class s8 teal
  class s9 teal
  class s10 orange
```

Rules and paths: [`2-guest-account/report.md`](2-guest-account/report.md).

## Write a Trio question

```mermaid
---
title: "TriQ: write a Trio question"
---
stateDiagram-v2
  state "Legend" as legend {
    lg0: Guest
    lg1: Signed in
  }
  class lg0 orange
  class lg1 teal
  s0: Home (signed in)
  s1: Home (guest)
  s2: Before You Use Trio (signed in)
  s3: Before You Use Trio (guest)
  s4: Trio feed (signed in)
  s5: Trio feed (guest)
  s6: Composer, empty, Submit off
  s7: Create Account form
  s8: Composer, ready to submit
  s9: Composer, Use at least 8 characters
  s10: Submitted for review (toast)
  s11: Composer with 3 AI ideas
  s12: Composer, submit error shown
  s13: Composer, AI idea picked
  [*] --> s0
  [*] --> s1
  s0 --> s2: you tap the Trio tab
  s1 --> s3: you tap the Trio tab
  s2 --> s4: you tap Continue
  s3 --> s5: you tap Continue
  s4 --> s6: you tap +
  s5 --> s7: you tap +
  s6 --> s4: you tap Cancel
  s6 --> s8: you type a question of 8+ characters
  s6 --> s9: you type under 8 characters
  s7 --> s5: you tap Cancel
  s8 --> s4: you tap Cancel
  s8 --> s10: you tap Submit, it works
  s8 --> s11: you tap Generate ideas
  s8 --> s12: you tap Submit, it fails
  s9 --> s8: you type a question of 8+ characters
  s10 --> s4: the toast goes away
  s11 --> s13: you tap an idea
  s12 --> s10: you tap Submit again, it works
  s13 --> s10: you tap Submit, it works
  class s0 teal
  class s1 orange
  class s2 teal
  class s3 orange
  class s4 teal
  class s5 orange
  class s6 teal
  class s7 orange
  class s8 teal
  class s9 teal
  class s10 teal
  class s11 teal
  class s12 teal
  class s13 teal
```

Rules and paths: [`3-trio-question/report.md`](3-trio-question/report.md).
