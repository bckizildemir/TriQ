# Provisioning Cloud Firestore

> [!IMPORTANT]
> **This repository is already provisioned.** The project is `ttbp-9d652`. The
> database is `(default)`, Standard edition, location `eur3`. The files
> `firebase.json`, `firestore.rules`, and `firestore.indexes.json` exist at the
> repository root.
>
> Read the sections below as reference only. Do NOT create a database, and do
> NOT change the `database` or `location` keys in `firebase.json`.

## Manual Initialization

Initialize the following firebase configuration files manually. Do not use `npx
-y firebase-tools@latest init`, as it expects interactive inputs.

1.  **Create `firebase.json`**: This file configures the Firebase CLI.
2.  **Create `firestore.rules`**: This file contains your security rules.
3.  **Create `firestore.indexes.json`**: This file contains your index
    definitions.

### 1. Create `firebase.json`

Create a file named `firebase.json` in your project root with the following
content. If this file already exists, instead append to the existing JSON:

```json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  }
}
```

This will use the default database with the Standard edition. To use a different
database, specify the database ID and location. You can check the list of
available databases using `npx -y firebase-tools@latest
firestore:databases:list`. If the database does not exist, it will be created
when you deploy:

```json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json",
    "database": "my-database-id",
    "location": "us-central1"
  }
}
```

### 2. Create `firestore.rules`

Create a file named `firestore.rules`. A good starting point (locking down the
database) is:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

*See [security_rules.md](security_rules.md) for how to write actual rules.*

### 3. Create `firestore.indexes.json`

Create a file named `firestore.indexes.json` with an empty configuration to
start:

```json
{
  "indexes": [],
  "fieldOverrides": []
}
```

*See [indexes.md](indexes.md) for how to configure indexes.*

## Deploy database, rules and indexes

> [!IMPORTANT]
> In this repository the database, the rules, and the indexes already exist. The
> database is `(default)`, Standard edition, location `eur3`, in the project
> `ttbp-9d652`. There is nothing to provision.
>
> A deploy overwrites the LIVE configuration of a production project. NEVER
> deploy the database, the rules, or the indexes unless the user explicitly asks
> for the deploy in the same turn. Edit `firestore.rules` and
> `firestore.indexes.json` in the repository, then let the user deploy.

## Local Emulation

To run Firestore locally for development and testing:

```bash
npx -y firebase-tools@latest emulators:start --only firestore
```

This starts the Firestore emulator, typically on port 8080. You can interact
with it using the Emulator UI (usually at http://localhost:4000/firestore).
