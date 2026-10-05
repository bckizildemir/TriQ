# Coding standards

This file exists for review tools that look for `CODING_STANDARDS.md` (for example the
`mattpocock-skills:code-review` standards agent). The standards themselves live in `CLAUDE.md`;
do not copy them here.

Review a change against:

1. `CLAUDE.md` → "Coding Style & Naming Conventions" and "Security & Configuration Tips".
2. `.claude/rules/testing.md` for tests.
3. The Swift skills. For each changed `.swift` file, load the matching skill from the routing table
   at the top of `CLAUDE.md` with the Skill tool (`swiftui-pro`, `swiftui-ui-patterns`, `swift-concurrency-pro`,
   `swift-testing-pro`, `swiftui-liquid-glass`, `ios-navigation-chrome`, `swift-style-guide`) and review the file
   against it. `swiftdata-pro` does not apply: this app persists through Firestore.

A finding that a skill or one of these sections supports is a standards finding. Cite the section
or skill by name.
