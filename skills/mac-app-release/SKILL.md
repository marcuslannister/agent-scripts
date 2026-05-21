---
name: mac-app-release
description: "Release signed macOS apps with Sparkle, notarization, GitHub Releases, Homebrew checks, and post-release closeout."
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

## Done

- appcast entry has URL, length, Sparkle signature.
- downloaded enclosure verifies with Sparkle.
- extracted app passes `codesign`, `spctl`, and `stapler validate`.
- GitHub release has app zip, dSYM zip when configured, plus app-specific extra assets.
- release notes match the changelog section.
- after verified release, bump changelog to next patch `Unreleased` in the app repo.
