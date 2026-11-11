---- MODULE GuestAccount ----
\* TriQ: a guest favorites questions, creates an account, then deletes it.
\* Source: verify-triq features guest-favorites.md and profile.md; #136 (Home after upgrade).
EXTENDS Naturals
VARIABLES screen, account, favs, upFrom, upErr
vars == <<screen, account, favs, upFrom, upErr>>

Init == screen = "home" /\ account = "guest" /\ favs = 0 /\ upFrom = "none" /\ upErr = FALSE

\* Guest favorites live on the device, at most 10.
StarSaved == screen = "home" /\ account = "guest" /\ favs < 9 /\ favs' = favs + 1
             /\ UNCHANGED <<screen, account, upFrom, upErr>>
StarTenth == screen = "home" /\ account = "guest" /\ favs = 9 /\ favs' = 10 /\ screen' = "limit"
             /\ UNCHANGED <<account, upFrom, upErr>>
StarOverCap == screen = "home" /\ account = "guest" /\ favs = 10 /\ screen' = "limit"
               /\ UNCHANGED <<account, favs, upFrom, upErr>>
MaybeLater == screen = "limit" /\ screen' = "home" /\ UNCHANGED <<account, favs, upFrom, upErr>>
CreateFromLimit == screen = "limit" /\ screen' = "upgrade" /\ upFrom' = "limit" /\ upErr' = FALSE
                   /\ UNCHANGED <<account, favs>>
OpenProfile == screen = "home" /\ screen' = (IF account = "guest" THEN "gprofile" ELSE "aprofile")
               /\ UNCHANGED <<account, favs, upFrom, upErr>>
CloseProfile == screen \in {"gprofile", "aprofile"} /\ screen' = "home"
                /\ UNCHANGED <<account, favs, upFrom, upErr>>
UpgradeFromProfile == screen = "gprofile" /\ screen' = "upgrade" /\ upFrom' = "profile" /\ upErr' = FALSE
                      /\ UNCHANGED <<account, favs>>
CancelUpgrade == screen = "upgrade" /\ screen' = (IF upFrom = "profile" THEN "gprofile" ELSE "home")
                 /\ upErr' = FALSE /\ UNCHANGED <<account, favs, upFrom>>
\* Owner decision #136: a created account closes the sheet and Profile and shows Home.
CreateWorks == screen = "upgrade" /\ screen' = "home" /\ account' = "account" /\ upErr' = FALSE
               /\ UNCHANGED <<favs, upFrom>>
CreateFails == screen = "upgrade" /\ ~upErr /\ upErr' = TRUE /\ UNCHANGED <<screen, account, favs, upFrom>>
GuestDelete == screen = "gprofile" /\ screen' = "signin" /\ account' = "none" /\ favs' = 0
               /\ UNCHANGED <<upFrom, upErr>>
EditProfile == screen = "aprofile" /\ screen' = "edit" /\ UNCHANGED <<account, favs, upFrom, upErr>>
LeaveEdit == screen = "edit" /\ screen' = "aprofile" /\ UNCHANGED <<account, favs, upFrom, upErr>>
DeleteAccount == screen = "edit" /\ screen' = "deletesheet" /\ UNCHANGED <<account, favs, upFrom, upErr>>
CancelDeleteSheet == screen = "deletesheet" /\ screen' = "edit" /\ UNCHANGED <<account, favs, upFrom, upErr>>
DeletePermanently == screen = "deletesheet" /\ screen' = "password" /\ UNCHANGED <<account, favs, upFrom, upErr>>
CancelPassword == screen = "password" /\ screen' = "edit" /\ UNCHANGED <<account, favs, upFrom, upErr>>
ConfirmWithPassword == screen = "password" /\ screen' = "signin" /\ account' = "none" /\ favs' = 0
                       /\ UNCHANGED <<upFrom, upErr>>
Done == screen = "signin" /\ UNCHANGED vars

Next == StarSaved \/ StarTenth \/ StarOverCap \/ MaybeLater \/ CreateFromLimit \/ OpenProfile
        \/ CloseProfile \/ UpgradeFromProfile \/ CancelUpgrade \/ CreateWorks \/ CreateFails
        \/ GuestDelete \/ EditProfile \/ LeaveEdit \/ DeleteAccount \/ CancelDeleteSheet
        \/ DeletePermanently \/ CancelPassword \/ ConfirmWithPassword \/ Done

\* Rules
GuestKeepsAtMostTen == favs <= 10
ProfileMatchesAccount == /\ (screen = "gprofile" => account = "guest")
                         /\ (screen \in {"aprofile", "edit", "deletesheet", "password"} => account = "account")
OnlyGuestsSeeUpgrade == screen \in {"upgrade", "limit"} => account = "guest"
DeletedMeansSignIn == (account = "none") <=> (screen = "signin")
====
