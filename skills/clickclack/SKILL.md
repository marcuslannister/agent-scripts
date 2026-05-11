---
name: clickclack
description: "ClickClack ops: hosted chat app, Hetzner prod deploy, DNS/docs/app surfaces, clean Docker rollout."
---

# ClickClack

Use this for ClickClack product/runtime ops, deploys, hosted app checks, and domain questions.

## What

- Repo: `~/Projects/clickclack` / `https://github.com/openclaw/clickclack`
- Product: self-hostable Slack-style chat for OpenClaw/community/agent workflows.
- Surfaces:
  - `https://clickclack.chat` product site
  - `https://app.clickclack.chat` hosted app
  - `https://docs.clickclack.chat` GitHub Pages docs from `docs/`

## Prod

- Hetzner: `clickclack-prod-01`
- IPv4: `157.90.237.80`
- IPv6: `2a01:4f8:1c1c:fb96::/64`
- SSH: `root@157.90.237.80`
- Labels: `app=clickclack`, `env=prod`
- OS: Ubuntu 24.04, Caddy + Docker
- Source on host: `/opt/clickclack-src` (clean export, not a git checkout)
- Previous source: `/opt/clickclack-src.prev` plus timestamped older prev dirs
- Data: `/var/lib/clickclack` bind-mounted to `/app/data`
- Container: `clickclack`, port `127.0.0.1:8080->8080`
- Caddy: `/etc/caddy/Caddyfile` proxies `clickclack.chat, app.clickclack.chat` to `127.0.0.1:8080`; `www` redirects to apex.
- DNS truth: `~/Projects/manager/DOMAINS.md` and `~/Projects/manager/DNS.md`

## Deploy

Golden path:

1. Local refresh:
   - `cd ~/Projects/clickclack`
   - `git status --short --branch`
   - `git fetch origin`
   - If on `main` with no upstream: `git merge --ff-only origin/main`
2. Decide deployed delta:
   - Last known deploy may be the old local `HEAD` before pull; verify `/opt/clickclack-src/.deploy-commit` if present.
   - `git log --oneline <old>..HEAD`
   - `git diff --stat <old>..HEAD`
3. Archive clean HEAD only:
   - Do not rsync untracked local files.
   - `short=$(git rev-parse --short=12 HEAD)`
   - `git archive --format=tar HEAD | ssh root@157.90.237.80 "rm -rf /opt/clickclack-src.next && mkdir -p /opt/clickclack-src.next && tar -C /opt/clickclack-src.next -xf - && printf '%s\n' '$short' > /opt/clickclack-src.next/.deploy-commit"`
4. Preserve env without printing secrets:
   - `docker inspect clickclack --format '{{range .Config.Env}}{{println .}}{{end}}' > /root/clickclack.env.current`
5. Backup before migrations:
   - `mkdir -p /var/lib/clickclack/backups`
   - `chown 1000:1000 /var/lib/clickclack/backups`
   - `docker exec clickclack clickclack backup --data /app/data --out /app/data/backups/clickclack-before-$(date -u +%Y%m%dT%H%M%SZ).db`
6. Build:
   - `docker build --label org.opencontainers.image.revision="$short" -t clickclack:"$short" -t clickclack:latest /opt/clickclack-src.next`
7. Replace container:
   - `docker stop clickclack && docker rm clickclack`
   - `docker run -d --name clickclack --restart unless-stopped --env-file /root/clickclack.env.current -p 127.0.0.1:8080:8080 -v /var/lib/clickclack:/app/data clickclack:latest serve --addr :8080 --data /app/data`
8. Rotate source dirs:
   - Move old `/opt/clickclack-src.prev` to timestamped backup.
   - Move `/opt/clickclack-src` to `/opt/clickclack-src.prev`.
   - Move `/opt/clickclack-src.next` to `/opt/clickclack-src`.

## Verify

- Host:
  - `docker ps --filter name=clickclack`
  - `docker inspect clickclack --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'`
  - `cat /opt/clickclack-src/.deploy-commit`
  - `curl -fsS http://127.0.0.1:8080/ >/tmp/clickclack-root.html`
  - `curl -fsS http://127.0.0.1:8080/app >/tmp/clickclack-app.html`
- Public:
  - `curl -I https://clickclack.chat`
  - `curl -I https://app.clickclack.chat`
  - `curl -I https://docs.clickclack.chat`

## Guardrails

- Do not print OAuth secrets or magic tokens.
- Use a throwaway `UserKnownHostsFile` if local SSH host-key state is stale; confirm server identity with `hcloud server describe clickclack-prod-01` first.
- `clickclack serve` runs migrations on boot; always back up SQLite before replacing the container.
- Keep deploys from clean git archives, not dirty working trees.
