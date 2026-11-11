---- MODULE FirstAnswer ----
\* TriQ: first open to first answer, as a guest. Source: verify-triq features
\* guest-onboarding.md and question-card.md.
EXTENDS Naturals
VARIABLES screen, step, legal, typed, saveFailed, told
vars == <<screen, step, legal, typed, saveFailed, told>>

Init == screen = "signin" /\ step = 0 /\ legal = FALSE /\ typed = 0
        /\ saveFailed = FALSE /\ told = FALSE

ContinueAsGuest == screen = "signin" /\ screen' = "intro" /\ step' = 1
                   /\ UNCHANGED <<legal, typed, saveFailed, told>>
Continue == screen = "intro" /\ step < 5 /\ step' = step + 1
            /\ UNCHANGED <<screen, legal, typed, saveFailed, told>>
Skip == screen = "intro" /\ step < 5 /\ step' = 5
        /\ UNCHANGED <<screen, legal, typed, saveFailed, told>>
Back == screen = "intro" /\ step > 1 /\ step' = step - 1
        /\ UNCHANGED <<screen, legal, typed, saveFailed, told>>
ToggleLegal == screen = "intro" /\ step = 5 /\ legal' = ~legal
               /\ UNCHANGED <<screen, step, typed, saveFailed, told>>
\* "See Today's Questions" is disabled until the legal toggle is on.
Finish == screen = "intro" /\ step = 5 /\ legal /\ screen' = "home"
          /\ UNCHANGED <<step, legal, typed, saveFailed, told>>
\* Opening a card starts a fresh visit; an earlier silent failure is no longer on screen.
OpenCard == screen = "home" /\ ~saveFailed /\ screen' = "card" /\ typed' = 0
            /\ saveFailed' = FALSE /\ told' = FALSE /\ UNCHANGED <<step, legal>>
TypeAnswer == screen = "card" /\ typed < 3 /\ typed' = typed + 1
              /\ UNCHANGED <<screen, step, legal, saveFailed, told>>
\* Save closes the card at once; the server call runs after the card closes. A failure rolls the
\* answers back and sets QuestionModel.error, which HomeView shows as an "Error" alert with OK
\* (Models/AnswerDraftStore.swift finish, Models/QuestionModel.swift report, Views/Main/HomeView.swift).
SaveWorks == screen \in {"card", "dialog"} /\ typed > 0 /\ screen' = "home"
             /\ typed' = 0 /\ saveFailed' = FALSE /\ UNCHANGED <<step, legal, told>>
SaveFails == screen \in {"card", "dialog"} /\ typed > 0 /\ screen' = "home"
             /\ typed' = 0 /\ saveFailed' = TRUE /\ told' = TRUE /\ UNCHANGED <<step, legal>>
\* The failure alert is on Home while told is TRUE and the user has not tapped OK yet.
DismissError == screen = "home" /\ saveFailed /\ told /\ saveFailed' = FALSE /\ told' = FALSE
                /\ UNCHANGED <<screen, step, legal, typed>>
CloseEmpty == screen = "card" /\ typed = 0 /\ screen' = "home"
              /\ UNCHANGED <<step, legal, typed, saveFailed, told>>
CloseWithText == screen = "card" /\ typed > 0 /\ screen' = "dialog"
                 /\ UNCHANGED <<step, legal, typed, saveFailed, told>>
CloseWithoutSaving == screen = "dialog" /\ screen' = "home" /\ typed' = 0
                      /\ UNCHANGED <<step, legal, saveFailed, told>>

Next == ContinueAsGuest \/ Continue \/ Skip \/ Back \/ ToggleLegal \/ Finish
        \/ OpenCard \/ TypeAnswer \/ SaveWorks \/ SaveFails \/ CloseEmpty
        \/ CloseWithText \/ CloseWithoutSaving \/ DismissError

\* Rules
LegalAgreedBeforeHome == screen \in {"home", "card", "dialog"} => legal
AtMostThreeAnswers == typed <= 3
LostSaveIsShown == (screen = "home" /\ saveFailed) => told
====
