# Secrets and environment variables

- Never reveal secret values, including internal secrets. Redact them from output.
- Use the configured secret-management tool. If no tool is identified, ask before retrieving a secret.
- Query only the exact environment variable needed for the task.
- Never run `env`, `set`, `export -p`, or broad secret searches that expose values in a normal shell.
- To store a secret the user gives, tell them to copy it, then run `<cmd> "$(pbpaste | tr -d '\n')" && pbcopy < /dev/null`. A `!` command gets no stdin, so an interactive prompt stores an empty value. Then check the stored length with `wc -c`. Do not print the value.
- After handling a secret or environment variable, remove token variables from each public `gh` write. Use `env -u GITHUB_TOKEN -u GH_TOKEN -u HOMEBREW_GITHUB_API_TOKEN gh ...`.
