# Firebase Local Environment Setup

This skill documents the bare minimum setup required for a full Firebase experience for the agent. Before starting to use any Firebase features, you MUST verify that each of the following steps has been completed.

## 1. Verify Node.js
- **Action**: Run `node --version`.
- **Handling**: Ensure Node.js is installed and the version is `>= 20`. If Node.js is missing or `< v20`, install it based on the operating system:

  **Recommended: Use a Node Version Manager**
  This avoids permission issues when installing global packages.

  **For macOS or Linux:**
  1. Guide the user to the [official nvm repository](https://github.com/nvm-sh/nvm#installing-and-updating).
  2. Request the user to manually install `nvm` and reply when finished. **Stop and wait** for the user's confirmation.
  3. Make `nvm` available in the current terminal session by sourcing the appropriate profile:
     ```bash
     # For Bash
     source ~/.bash_profile
     source ~/.bashrc

     # For Zsh
     source ~/.zprofile
     source ~/.zshrc
     ```
  4. Install Node.js:
     ```bash
     nvm install 24
     nvm use 24
     ```

  **For Windows:**
  1. Guide the user to download and install [nvm-windows](https://github.com/coreybutler/nvm-windows/releases).
  2. Request the user to manually install `nvm-windows` and Node.js, and reply when finished. **Stop and wait** for the user's confirmation.
  3. After the user confirms, verify Node.js is available:
     ```bash
     node --version
     ```

  **Alternative: Official Installer**
  1. Guide the user to download and install the LTS version from [nodejs.org](https://nodejs.org/en/download).
  2. Request the user to manually install Node.js and reply when finished. **Stop and wait** for the user's confirmation.

## 2. Verify Firebase CLI
- **Command**: `npx -y firebase-tools@latest --version`
- **Expected**: Successfully outputs a version string.

## 3. Verify Firebase Authentication
You must be authenticated to manage Firebase projects.
- **Action**: Run `npx -y firebase-tools@latest login`.
- **Handling**: If the environment is remote or restricted (no browser access), run `npx -y firebase-tools@latest login --no-localhost` instead.

## 4. Check for Optional MCP Tools
The Firebase MCP Server tools are optional. Use them ONLY IF they are already available in the current session. If they are not available, do NOT install an MCP server, a plugin, or a marketplace. Read the vendored reference files under `.claude/skills/firebase-basics/references/` instead, and ask the user to run the operation if the task still needs a remote API call.

---
**CRITICAL AGENT RULE:** Do NOT proceed with any other Firebase tasks until EVERY step above has been successfully verified and completed.
