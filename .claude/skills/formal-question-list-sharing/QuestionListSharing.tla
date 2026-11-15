---------------------------- MODULE QuestionListSharing ----------------------------
(***************************************************************************)
(* Question list sharing, server side: one owner, one Shared Question List,*)
(* a few Recipients, and the owner's link actions interleaved with the     *)
(* recipients' preview / accept / reply / leave calls.                     *)
(*                                                                         *)
(* Every action is one indivisible step of the real code. A callable that  *)
(* runs one Firestore transaction is one action. A callable that awaits    *)
(* several separate reads and writes is several actions, one per write or *)
(* per read whose result decides a later write. Line numbers point into    *)
(* functions/questionListShares.js (QLS) and firestore.rules (RULES) at    *)
(* the sync commit named in SKILL.md.                                      *)
(*                                                                         *)
(* Names come from GLOSSARY.md (the repo glossary) and the code:            *)
(*   status        questionListShares/{id}.status   "none" = not created   *)
(*   linkEnabled   questionListShares/{id}.isLinkEnabled                   *)
(*   code          questionListShares/{id}.shareCode, numbered 1, 2, ...   *)
(*   rec[r]        recipients/{r}.status   "none" = no document            *)
(*   unread[r]     recipients/{r}.unreadByOwner                            *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
  Recipients,   \* permanent-account users who may get a share link
  MaxCode,      \* bound: create gives code 1, each regenerate adds one
  Cap           \* recipientCap (QLS:6 DEFAULT_RECIPIENT_CAP = 25; small here)

VARIABLES
  status, linkEnabled, code,
  rec, held, via, rpc, unread,
  revokeStep, revokeTargets,
  \* ghost variables: they record history for the rules, the code has no such field
  everRevoked, admittedThroughReplacedLink, admittedThroughDisabledLink, replyAfterExit

vars == <<status, linkEnabled, code, rec, held, via, rpc, unread,
          revokeStep, revokeTargets,
          everRevoked, admittedThroughReplacedLink, admittedThroughDisabledLink, replyAfterExit>>

RecipientStatus == {"none", "accepted", "left", "revoked"}
RecipientSteps  == {"idle", "previewing", "accepting", "replyShareChecked", "replyRecipientChecked"}

TypeOK ==
  /\ status \in {"none", "active", "revoked"}
  /\ linkEnabled \in BOOLEAN
  /\ code \in 0..MaxCode
  /\ rec \in [Recipients -> RecipientStatus]
  /\ held \in [Recipients -> 0..MaxCode]
  /\ via \in [Recipients -> 0..MaxCode]
  /\ rpc \in [Recipients -> RecipientSteps]
  /\ unread \in [Recipients -> BOOLEAN]
  /\ revokeStep \in {"idle", "shareMarked", "recipientsRead"}
  /\ revokeTargets \subseteq Recipients

Init ==
  /\ status = "none"
  /\ linkEnabled = FALSE
  /\ code = 0
  /\ rec = [r \in Recipients |-> "none"]
  /\ held = [r \in Recipients |-> 0]
  /\ via = [r \in Recipients |-> 0]
  /\ rpc = [r \in Recipients |-> "idle"]
  /\ unread = [r \in Recipients |-> FALSE]
  /\ revokeStep = "idle"
  /\ revokeTargets = {}
  /\ everRevoked = FALSE
  /\ admittedThroughReplacedLink = {}
  /\ admittedThroughDisabledLink = {}
  /\ replyAfterExit = {}

\* QLS:453 shareIsClaimable
Claimable == status = "active" /\ linkEnabled

AcceptedCount == Cardinality({r \in Recipients : rec[r] = "accepted"})

\* RULES:306-314 isAcceptedShareRecipient: what lets a recipient read the share
\* document, which holds the list snapshot and the owner's answer snapshot.
CanReadShare(r) == status = "active" /\ rec[r] = "accepted"

ghosts == <<everRevoked, admittedThroughReplacedLink, admittedThroughDisabledLink, replyAfterExit>>

-----------------------------------------------------------------------------
(* Owner steps. The owner's app awaits each callable, so the owner runs one *)
(* at a time; revokeStep holds the owner between the parts of a revoke.   *)

\* createQuestionListShare, QLS:9-52: one set() of the new share document.
OwnerSharesList ==
  /\ status = "none"
  /\ status' = "active" /\ linkEnabled' = TRUE /\ code' = 1
  /\ UNCHANGED <<rec, held, via, rpc, unread, revokeStep, revokeTargets, ghosts>>

\* The owner sends the current link to r (system share sheet). r keeps the
\* link it got; a later regenerate does not change what r holds.
OwnerSendsLink(r) ==
  /\ status = "active" /\ linkEnabled /\ held[r] # code
  /\ held' = [held EXCEPT ![r] = code]
  /\ UNCHANGED <<status, linkEnabled, code, rec, via, rpc, unread, revokeStep, revokeTargets, ghosts>>

\* disableQuestionListShare, QLS:180-187: one transaction.
OwnerDisablesLink ==
  /\ revokeStep = "idle" /\ status # "none" /\ linkEnabled
  /\ linkEnabled' = FALSE
  /\ UNCHANGED <<status, code, rec, held, via, rpc, unread, revokeStep, revokeTargets, ghosts>>

\* regenerateQuestionListShareLink, QLS:206-216: one transaction. It checks
\* ownership only, not status, and turns the link back on.
OwnerRegeneratesLink ==
  /\ revokeStep = "idle" /\ status # "none" /\ code < MaxCode
  /\ code' = code + 1 /\ linkEnabled' = TRUE
  /\ UNCHANGED <<status, rec, held, via, rpc, unread, revokeStep, revokeTargets, ghosts>>

\* revokeQuestionListShare -> revokeShareRef, QLS:367-395: NOT one
\* transaction. Part 1, QLS:374-382: get + update of the share document.
OwnerRevokesShare ==
  /\ revokeStep = "idle" /\ status # "none"
  /\ status' = "revoked" /\ linkEnabled' = FALSE
  /\ revokeStep' = "shareMarked"
  /\ everRevoked' = TRUE
  /\ UNCHANGED <<code, rec, held, via, rpc, unread, revokeTargets,
                 admittedThroughReplacedLink, admittedThroughDisabledLink, replyAfterExit>>

\* Part 2, QLS:384-393: read every recipient document, pick the accepted ones.
RevokeReadsRecipients ==
  /\ revokeStep = "shareMarked"
  /\ revokeTargets' = {r \in Recipients : rec[r] = "accepted"}
  /\ revokeStep' = "recipientsRead"
  /\ UNCHANGED <<status, linkEnabled, code, rec, held, via, rpc, unread, ghosts>>

\* Part 3, QLS:394: the batch writes status "revoked" to the documents read.
RevokeCommitsBatch ==
  /\ revokeStep = "recipientsRead"
  /\ rec' = [r \in Recipients |-> IF r \in revokeTargets THEN "revoked" ELSE rec[r]]
  /\ revokeStep' = "idle" /\ revokeTargets' = {}
  /\ UNCHANGED <<status, linkEnabled, code, held, via, rpc, unread, ghosts>>

\* The function times out or the batch fails between parts. The owner may
\* tap Revoke again later (assertOwnedShare does not check status).
RevokeStopsHalfway ==
  /\ revokeStep \in {"shareMarked", "recipientsRead"}
  /\ revokeStep' = "idle" /\ revokeTargets' = {}
  /\ UNCHANGED <<status, linkEnabled, code, rec, held, via, rpc, unread, ghosts>>

\* markQuestionListShareReplySeen, QLS:330-338: one transaction.
OwnerOpensReply(r) ==
  /\ revokeStep = "idle" /\ unread[r]
  /\ unread' = [unread EXCEPT ![r] = FALSE]
  /\ UNCHANGED <<status, linkEnabled, code, rec, held, via, rpc, revokeStep, revokeTargets, ghosts>>

-----------------------------------------------------------------------------
(* Recipient steps.                                                        *)

\* previewQuestionListShare, QLS:54-90. Reads only (the owner-name refresh
\* write changes nothing modelled). The app's deep link carries the code r
\* opened; via[r] keeps it for the accept that follows. A recipient who is
\* already accepted is routed to the list, and a refused preview shows an
\* error: neither changes server state, so only a claimable preview is a step.
RecipientOpensLink(r) ==
  /\ rpc[r] = "idle" /\ held[r] # 0
  /\ held[r] = code /\ status # "none"               \* QLS:401-411 query by shareCode
  /\ ~(rec[r] = "accepted" /\ status = "active")    \* QLS:66-68 isAccepted
  /\ Claimable                                      \* QLS:75-77
  /\ rpc' = [rpc EXCEPT ![r] = "previewing"]
  /\ via' = [via EXCEPT ![r] = held[r]]
  /\ UNCHANGED <<status, linkEnabled, code, rec, held, unread, revokeStep, revokeTargets, ghosts>>

RecipientClosesPreview(r) ==
  /\ rpc[r] = "previewing"
  /\ rpc' = [rpc EXCEPT ![r] = "idle"]
  /\ UNCHANGED <<status, linkEnabled, code, rec, held, via, unread, revokeStep, revokeTargets, ghosts>>

\* acceptQuestionListShare part 1, QLS:98-108: the share is found by its
\* shareCode OUTSIDE the transaction; only its document reference is kept.
RecipientTapsAccept(r) ==
  /\ rpc[r] = "previewing"
  /\ rpc' = [rpc EXCEPT ![r] = IF via[r] = code /\ status # "none" THEN "accepting" ELSE "idle"]
  /\ UNCHANGED <<status, linkEnabled, code, rec, held, via, unread, revokeStep, revokeTargets, ghosts>>

\* acceptQuestionListShare part 2, QLS:110-164: one transaction on the share
\* reference. It re-reads status, isLinkEnabled and shareCode (the code must
\* still be the one r used, fix for #152), and counts accepted recipients.
AcceptTransaction(r) ==
  /\ rpc[r] = "accepting"
  /\ rpc' = [rpc EXCEPT ![r] = "idle"]
  /\ IF rec[r] = "accepted" /\ status = "active"               \* QLS:127-129 no-op
       THEN UNCHANGED <<rec, admittedThroughReplacedLink, admittedThroughDisabledLink>>
     ELSE IF via[r] # code \/ ~Claimable \/ AcceptedCount >= Cap   \* refused: replaced link, disabled, or full
       THEN UNCHANGED <<rec, admittedThroughReplacedLink, admittedThroughDisabledLink>>
     ELSE /\ rec' = [rec EXCEPT ![r] = "accepted"]              \* QLS:149-163
          /\ admittedThroughReplacedLink' =
               IF via[r] # code THEN admittedThroughReplacedLink \cup {r}
               ELSE admittedThroughReplacedLink
          /\ admittedThroughDisabledLink' =
               IF ~linkEnabled THEN admittedThroughDisabledLink \cup {r}
               ELSE admittedThroughDisabledLink
  /\ UNCHANGED <<status, linkEnabled, code, held, via, unread, revokeStep, revokeTargets,
                 everRevoked, replyAfterExit>>

\* sendQuestionListShareReply: plain reads first, then ONE transaction that
\* re-checks share status and recipient status before it writes (fix for #152).
\* Part 1: read the share, require status "active". The app
\* shows Send Answers only on a list r has accepted.
RecipientTapsSendAnswers(r) ==
  /\ rpc[r] = "idle" /\ rec[r] = "accepted" /\ status = "active"
  /\ rpc' = [rpc EXCEPT ![r] = "replyShareChecked"]
  /\ UNCHANGED <<status, linkEnabled, code, rec, held, via, unread, revokeStep, revokeTargets, ghosts>>

\* Part 2, QLS:297-300: read r's recipient document, require "accepted".
ReplyChecksRecipient(r) ==
  /\ rpc[r] = "replyShareChecked"
  /\ rpc' = [rpc EXCEPT ![r] = IF rec[r] = "accepted" THEN "replyRecipientChecked" ELSE "idle"]
  /\ UNCHANGED <<status, linkEnabled, code, rec, held, via, unread, revokeStep, revokeTargets, ghosts>>

\* Part 3: answer reads, then the transaction re-reads share and recipient and
\* writes the reply snapshot with unreadByOwner true only if r is still an
\* accepted recipient of an active share; otherwise it throws and writes nothing.
ReplyWritten(r) ==
  /\ rpc[r] = "replyRecipientChecked"
  /\ rpc' = [rpc EXCEPT ![r] = "idle"]
  /\ unread' = [unread EXCEPT ![r] = IF rec[r] = "accepted" /\ status = "active" THEN TRUE ELSE unread[r]]
  /\ replyAfterExit' = replyAfterExit
  /\ UNCHANGED <<status, linkEnabled, code, rec, held, via, revokeStep, revokeTargets,
                 everRevoked, admittedThroughReplacedLink, admittedThroughDisabledLink>>

\* leaveQuestionListShare, QLS:251-274: one transaction. The Remove Shared
\* List button stays enabled while Send Answers is in flight
\* (SharedQuestionListViews.swift, AcceptedSharedQuestionListDetailView).
RecipientLeaves(r) ==
  /\ rec[r] = "accepted" /\ status # "none"
  /\ rec' = [rec EXCEPT ![r] = "left"]
  /\ UNCHANGED <<status, linkEnabled, code, held, via, rpc, unread, revokeStep, revokeTargets, ghosts>>

Next ==
  \/ OwnerSharesList
  \/ \E r \in Recipients : OwnerSendsLink(r)
  \/ OwnerDisablesLink
  \/ OwnerRegeneratesLink
  \/ OwnerRevokesShare
  \/ RevokeReadsRecipients
  \/ RevokeCommitsBatch
  \/ RevokeStopsHalfway
  \/ \E r \in Recipients : OwnerOpensReply(r)
  \/ \E r \in Recipients : RecipientOpensLink(r)
  \/ \E r \in Recipients : RecipientClosesPreview(r)
  \/ \E r \in Recipients : RecipientTapsAccept(r)
  \/ \E r \in Recipients : AcceptTransaction(r)
  \/ \E r \in Recipients : RecipientTapsSendAnswers(r)
  \/ \E r \in Recipients : ReplyChecksRecipient(r)
  \/ \E r \in Recipients : ReplyWritten(r)
  \/ \E r \in Recipients : RecipientLeaves(r)

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* Rules. Each one is a promise from GLOSSARY.md, ADR 0001 or the app copy. *)

\* GLOSSARY.md "Share Link": a link admits new recipients only until it is
\* disabled. Regenerate turns a new link on; the old one stays dead.
DisabledLinkAdmitsNoOne == admittedThroughDisabledLink = {}

\* Regenerate exists so that a link that reached the wrong person stops
\* working: no recipient gets in through a link the owner has replaced.
ReplacedLinkAdmitsNoOne == admittedThroughReplacedLink = {}

\* GLOSSARY.md "Revocation" + RULES:306-314: once the owner revokes, no
\* recipient can read the shared list (snapshot and owner answers) again.
RevokedShareStaysClosed == everRevoked => \A r \in Recipients : ~CanReadShare(r)

\* GLOSSARY.md "Share Link": the recipient cap holds.
RecipientCapHolds == AcceptedCount <= Cap

\* App copy on Remove Shared List: "The owner will no longer see future
\* replies from you." Revocation ends replies too: no reply snapshot lands
\* while its sender is not an accepted recipient of an active share.
NoReplyAfterLeavingOrRevocation == replyAfterExit = {}

\* Chart.cfg only: stop exploring after a reply is saved, so the one-recipient
\* chart fits the statechart budget. TLC still checks the rules in those states.
\* Do not name it ChartBound or ChartBudget: statechart defines those names.
SmallChartBound == \A r \in Recipients : ~unread[r]

=============================================================================
