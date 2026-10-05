# Question list sharing UX

## Lists screen segments

- **Lists** (formerly Mine): editable personal question lists only.
- **Shared**: unified hub for collaboration on question lists.

## Shared hub

The Shared segment shows two sections when data exists:

| Section | Data source | Detail screen |
|---------|-------------|---------------|
| Received | `SharedQuestionListStore.acceptedShares` | Side-by-side owner vs your answers; send reply from menu |
| Sent | `SharedQuestionListStore.ownedShares` | Side-by-side owner vs recipient answers on first screen when someone has accepted |

Empty state copy: lists you receive or send with others appear in Shared.

Sent rows prefetch recipient summaries so unread reply indicators can appear before opening a share.

## Sender detail

- Link actions (share, disable, regenerate, revoke) live in the toolbar menu.
- One recipient: comparison cards show immediately.
- Multiple recipients: **Compare with** picker at the top, then the same side-by-side cards.

Firestore listeners and security rules are unchanged; this is presentation-only.
