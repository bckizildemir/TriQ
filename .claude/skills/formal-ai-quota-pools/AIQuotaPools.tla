---------------------------- MODULE AIQuotaPools ----------------------------
(***************************************************************************)
(* The server-side AI quota: the per-uid daily counter (aiUsageDaily/{uid}) *)
(* and the project-wide pools (aiUsageProjectDaily/{dayKey}), as written in *)
(* functions/aiUsageLimit.js and wired in functions/index.js (aiCallable).  *)
(* See SKILL.md in this folder for the coverage record.                    *)
(*                                                                         *)
(* One group is modelled (aiQuery); every group uses the same code path.   *)
(* Limits are scaled down: AnonLimit / PermLimit stand for DAILY_LIMITS    *)
(* anonymous / permanent (5 / 20), GuestPool / VerifiedPool for            *)
(* PROJECT_DAILY_LIMITS guest / verified (30 / 60).                        *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    FirstUid,        \* the caller under study: starts as a guest, may upgrade, verify, delete
    SecondUid,       \* another caller of any account kind, fixed for the run (pool pressure)
    FirstCalls,      \* calls in one run; a client retry is one more call
    SecondCalls,
    Days,            \* UTC days the run spans (dayKeyFor)
    AnonLimit,       \* DAILY_LIMITS[group].anonymous
    PermLimit,       \* DAILY_LIMITS[group].permanent
    GuestPool,       \* PROJECT_DAILY_LIMITS[group].guest
    VerifiedPool,    \* PROJECT_DAILY_LIMITS[group].verified
    \* Read from the code by run.sh (extract-flags.mjs):
    UidRefusesAtLimit,     \* consumeDailyQuota: `if (used >= limit)` (FALSE: `used > limit`)
    PoolRefusesAtLimit,    \* nextProjectDocument: `if (used >= limit)` (FALSE: `used > limit`)
    ChargeBeforeProvider,  \* withDailyQuota: `await consumeDailyQuota` before `return handler`
    \* Scope switches (core.cfg turns these off; AIQuotaPools.cfg keeps them on):
    WithDayRollover,       \* a UTC midnight can pass during the run
    WithAccountDeletion    \* deleteOwnAccountData can run for a uid

Days1 == 1..Days
Uids == {FirstUid, SecondUid}
Slots(u) == 1..(IF u = FirstUid THEN FirstCalls ELSE SecondCalls)
Pools == {"guest", "verified"}
\* "email" is a permanent account whose address is not verified yet.
AccountKinds == {"anonymous", "email", "verified"}

PoolLimit(p) == IF p = "guest" THEN GuestPool ELSE VerifiedPool
Refuses(used, limit, atLimit) == IF atLimit THEN used >= limit ELSE used > limit
Max(a, b) == IF a >= b THEN a ELSE b

VARIABLES
    day,          \* the server's UTC day now
    account,      \* account[u]: what the uid's ID token says (sign_in_provider, email_verified)
    call,         \* call[u][s]: one callable request, see Phases
    uidDoc,       \* aiUsageDaily/{uid}: [dayKey, count] for the group; dayKey 0 = no document
    poolDoc,      \* aiUsageProjectDaily/{dayKey}.counts["aiQuery:<pool>"]
    deleted       \* deleted[u]: deleteOwnAccountData already ran for this uid

vars == <<day, account, call, uidDoc, poolDoc, deleted>>

(* Phases of one request through aiCallable =                                *)
(*   withSingleUseAppCheck(withDailyQuota({db, group}, handler)):             *)
(*   "idle"     not sent yet                                                  *)
(*   "stamped"  App Check passed; withDailyQuota read the token's              *)
(*              sign_in_provider / email_verified (the day is read later,     *)
(*              inside the transaction)                                       *)
(*   "charged"  the quota transaction let it through; provider not called yet *)
(*   "called"   (only if the handler ran before the charge) provider called   *)
(*   "done"     the provider answered or failed (no refund), or refused       *)
(* Fields kept for the rules (the code does not store them):                  *)
(*   passed  the quota transaction let it through                             *)
(*   paid    the provider was called (money left)                             *)
(*   wrong   refused although the uid or pool had not really spent its limit *)
NoCall == [phase |-> "idle", day |-> 0, anon |-> FALSE, guest |-> FALSE,
           passed |-> FALSE, paid |-> FALSE, wrong |-> FALSE]

LimitOf(c) == IF c.anon THEN AnonLimit ELSE PermLimit
PoolOf(c) == IF c.guest THEN "guest" ELSE "verified"

\* Truth, counted from the calls (the code keeps only the documents).
CallsOf(u) == {<<u, s>> : s \in Slots(u)}
AllCalls == UNION {CallsOf(u) : u \in Uids}
C(k) == call[k[1]][k[2]]
Count(S) == Cardinality(S)
Paid(u, d) == Count({k \in CallsOf(u) : C(k).paid /\ C(k).day = d})
Passed(u, d) == Count({k \in CallsOf(u) : C(k).passed /\ C(k).day = d})
PoolPaid(d, p) == Count({k \in AllCalls : C(k).paid /\ C(k).day = d /\ PoolOf(C(k)) = p})
PoolPassed(d, p) == Count({k \in AllCalls : C(k).passed /\ C(k).day = d /\ PoolOf(C(k)) = p})
\* The highest per-uid limit u's tokens carried on day d (after an upgrade, the higher one).
DayLimit(u, d) == LET ls == {LimitOf(C(k)) : k \in {j \in CallsOf(u) : C(j).phase # "idle" /\ C(j).day = d}}
                  IN IF ls = {} THEN 0 ELSE IF PermLimit \in ls THEN PermLimit ELSE AnonLimit

Init ==
    /\ day = 1
    \* The second caller's kind matters only when it sends calls (not in the chart configs).
    /\ account \in {f \in [Uids -> AccountKinds] :
                     f[FirstUid] = "anonymous" /\ (SecondCalls = 0 => f[SecondUid] = "anonymous")}
    /\ call = [u \in Uids |-> [s \in Slots(u) |-> NoCall]]
    /\ uidDoc = [u \in Uids |-> [dayKey |-> 0, count |-> 0]]
    /\ poolDoc = [d \in Days1 |-> [p \in Pools |-> 0]]
    /\ deleted = [u \in Uids |-> FALSE]

(* withDailyQuota: the ID token claims, read once, before the transaction. The *)
(* day is NOT read here: consumeDailyQuota reads the clock inside the          *)
(* transaction (TriQ#153), so `day` of a call is set by QuotaTransaction.       *)
(* isAnonymous = sign_in_provider is "anonymous"; isGuest =        *)
(* isGuestToken (anonymous, or email_verified is not true).                    *)
SendCall(u, s) ==
    /\ call[u][s].phase = "idle"
    /\ call' = [call EXCEPT ![u][s] = [NoCall EXCEPT !.phase = "stamped",
                                       !.anon = (account[u] = "anonymous"),
                                       !.guest = (account[u] # "verified")]]
    /\ UNCHANGED <<day, account, uidDoc, poolDoc, deleted>>

(* consumeDailyQuota: one db.runTransaction that reads aiUsageDaily/{uid} and   *)
(* aiUsageProjectDaily/{dayKey}, then writes both. Firestore runs it as one     *)
(* serializable step, so it is one action here. A count stored under another   *)
(* dayKey counts as 0 (`stored?.dayKey === dayKey ? ... : {}`), and the write  *)
(* replaces the document with the dayKey read inside the transaction (`day`;   *)
(* a stored day ahead of the clock wins, which never happens here: the model   *)
(* clock only moves forward).                                                  *)
QuotaTransaction(u, s) ==
    LET c     == [call[u][s] EXCEPT !.day = day]
        used  == IF uidDoc[u].dayKey = c.day THEN uidDoc[u].count ELSE 0
        p     == PoolOf(c)
        pUsed == poolDoc[c.day][p]
        after == IF ChargeBeforeProvider THEN "charged" ELSE "done"
    IN /\ c.phase = IF ChargeBeforeProvider THEN "stamped" ELSE "called"
       /\ IF Refuses(used, LimitOf(c), UidRefusesAtLimit)
          THEN \* reason "daily-limit"
               /\ call' = [call EXCEPT ![u][s].phase = "done", ![u][s].day = day,
                                       ![u][s].wrong = (Passed(u, c.day) < LimitOf(c))]
               /\ UNCHANGED <<uidDoc, poolDoc>>
          ELSE IF Refuses(pUsed, PoolLimit(p), PoolRefusesAtLimit)
          THEN \* reason "project-daily-limit"
               /\ call' = [call EXCEPT ![u][s].phase = "done", ![u][s].day = day,
                                       ![u][s].wrong = (PoolPassed(c.day, p) < PoolLimit(p))]
               /\ UNCHANGED <<uidDoc, poolDoc>>
          ELSE /\ call' = [call EXCEPT ![u][s].phase = after, ![u][s].day = day,
                                       ![u][s].passed = TRUE]
               /\ uidDoc' = [uidDoc EXCEPT ![u] = [dayKey |-> c.day, count |-> used + 1]]
               /\ poolDoc' = [poolDoc EXCEPT ![c.day][p] = pUsed + 1]
       /\ UNCHANGED <<day, account, deleted>>

(* The handler calls the AI provider (aiProviderProxy.js). An answer and a      *)
(* failure end the same way: the attempt stays spent, nothing is refunded. A    *)
(* client retry is a new call in another slot.                                  *)
ProviderCall(u, s) ==
    /\ call[u][s].phase = IF ChargeBeforeProvider THEN "charged" ELSE "stamped"
    /\ call' = [call EXCEPT ![u][s].phase = IF ChargeBeforeProvider THEN "done" ELSE "called",
                            ![u][s].paid = TRUE]
    /\ UNCHANGED <<day, account, uidDoc, poolDoc, deleted>>

(* UTC midnight. A call not yet in its transaction takes the new day. *)
Midnight ==
    /\ WithDayRollover
    /\ day < Days
    /\ day' = day + 1
    /\ UNCHANGED <<account, call, uidDoc, poolDoc, deleted>>

(* A guest links an email: same uid, sign_in_provider is no longer anonymous,  *)
(* email_verified is false. The next token carries it.                          *)
LinkEmail(u) ==
    /\ account[u] = "anonymous"
    /\ account' = [account EXCEPT ![u] = "email"]
    /\ UNCHANGED <<day, call, uidDoc, poolDoc, deleted>>

VerifyEmail(u) ==
    /\ account[u] = "email"
    /\ account' = [account EXCEPT ![u] = "verified"]
    /\ UNCHANGED <<day, call, uidDoc, poolDoc, deleted>>

(* deleteOwnAccountData (accountDeletion.js) calls deleteAiUsageCounter, which  *)
(* deletes aiUsageDaily/{uid} unless its dayKey is today (TriQ#153), before the *)
(* Auth user. The uid can still call afterwards: onCall verifies the *)
(* ID token without checkRevoked, so a token stays good until it expires (up to *)
(* an hour), and if deleteAuthUser throws the account stays for a retry.        *)
DeleteAccountData(u) ==
    /\ WithAccountDeletion
    /\ ~deleted[u]
    /\ deleted' = [deleted EXCEPT ![u] = TRUE]
    /\ uidDoc' = [uidDoc EXCEPT ![u] = IF uidDoc[u].dayKey >= day THEN uidDoc[u]
                                                                    ELSE [dayKey |-> 0, count |-> 0]]
    /\ UNCHANGED <<day, account, call, poolDoc>>

AllDone == \A u \in Uids : \A s \in Slots(u) : call[u][s].phase = "done"
Finished == AllDone /\ UNCHANGED vars

Next ==
    \/ \E u \in Uids : \E s \in Slots(u) : SendCall(u, s)
    \/ \E u \in Uids : \E s \in Slots(u) : QuotaTransaction(u, s)
    \/ \E u \in Uids : \E s \in Slots(u) : ProviderCall(u, s)
    \/ Midnight
    \/ LinkEmail(FirstUid)
    \/ VerifyEmail(FirstUid)
    \/ DeleteAccountData(FirstUid)
    \/ Finished

Spec == Init /\ [][Next]_vars

----------------------------------------------------------------------------
(* Rules *)

\* No uid gets more provider calls on a UTC day than the per-uid limit its
\* tokens carried that day (the higher one, after a guest upgrades).
UidWithinDailyLimit ==
    \A u \in Uids, d \in Days1 : Paid(u, d) <= DayLimit(u, d)

\* No pool gets more provider calls on a UTC day than its project limit.
PoolWithinDailyLimit ==
    \A d \in Days1, p \in Pools : PoolPaid(d, p) <= PoolLimit(p)

\* A call is refused only when the uid, or its pool, really has spent the limit.
NoWrongLockout == \A u \in Uids : \A s \in Slots(u) : ~call[u][s].wrong

TypeOK ==
    /\ day \in Days1
    /\ account \in [Uids -> AccountKinds]
    /\ uidDoc \in [Uids -> [dayKey : 0..Days, count : Nat]]
=============================================================================
