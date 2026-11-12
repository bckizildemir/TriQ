# QuestionListSharing

TLC reached 446 states and 1168 steps. The chart draws 15 states and 39 arrows.
1 state outside the constraints ends a rule's path, and the chart includes it. TLC checks the rules in a state outside the constraints, but it does not explore past it.
The chart does not draw 637 steps that stay in one chart state.
The view hides 239 steps, so the chart does not draw them.

## ReplacedLinkAdmitsNoOne breaks
The shortest path has 6 steps:
0. Not shared yet, no recipient
1. owner taps Share: First link live, no recipient
2. owner sends the link: First link live, no recipient
3. recipient opens the link: First link live, recipient joining
4. recipient taps Accept: First link live, recipient joining
5. owner taps Regenerate Link: New link live, recipient joining
6. server lets the recipient in: New link live, recipient on the list

## NoReplyAfterLeavingOrRevocation breaks
The shortest path has 9 steps:
0. Not shared yet, no recipient
1. owner taps Share: First link live, no recipient
2. owner sends the link: First link live, no recipient
3. recipient opens the link: First link live, recipient joining
4. recipient taps Accept: First link live, recipient joining
5. server lets the recipient in: First link live, recipient on the list
6. recipient taps Send Answers: First link live, recipient sending answers
7. owner taps Revoke Share: Share revoked, recipient sending answers
8. server checks the recipient: Share revoked, recipient sending answers
9. server saves the reply: Share revoked, nobody has access

## Rules that hold
TypeOK, DisabledLinkAdmitsNoOne, RevokedShareStaysClosed, RecipientCapHolds, NoDeadlock
