# Artifact privacy and paths

- Do not include personal identifiers: local account names, home directory names, real names, or email addresses. This rule includes contributor-credit trailers.
- Use `~` for the user's home directory in prose. In code, derive paths from the repository root, `$HOME`, or the script's location.
- Apply these rules to files, commit messages, and generated artifacts, including documentation, comments, and tests.
- The privacy guard (ADR-0011 in agent-scripts) blocks a commit that adds a home path, an email address, or a secret. If it blocks a commit, fix the line or ask the user. Never bypass it.
