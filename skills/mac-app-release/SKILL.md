---
name: mac-app-release
description: "macOS app release: Sparkle, notarization, GitHub Release, Homebrew, closeout."
---

# Mac App Release

Use for BlackBar, RepoBar, CodexBar, Trimmy, and similar Sparkle-updated macOS apps.

## Rules

- Work from the app repo.
- Read `.mac-release.env`; it is the repo-owned release manifest.
- Use `scripts/mac-release` from this skill for shared release/appcast/verify work.
- Keep app-specific build/package/sign behavior in repo scripts unless it is already manifest-driven.
- Never print private key material.
- Prefer Keychain Sparkle signing. `SPARKLE_PRIVATE_KEY_FILE` is an explicit override only.

## Commands

```bash
/Users/steipete/Projects/agent-scripts/skills/mac-app-release/scripts/mac-release status
/Users/steipete/Projects/agent-scripts/skills/mac-app-release/scripts/mac-release notes [version] [output.md]
/Users/steipete/Projects/agent-scripts/skills/mac-app-release/scripts/mac-release changelog-html <version> [CHANGELOG.md]
/Users/steipete/Projects/agent-scripts/skills/mac-app-release/scripts/mac-release make-appcast <zip> [feed-url]
/Users/steipete/Projects/agent-scripts/skills/mac-app-release/scripts/mac-release verify-appcast [version]
/Users/steipete/Projects/agent-scripts/skills/mac-app-release/scripts/mac-release check-assets [tag]
/Users/steipete/Projects/agent-scripts/skills/mac-app-release/scripts/mac-release release
```

## Manifest

Each repo owns `.mac-release.env`. It must contain no secrets.

Required:

- `MAC_RELEASE_APP_NAME`
- `MAC_RELEASE_REPO`
- `MAC_RELEASE_BUNDLE_ID`
- `MAC_RELEASE_VERSION_FILE`
- `MAC_RELEASE_APPCAST`
- `MAC_RELEASE_FEED_URL`
- `MAC_RELEASE_DOWNLOAD_URL_PREFIX`
- `MAC_RELEASE_APP_ZIP`
- either `MAC_RELEASE_INFO_PLIST` or `MAC_RELEASE_SUPUBLIC_ED_KEY`
- `MAC_RELEASE_PACKAGE_CMD`

Common optional:

- `MAC_RELEASE_PRECHECK`
- `MAC_RELEASE_SOURCE_FILES` (space-separated app helper files to source before expanding artifact names)
- `MAC_RELEASE_DSYM_ZIP`
- `MAC_RELEASE_REQUIRE_DSYM=0` for app-only releases
- `MAC_RELEASE_ARTIFACT_PREFIX`
- `MAC_RELEASE_TAG_SIGNED`
- `MAC_RELEASE_TAG_FORCE`
- `MAC_RELEASE_RELEASE_BRANCH`
- `MAC_RELEASE_SPARKLE_ACCOUNT`
- `MAC_RELEASE_SPARKLE_CHANNEL`
- `MAC_RELEASE_GENERATE_APPCAST_ARGS`
- `MAC_RELEASE_RUN_SPARKLE_UPDATE_TEST`
- `MAC_RELEASE_SIGNING_KEY_FILE` (local fallback path only; Keychain is used when the file is absent)
- `MAC_RELEASE_EXTRA_ASSET_PATTERNS`
- `MAC_RELEASE_EXTRA_ASSET_WAIT_SECONDS`
- `MAC_RELEASE_EXTRA_ASSET_WAIT_INTERVAL`
- `MAC_RELEASE_OP_ITEM` + `MAC_RELEASE_OP_FIELDS` for required packaging secrets. The release helper reads the known item once via `op` inside one persistent tmux session, then exports the requested fields for the package command.
- `MAC_RELEASE_OP_ACCOUNT` defaults to `my.1password.com`; `MAC_RELEASE_OP_VAULT`, `MAC_RELEASE_OP_TMUX_SESSION`, `MAC_RELEASE_OP_WAIT_SECONDS` are optional. Without a vault, service-account token env is unset for that single `op` read so the personal desktop account handles it.
- `MAC_RELEASE_RUN_LOGIN_SHELL=1` opts command hooks back into `bash -lc`; default hooks use `env -u BASH_ENV bash -c` so shell startup files cannot override exported release secrets.

1Password rules:

- Prefer already-exported env vars first; no `op` call if all `MAC_RELEASE_OP_FIELDS` are present.
- If fields are missing, use exactly one `op item get` inside tmux for the whole release.
- Use service-account mode only with an explicit vault or `MAC_RELEASE_OP_USE_SERVICE_ACCOUNT=1`.
- Do not retry `op` reads in a fresh shell; rerun only from the same tmux session after explicit user direction.

## Done

- appcast entry has URL, length, Sparkle signature.
- downloaded enclosure verifies with Sparkle.
- extracted app passes `codesign`, `spctl`, and `stapler validate`.
- GitHub release has app zip, dSYM zip when configured, plus app-specific extra assets.
- release notes match the changelog section.
- after verified release, bump changelog to next patch `Unreleased` in the app repo.
