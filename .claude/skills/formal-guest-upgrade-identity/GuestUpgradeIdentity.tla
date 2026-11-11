---------------------------- MODULE GuestUpgradeIdentity ----------------------------
(***************************************************************************)
(* A Guest becomes a permanent account, and who holds the username.        *)
(*                                                                         *)
(* One device user, one username N, and one other person.                  *)
(*   g  the Guest's uid. AuthModel.linkAnonymousAccount keeps it (ADR 0012) *)
(*   s  the uid AuthModel.signUp makes with createUser                     *)
(*   o  someone else, on another device, who also wants N                  *)
(*                                                                         *)
(* Every action is one indivisible step in the code:                       *)
(*   - a claimUsername / releaseUsername call is one Firestore transaction *)
(*     (functions/usernameRegistry.js), so it writes usernames/N and      *)
(*     users/<uid> together or not at all;                                 *)
(*   - the client's view of that call (answer arrived, or an error) is    *)
(*     part of the same step, with the "answer lost" case modelled as the *)
(*     server committing while the client takes the catch branch;         *)
(*   - an await in AuthModel is a point where the app can be killed.       *)
(* Line numbers are TTB/Models/AuthModel.swift at the sync commit.         *)
(***************************************************************************)

VARIABLES
  device,  \* who is signed in on this device: "g", "s" or "none"
  gAcct,   \* the Guest's Firebase Auth user: "anonymous", "permanent", or
           \* "abandoned" (an anonymous user signed out: nobody can sign in to it again)
  sAcct,   \* the sign-up user: "none" (not made yet), "permanent", "deleted"
  owner,   \* usernames/N .uid: "nobody", "g", "s", "o"
  gName,   \* users/g .username: "placeholder" (Guest User / User) or "N"
  sName,   \* users/s .username: "absent" (no document), "N"
  up,      \* linkAnonymousAccount step: "idle", "claim1", "link", "refresh", "claim2", "release"
  prev,    \* previousProfile?.username read at :348 (try?): "placeholder", "N", or "nil" when the read failed
  su,      \* signUp step: "idle", "claim", "cleanup"
  oHeld    \* history: the other person has held N at some point

vars == <<device, gAcct, sAcct, owner, gName, sName, up, prev, su, oHeld>>

Live(acct) == acct \in {"anonymous", "permanent"}

Init ==
  /\ device = "g"
  /\ gAcct = "anonymous"
  /\ sAcct = "none"
  /\ owner = "nobody"
  /\ gName = "placeholder"
  /\ sName = "absent"
  /\ up = "idle"
  /\ prev = "placeholder"
  /\ su = "idle"
  /\ oHeld = FALSE

\* claimUsername transaction (usernameRegistry.js:89): N is free or already the caller's.
FreeFor(uid) == owner \in {"nobody", uid}

---------------------------------------------------------------------------
\* linkAnonymousAccount (AuthModel.swift:328), from GuestUpgradeView "Create account".

\* :345-354 profileSnapshot (try?: may come back nil), then the first claimUsername(isAnonymous: true).
\* Its success and failure are separate steps below; the tap itself only reads the profile.
GuestTapsCreateAccount ==
  /\ device = "g" /\ gAcct = "anonymous" /\ up = "idle" /\ su = "idle"
  /\ \E p \in {gName, "nil"} : prev' = p
  /\ up' = "claim1"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, owner, gName, sName, su>>

\* :350 claim 1 refused: N belongs to someone else (already-exists). Nothing written.
Claim1Taken ==
  /\ up = "claim1" /\ ~FreeFor("g")
  /\ up' = "idle"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, owner, gName, sName, prev, su>>

\* :350 claim 1 never reached the server (offline, App Check). Nothing written.
Claim1Fails ==
  /\ up = "claim1"
  /\ up' = "idle"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, owner, gName, sName, prev, su>>

\* :350 claim 1 commits and the answer arrives: go on to link.
Claim1Commits ==
  /\ up = "claim1" /\ FreeFor("g")
  /\ owner' = "g" /\ gName' = "N"
  /\ up' = "link"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, sName, prev, su>>

\* :350 claim 1 commits but the client gets an error (timeout, lost answer).
\* The throw is outside the inner do/catch, so releaseUsername is NOT called.
Claim1CommitsAnswerLost ==
  /\ up = "claim1" /\ FreeFor("g")
  /\ owner' = "g" /\ gName' = "N"
  /\ up' = "idle"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, sName, prev, su>>

\* :357 linkAccount succeeds: same uid, now permanent.
LinkSucceeds ==
  /\ up = "link"
  /\ gAcct' = "permanent"
  /\ up' = "refresh"
  /\ UNCHANGED <<oHeld, device, sAcct, owner, gName, sName, prev, su>>

\* :357 linkAccount throws (email already in use, weak password, offline).
LinkFails ==
  /\ up = "link"
  /\ up' = "release"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, owner, gName, sName, prev, su>>

\* :358 forceRefreshIDToken.
RefreshSucceeds ==
  /\ up = "refresh"
  /\ up' = "claim2"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, owner, gName, sName, prev, su>>

RefreshFails ==
  /\ up = "refresh"
  /\ up' = "release"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, owner, gName, sName, prev, su>>

\* :359 claim 2 (isAnonymous: false). Same uid, so N is still the caller's.
Claim2Succeeds ==
  /\ up = "claim2"
  /\ owner' = "g" /\ gName' = "N"
  /\ up' = "idle"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, sName, prev, su>>

\* :359 claim 2 throws (it may or may not have committed; both leave N with g).
Claim2Fails ==
  /\ up = "claim2"
  /\ up' = "release"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, owner, gName, sName, prev, su>>

\* :365 releaseUsername lands (usernameRegistry.js:173). It deletes usernames/N when g holds it.
\* It puts the old username back only when restoreUsername is a placeholder (:215); a nil
\* restoreUsername, or N itself (:199), patches no username, so users/g keeps showing N.
ReleaseLands ==
  /\ up = "release"
  /\ owner' = IF owner = "g" THEN "nobody" ELSE owner
  /\ gName' = IF prev = "placeholder" THEN "placeholder" ELSE gName
  /\ up' = "idle"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, sName, prev, su>>

\* UsernameService.releaseUsername swallows every error (best effort, :103-107).
ReleaseFails ==
  /\ up = "release"
  /\ up' = "idle"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, owner, gName, sName, prev, su>>

---------------------------------------------------------------------------
\* signUp (AuthModel.swift:247), from the sign-in screen when nobody is signed in.

\* :275 createUser: a new permanent uid, signed in on the device.
SignUpCreatesUser ==
  /\ device = "none" /\ sAcct = "none" /\ su = "idle" /\ up = "idle"
  /\ sAcct' = "permanent" /\ device' = "s"
  /\ su' = "claim"
  /\ UNCHANGED <<oHeld, gAcct, owner, gName, sName, up, prev>>

\* :277 claim succeeds: sign-up done.
SignUpClaimCommits ==
  /\ su = "claim" /\ FreeFor("s")
  /\ owner' = "s" /\ sName' = "N"
  /\ su' = "idle"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, gName, up, prev>>

\* :277 claim refused as taken, or never reached the server: :283 cleans up.
SignUpClaimRefused ==
  /\ su = "claim"
  /\ su' = "cleanup"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, owner, gName, sName, up, prev>>

\* :277 claim commits but the client gets an error: :283 cleans up anyway.
SignUpClaimCommitsAnswerLost ==
  /\ su = "claim" /\ FreeFor("s")
  /\ owner' = "s" /\ sName' = "N"
  /\ su' = "cleanup"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, gName, up, prev>>

\* :283 deletePartiallyCreatedAccount -> LiveAuthUserDocumentManager.deleteUserAndAuth:
\* deletes users/s and the Auth user. It does not touch usernames/N.
SignUpCleanup ==
  /\ su = "cleanup"
  /\ sAcct' = "deleted" /\ sName' = "absent" /\ device' = "none"
  /\ su' = "idle"
  /\ UNCHANGED <<oHeld, gAcct, owner, gName, up, prev>>

---------------------------------------------------------------------------
\* Events outside the two flows.

\* The app is killed at an await. Server state stays as it is; the flow is gone.
AppKilled ==
  /\ (up # "idle" \/ su # "idle")
  /\ up' = "idle" /\ su' = "idle"
  /\ UNCHANGED <<oHeld, device, gAcct, sAcct, owner, gName, sName, prev>>

\* ProfileModel.signOut (Auth.signOut). For a Guest the anonymous user is then out of reach.
SignOut ==
  /\ device \in {"g", "s"} /\ up = "idle" /\ su = "idle"
  /\ device' = "none"
  /\ gAcct' = IF device = "g" /\ gAcct = "anonymous" THEN "abandoned" ELSE gAcct
  /\ UNCHANGED <<oHeld, sAcct, owner, gName, sName, up, prev, su>>

\* The other person claims N (their own claimUsername transaction).
SomeoneElseClaims ==
  /\ owner = "nobody"
  /\ owner' = "o" /\ oHeld' = TRUE
  /\ UNCHANGED <<device, gAcct, sAcct, gName, sName, up, prev, su>>

Work ==
  \/ GuestTapsCreateAccount \/ Claim1Taken \/ Claim1Fails \/ Claim1Commits
  \/ Claim1CommitsAnswerLost \/ LinkSucceeds \/ LinkFails \/ RefreshSucceeds
  \/ RefreshFails \/ Claim2Succeeds \/ Claim2Fails \/ ReleaseLands \/ ReleaseFails
  \/ SignUpCreatesUser \/ SignUpClaimCommits \/ SignUpClaimRefused
  \/ SignUpClaimCommitsAnswerLost \/ SignUpCleanup
  \/ AppKilled \/ SignOut \/ SomeoneElseClaims

Done == ~ENABLED Work /\ UNCHANGED vars

Next == Work \/ Done

Spec == Init /\ [][Next]_vars

---------------------------------------------------------------------------
\* Rules.

TypeOK ==
  /\ device \in {"g", "s", "none"}
  /\ gAcct \in {"anonymous", "permanent", "abandoned"}
  /\ sAcct \in {"none", "permanent", "deleted"}
  /\ owner \in {"nobody", "g", "s", "o"}
  /\ gName \in {"placeholder", "N"}
  /\ sName \in {"absent", "N"}
  /\ up \in {"idle", "claim1", "link", "refresh", "claim2", "release"}
  /\ prev \in {"placeholder", "N", "nil"}
  /\ su \in {"idle", "claim", "cleanup"}
  /\ oHeld \in BOOLEAN

\* 1. A claimed username always belongs to an account someone can still sign in to.
\*    Broken, N is lost for good: nobody can claim it and nobody can release it.
NoOrphanAfterUpgrade == owner = "g" => Live(gAcct)
NoOrphanAfterSignUp == owner = "s" => sAcct = "permanent"

\* 0. A username is held by one account at a time, and a claim never takes it from its holder
\*    (usernameRegistry.js:96). Nothing in the model releases the other person's name, so once
\*    they hold N they keep it. Holds at the sync commit; it is the rule the proof broke.
NameStaysWithItsHolder == oHeld => owner = "o"

\* 2. A profile shows a username only while its account holds that username.
\*    Broken, someone else can claim N and two people show the same name.
ShownNameIsHeld ==
  /\ (gName = "N" /\ Live(gAcct)) => owner = "g"
  /\ (sName = "N" /\ sAcct = "permanent") => owner = "s"

\* 3. When an upgrade has ended and the Guest is still a Guest, nothing of it is left:
\*    the Guest holds no username and the profile shows the placeholder.
FailedUpgradeLeavesNoName ==
  (up = "idle" /\ gAcct = "anonymous") => (owner # "g" /\ gName = "placeholder")

\* 4. When an upgrade has ended and the account is permanent, it holds the username it chose.
UpgradedAccountKeepsItsName ==
  (up = "idle" /\ gAcct = "permanent") => (owner = "g" /\ gName = "N")

=============================================================================
