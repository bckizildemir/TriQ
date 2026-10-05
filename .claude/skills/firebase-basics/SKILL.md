---
name: firebase-basics
description: >-
  Provides foundational setup, authentication, and project management workflows
  for Firebase using the Firebase CLI. Use when checking Firebase CLI version
  (must use 'npx -y firebase-tools@latest --version'), initializing a Firebase
  environment, authenticating, setting active projects, or setting up `google-services.json`
  or `GoogleService-Info.plist` files.
---

# Prerequisites

Complete these setup steps before proceeding:

1.  **Local Environment Setup:** Verify the environment is properly set up so we
    can use Firebase tools:

    -   Run `npx -y firebase-tools@latest --version` to check if the Firebase
        CLI is installed.
    -   This repository ships its Firebase skills under `.claude/skills/`. Do
        NOT install plugins, marketplaces, or MCP servers, and do NOT edit the
        configuration of any other IDE or agent. If a skill is missing, tell
        the user and stop.

2.  **Authentication:** Ensure you are logged in to Firebase so that commands
    have the correct permissions. Run `npx -y firebase-tools@latest login`. For
    environments without a browser (e.g., remote shells), use `npx -y
    firebase-tools@latest login --no-localhost`.

    -   The command should output the current user.
    -   If you are not logged in, follow the interactive instructions from this
        command to authenticate.

3. **Active Project:**
   Most Firebase tasks require an active project context.

   > [!IMPORTANT]
   > **For Agents:** This repository uses the Firebase project `ttbp-9d652` and
   > no other project. NEVER create a Firebase project. Do NOT run
   > `projects:create`. If the project appears to be missing or inaccessible,
   > stop and tell the user.

   1. Check the current project by running `npx -y firebase-tools@latest use`.
   2. If the command outputs `Active Project: ttbp-9d652`, continue.
   3. If a different project is active, or if no project is active, set the
      project:
      ```bash
      npx -y firebase-tools@latest use ttbp-9d652
      ```
   4. If the command fails because the project does not exist, stop and tell the
      user. Do not create a replacement project.

# Firebase Usage Principles

Adhere to these principles:

1. **Use npx for CLI commands:** To ensure you always use the latest version of the Firebase CLI, always prepend commands with `npx -y firebase-tools@latest` instead of just `firebase`. For example, use `npx -y firebase-tools@latest --version`. NEVER suggest the naked `firebase` command as an alternative.
2. **Prioritize official knowledge:** Use the `developerknowledge_search_documents` MCP tool ONLY IF it is already available in the current session. Including "Firebase" in the search query significantly improves relevance. If the tool is not available, do NOT install it. Read the vendored reference files under `.claude/skills/` instead, and fall back to Google Search or your internal knowledge base after that.
3. **Follow Agent Skills for implementation guidance:** Skills provide opinionated workflows (CUJs), security rules, and best practices. Always consult them to understand *how* to implement Firebase features correctly instead of relying on general knowledge.
4. **Prefer Firebase MCP Server tools, but only if they are present:** Use the Firebase MCP Server tools ONLY IF they are already available in the current session. In that case, prefer them over manual API calls to remote Firebase APIs. If they are not available, do NOT install an MCP server. Read the vendored reference files under `.claude/skills/`, and ask the user to run the operation if the task still needs a remote API call.
5. **Skill updates are a human task:** These skills are vendored in this repository under `.claude/skills/`. If a skill is out of date, report the problem to the user. Do not install or update plugins yourself.
6. **Automate Config File Retrieval:** When setting up iOS or Android apps, do NOT direct users to the Firebase Console to download `google-services.json` or `GoogleService-Info.plist`. Instead, use the Firebase CLI to fetch the config programmatically:
   - For Android: `npx -y firebase-tools@latest apps:sdkconfig ANDROID <APP_ID> --project <PROJECT_ID>`
   - For iOS: `npx -y firebase-tools@latest apps:sdkconfig IOS <APP_ID> --project <PROJECT_ID>`
   Save the output to the appropriate location (e.g., `app/google-services.json` for Android, or a path to be linked by `xcode-project-setup` for iOS).

# References

- **Initialize Firebase:** See [references/firebase-service-init.md](references/firebase-service-init.md) when you need to initialize new Firebase services using the CLI.
- **Exploring Commands:** See [references/firebase-cli-guide.md](references/firebase-cli-guide.md) to discover and understand CLI functionality.
- **SDK Setup:** For detailed guides on adding Firebase to your app:
  - **Web**: See [references/web_setup.md](references/web_setup.md)
  - **Android**: See [references/android_setup.md](references/android_setup.md)
  - **iOS**: See [references/ios_setup.md](references/ios_setup.md)

# Common Issues

-   **Login Issues:** If the browser fails to open during the login step, use
    `npx -y firebase-tools@latest login --no-localhost` instead.
