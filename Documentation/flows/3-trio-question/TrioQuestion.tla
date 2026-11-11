---- MODULE TrioQuestion ----
\* TriQ: write a Trio question. Source: verify-triq feature trio-composer.md and
\* TTB/Views/AI/TrioPromptComposerView.swift (Cancel closes at once; a picked idea stays highlighted).
\* The account kind is fixed per run: a guest who creates an account here is flow 2.
EXTENDS Naturals
VARIABLES screen, account, seen, draft, ideas, err
vars == <<screen, account, seen, draft, ideas, err>>

Init == screen = "home" /\ account \in {"guest", "account"} /\ seen = FALSE
        /\ draft = "empty" /\ ideas = "none" /\ err = FALSE

OpenTrio == screen = "home" /\ screen' = (IF seen THEN "feed" ELSE "disclosure")
            /\ UNCHANGED <<account, seen, draft, ideas, err>>
ContinueDisclosure == screen = "disclosure" /\ screen' = "feed" /\ seen' = TRUE
                      /\ UNCHANGED <<account, draft, ideas, err>>
\* Going back to Home is left out: the flow ends in the Trio feed.
TapPlus == screen = "feed" /\ screen' = (IF account = "guest" THEN "upgrade" ELSE "composer")
           /\ draft' = "empty" /\ ideas' = "none" /\ err' = FALSE /\ UNCHANGED <<account, seen>>
CancelUpgrade == screen = "upgrade" /\ screen' = "feed" /\ UNCHANGED <<account, seen, draft, ideas, err>>
\* 8 to 180 characters; under 8 shows "Use at least 8 characters."
TypeShort == screen = "composer" /\ draft = "empty" /\ draft' = "short" /\ err' = FALSE
             /\ UNCHANGED <<screen, account, seen, ideas>>
TypeEnough == screen = "composer" /\ draft \in {"empty", "short"} /\ draft' = "ok" /\ err' = FALSE
              /\ UNCHANGED <<screen, account, seen, ideas>>
GenerateIdeas == screen = "composer" /\ draft = "ok" /\ ideas = "none" /\ ideas' = "shown" /\ err' = FALSE
                 /\ UNCHANGED <<screen, account, seen, draft>>
PickIdea == screen = "composer" /\ ideas = "shown" /\ ideas' = "picked" /\ draft' = "ok"
            /\ UNCHANGED <<screen, account, seen, err>>
SubmitWorks == screen = "composer" /\ draft = "ok" /\ screen' = "toast"
               /\ UNCHANGED <<account, seen, draft, ideas, err>>
SubmitFails == screen = "composer" /\ draft = "ok" /\ ~err /\ err' = TRUE
               /\ UNCHANGED <<screen, account, seen, draft, ideas>>
ToastEnds == screen = "toast" /\ screen' = "feed" /\ UNCHANGED <<account, seen, draft, ideas, err>>
CancelComposer == screen = "composer" /\ screen' = "feed" /\ UNCHANGED <<account, seen, draft, ideas, err>>

Next == OpenTrio \/ ContinueDisclosure \/ TapPlus \/ CancelUpgrade \/ TypeShort
        \/ TypeEnough \/ GenerateIdeas \/ PickIdea \/ SubmitWorks \/ SubmitFails \/ ToastEnds
        \/ CancelComposer

\* Rules
GuestNeverReachesComposer == screen \in {"composer", "toast"} => account = "account"
OnlyValidQuestionsSubmitted == screen = "toast" => draft = "ok"
DisclosureComesFirst == screen \in {"feed", "upgrade", "composer", "toast"} => seen
====
