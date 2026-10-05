---
name: firebase-firestore
description: >-
  Sets up, manages, and executes queries against Cloud Firestore database
  instances. Activate this skill for Firestore data modelling, security rules,
  and Firebase CLI work. Use when listing Firestore databases, configuring
  security rules, designing data models, writing client SDK queries, or
  checking indexes. This skill does not replace the mandatory Swift skills in
  CLAUDE.md; invoke those first for any Swift file.
compatibility: This skill is best used with the Firebase CLI, but does not require it. Firebase CLI can be accessed through `npx -y firebase-tools@latest`.
---

# Cloud Firestore Database and Operations

## 1. This Repository Has One Fixed Database

This repository (TTB) already has its Firestore database. The facts are:

-   Database ID: `(default)`
-   Edition: Standard
-   Location: `eur3`

See `firebase.json` at the repository root.

Obey these rules:

-   NEVER run `firestore:databases:create`.
-   NEVER provision a new database, and never select a different edition or
    location.
-   ALWAYS read the guides under `references/standard/` only.
-   If a command shows no database, this is a credentials problem or a project
    selection problem. Tell the user, and do not create a database.

To inspect the database, you can run this read-only command:

```bash
npx -y firebase-tools@latest firestore:databases:get "(default)"
```

--------------------------------------------------------------------------------

## 2. Specialized Guides

Open and read the reference guides for the Standard edition:

### Standard Edition (`references/standard/`)

-   **Provisioning**: Read [provisioning.md](references/standard/provisioning.md)
-   **Security Rules**: Read [security_rules.md](references/standard/security_rules.md)
-   **SDK Usage**: Read [web_sdk_usage.md](references/standard/web_sdk_usage.md), [android_sdk_usage.md](references/standard/android_sdk_usage.md), [ios_setup.md](references/standard/ios_setup.md), or [flutter_setup.md](references/standard/flutter_setup.md)
-   **Indexes**: Read [indexes.md](references/standard/indexes.md)
