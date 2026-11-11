# AIQuotaPools

TLC reached 558 states, more than the chart budget of 500, so the chart draws only the bug paths: 7 states and 7 arrows.

## UidWithinDailyLimit breaks
The shortest path has 7 steps:
0. Day 1 / Guest · answers: 0
1. the app asks the AI: Day 1 / Guest · answers: 0 · 1 in flight
2. the app asks the AI: Day 1 / Guest · answers: 0 · 2 in flight
3. the server checks and counts the quota: Day 1 / Guest · answers: 0 · 2 in flight
4. the AI provider answers or fails (no refund): Day 1 / Guest · answers: 1 · 1 in flight
5. the user deletes the account (token still valid): Day 1 / Guest, data deleted · answers: 1 · counter says 0 · 1 in flight
6. the server checks and counts the quota: Day 1 / Guest, data deleted · answers: 1 · counter says 1 · 1 in flight
7. the AI provider answers or fails (no refund): Day 1 / Guest, data deleted · answers: 2 · counter says 1

## Rules that hold
TypeOK, PoolWithinDailyLimit, NoWrongLockout, NoDeadlock
