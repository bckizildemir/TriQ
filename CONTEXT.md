# TTB Context

TTB is a three-slot prompt app where people collect questions, answer them, and share focused question-list exchanges with other people.

## Language

**Question List**:
A user-owned collection of question IDs saved for later answering or sharing. A question list belongs to exactly one owner.
_Avoid_: Playlist, folder, set

**Shared Question List**:
A private exchange created from a snapshot of a question list and accepted by one or more recipients. The shared question list is separate from the owner's editable question list.
_Avoid_: Public list, live list, group room

**Share Link**:
An owner-generated link that lets permanent-account users claim access to a shared question list until the link is disabled, revoked, or reaches its recipient cap.
_Avoid_: Public URL, invite code

**Recipient**:
A permanent-account user who accepts a share link and becomes account-bound to that shared question list. Recipients do not see other recipients.
_Avoid_: Guest, viewer, participant

**Answer Snapshot**:
A text-only copy of a user's non-empty answers at the moment they intentionally share them. Later answer edits do not change an existing snapshot.
_Avoid_: Live answers, answer sync

**Reply Snapshot**:
The latest answer snapshot a recipient sends back to the owner for a shared question list. A new reply snapshot replaces the previous one.
_Avoid_: Reply history, comment

**Content Release**:
An admin-published announcement that groups newly available categories and seeded questions into one "What's New" item.
_Avoid_: Draft release, scheduled release, campaign

**Content Update Notification**:
A user-visible notice that one content release is available. A content update notification always points to a content release.
_Avoid_: Marketing push, broadcast, generic notification

**Question Suggestion**:
An AI-generated full Trio question candidate based on a user's draft text. A question suggestion can become the submitted question, but it does not replace the user's ability to author their own question.
_Avoid_: Variation, generated idea

**Notification Opt-in**:
A user's device-level choice to receive content update notifications when system notification permission also allows alerts.
_Avoid_: Global subscription, account-wide preference

**Favorite**:
A question a user saved to return to. A favorite is held on the device until the user has a permanent account and on the account afterwards.
_Avoid_: Bookmark, like, star, saved question

**Guest Favorite**:
A favorite held on the device by a user without a permanent account. Guest favorites are capped; reaching the cap prompts an upgrade, and passing it is refused. They migrate onto the account when the user upgrades, and the device keeps them until the account has accepted them, so a migration that does not succeed loses nothing.
_Avoid_: Local favorite, temporary favorite, anonymous favorite

**Favorite Milestone**:
A one-off encouragement shown to a guest partway to the guest favorite cap, telling them how many they have saved and how many they may save. It is not the Upgrade Prompt: it asks nothing of the user.
_Avoid_: Upgrade prompt, warning, limit notice

**Upgrade Prompt**:
The request to create a permanent account, shown to a guest who reaches the guest favorite cap. It offers the upgrade and lets the guest decline; it does not perform the upgrade itself. It appears wherever the guest reached the cap, including over a question they have opened full screen.
_Avoid_: Signup prompt, limit sheet, favorite limit prompt

**Answer Draft**:
An answer while it is being edited. Answers are compared ignoring the space around them, so retyping the same words with different spacing is not a change.
_Avoid_: Unsaved answer, pending answer, answer form

**Answer Slot**:
One of exactly three positions in an answer. Every question has three, in a fixed order, and any of them may be empty. A slot holds its own text and at most one image.
_Avoid_: Answer field, answer row, answer index

**Revocation**:
The owner action that removes access to a shared question list without deleting either person's normal saved answers.
_Avoid_: Delete answers, unlink

## Example Dialogue

Owner: "I made a question list for our trip and created a share link with my answers included."

Recipient: "I accepted the share link, answered the questions as my normal TTB answers, then sent back a reply snapshot."

Owner: "Now I can compare my answer snapshot with your latest reply snapshot. If I revoke the shared question list, neither of our saved answers are deleted."

Admin: "I published a content release for the new travel category and its seeded questions."

User: "My notification opt-in is enabled, so I received a content update notification and opened the related What's New item."

User: "I started typing a Trio question and picked one question suggestion, then changed the category before submitting."
