# AIQuotaPools

TLC reached 12,258 states, more than the chart budget of 500, so the chart draws only the bug paths: 9 states and 9 arrows.

## UidWithinDailyLimit breaks
The shortest path has 9 steps:
0. Day 1 / Guest · answers: 0
1. the app asks the AI: Day 1 / Guest · answers: 0 · 1 in flight
2. the app asks the AI: Day 1 / Guest · answers: 0 · 2 in flight
3. the server checks and counts the quota: Day 1 / Guest · answers: 0 · 2 in flight
4. the AI provider answers or fails (no refund): Day 1 / Guest · answers: 1 · 1 in flight
5. UTC midnight passes: Day 2 / Guest · answers day 1: 1, day 2: 0 · counter still on day 1 · 1 in flight (one sent before midnight)
6. the app asks the AI: Day 2 / Guest · answers day 1: 1, day 2: 0 · counter still on day 1 · 2 in flight (one sent before midnight)
7. the server checks and counts the quota: Day 2 / Guest · answers day 1: 1, day 2: 0 · 2 in flight (one sent before midnight)
8. the server checks and counts the quota: Day 2 / Guest · answers day 1: 1, day 2: 0 · counter still on day 1 · 2 in flight
9. the AI provider answers or fails (no refund): Day 2 / Guest · answers day 1: 2, day 2: 0 · counter still on day 1 · 1 in flight

## Rules that hold
TypeOK, PoolWithinDailyLimit, NoWrongLockout, NoDeadlock
