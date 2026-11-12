# GuestUpgradeIdentity

TLC reached 193 states and 371 steps. The chart draws 24 states and 45 arrows.
The chart does not draw 38 steps that stay in one chart state.
The view hides 112 steps, so the chart does not draw them.

## FailedUpgradeLeavesNoName breaks
The shortest path has 2 steps:
0. Guest
1. you tap Create account: Guest, saving the username
2. the name is saved, but the app gets an error: Guest: the Guest kept the name

## NoOrphanAfterUpgrade breaks
The shortest path has 3 steps:
0. Guest
1. you tap Create account: Guest, saving the username
2. the name is saved, but the app gets an error: Guest: the Guest kept the name
3. you sign out: Signed out: the name is stuck on an account nobody can use

## ShownNameIsHeld breaks
The shortest path has 4 steps:
0. Guest
1. you tap Create account; the profile read fails: Guest, saving the username
2. the name is saved: Guest, name saved, linking the email
3. linking the email fails: Guest, letting the name go
4. the name is let go, the old name is not put back: Guest: the profile shows a name it does not hold; the Guest kept the name

## NoOrphanAfterSignUp breaks
The shortest path has 4 steps:
0. Guest
1. you sign out: Signed out
2. you sign up: Signing up, saving the username
3. the name is saved, but the app gets an error: Sign-up failed, deleting the new account
4. the app deletes the new account: Signed out: the name is stuck on an account nobody can use

## UpgradedAccountKeepsItsName breaks
The shortest path has 5 steps:
0. Guest
1. you tap Create account: Guest, saving the username
2. the name is saved: Guest, name saved, linking the email
3. the email links: Account, finishing the upgrade
4. the token refresh fails: Account, letting the name go
5. the name is let go: Account (upgraded): the upgraded account has no username

## Rules that hold
TypeOK, NameStaysWithItsHolder, NoDeadlock
