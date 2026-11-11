# Install, launch, and connect Metrix.Bar

## Decide what is missing

- **Installed and running:** do not reinstall. Proceed to the connection steps below.
- **Installed but stopped:** launch the existing application from the OS applications menu (or its confirmed installation path), then connect.
- **Not installed:** when the user has requested installation, detect the machine, select and verify a compatible GUI package, then install and launch within that scope. Do not ask for the same authorization again. If installation was not requested, ask before installing.
- **Connected:** verify both reachability and authenticated access before dashboard operations.

Do not read the app's private configuration to discover a token. Do not disable Gatekeeper, SmartScreen, signature checks, or other OS protection. Let the user handle system authorization and any required administrator approval; never elevate privileges or install system dependencies without the user's explicit approval.

## Detect the actual OS and CPU

Use host commands, not the agent runtime's presumed platform. On macOS or Linux:

```bash
uname -s
uname -m
```

On macOS, also run `sw_vers -productVersion`. If a shell is translated under Rosetta, check `sysctl -in sysctl.proc_translated` and `sysctl -n hw.optional.arm64` to identify Apple silicon instead of selecting an Intel package solely from `uname -m`. On Linux inspect `/etc/os-release` to choose a supported package method; a GUI desktop session is required.

In Windows PowerShell, inspect the actual OS architecture and version (a 32-bit agent process does not imply a 32-bit OS):

```text
[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
(Get-CimInstance Win32_OperatingSystem).Version
```

Map Darwin → `macos`, Windows → `windows`, Linux → `linux`; `aarch64`/ARM64 → `arm64`, `amd64`/x86_64/X64 → `x86_64`. Do not guess unsupported architectures.

## Select a live GUI download

Fetch `https://downloads.agili.app/metrix-bar/release-info.json`. Its current contract is `schemaVersion: 1`, with `channels.stable` and `channels.preview` (each may be null). A channel contains `displayVersion` and `downloads`. Each download contains `platform`, `arch`, `format`, `name`, `url`, `sha256`, and optional `role` and `minimumSystemVersion`.

1. Choose `channels.stable` by default. Only choose `channels.preview` if the user explicitly requests preview. If stable has no compatible GUI package, explain that fact and, if available, offer preview; do not silently switch channels.
2. Filter for the detected platform and `role === "gui"` **or missing role**. Exclude CLI packages.
3. Match the native CPU exactly; on macOS an `arch: "universal"` GUI package is also valid for Intel and Apple silicon. Do not substitute another architecture.
4. Compare the host OS version against `minimumSystemVersion` where present. Do not install an incompatible package. Current macOS builds require macOS 12 or newer; always honor the selected asset's requirements.
5. Current GUI formats are macOS `dmg`, Windows NSIS `exe`, and Linux `deb` or `tar.gz`. Inspect the actual index rather than inventing a filename, URL, package manager, or format. There is no published Homebrew/winget formula, RPM, or AppImage promised by this guide.
6. Use the asset's `url` unchanged. Download into a temporary/user-owned directory. Verify the downloaded bytes against **that asset's** `sha256` before opening, executing, mounting, or extracting them. Stop on mismatch or missing verification data.

For example, after setting `ASSET_URL` and `PACKAGE` to the selected URL and a local destination (never a token):

```bash
curl -fL "$ASSET_URL" -o "$PACKAGE"
# macOS:
shasum -a 256 "$PACKAGE"
# Linux:
sha256sum "$PACKAGE"
```

In PowerShell:

```text
Invoke-WebRequest -Uri $AssetUrl -OutFile $Package
Get-FileHash -Algorithm SHA256 -LiteralPath $Package
```

Compare the computed digest with the index, case-insensitively. Do not continue merely because the command succeeded.

## Install and launch

### macOS: DMG

Mount the verified image read-only:

```bash
hdiutil attach -readonly -nobrowse "$PACKAGE"
```

Read the command's actual mount point (do not assume `/Volumes/Metrix.Bar`). Locate the real `.app` bundle at that mount point. Use the user's chosen destination; otherwise prefer writable `/Applications`, falling back to user-owned `~/Applications`. Do not replace an existing installation unless the user requested that update or replacement. With `APP_BUNDLE` set to that discovered bundle and `DESTINATION` to the selected application directory:

```bash
mkdir -p "$DESTINATION"
ditto "$APP_BUNDLE" "$DESTINATION/$(basename "$APP_BUNDLE")"
hdiutil detach "$MOUNT_POINT"
open "$DESTINATION/$(basename "$APP_BUNDLE")"
```

Set `MOUNT_POINT` from the mount output. Detach even if copying fails, but launch only after a successful copy. If the selected directory requires authorization, hand that step to the user rather than using unsolicited privilege escalation. Respect system security prompts.

### Windows: NSIS EXE

Run the verified installer through the normal interactive installation flow:

```text
Start-Process -FilePath $Package -Wait
```

Have the user complete the installer and any OS authorization. Do not invent silent switches or installation paths. Start Metrix.Bar from its installed Start menu shortcut, or the installer's launch option, and confirm it is running in the system tray.

### Linux: DEB or tar.gz

The app needs GTK 3, a StatusNotifierItem tray host, a graphical desktop, and a D-Bus session. Tray behavior varies by desktop and does not promise macOS-style text. DEB metadata may declare additional distribution dependencies; use the package manager's real diagnostics rather than removing those requirements.

For a `deb` on Debian/Ubuntu, open the verified file with the desktop package installer and let the user authorize installation and dependencies. Alternatively, if the user chooses a system package installation, the standard package-manager operation is `apt install /absolute/path/to/the-verified.deb` in a user-authorized administrator session. Do not run it with automatic elevation. Launch from the applications menu. To inspect the installed paths without assuming them, use `dpkg-deb -c "$PACKAGE"` and the packaged desktop entry; the current package places the executable under `/opt/metrix-bar/metrix-bar`.

For a `tar.gz`, inspect before extraction:

```bash
tar -tzf "$PACKAGE"
mkdir -p "$HOME/.local/opt/metrix-bar"
tar -xzf "$PACKAGE" -C "$HOME/.local/opt/metrix-bar"
cd "$HOME/.local/opt/metrix-bar"
./metrix-bar
```

Use a new, empty extraction directory (choose a different directory if the one above exists). Reject entries escaping it through absolute paths, `..`, or unsafe links. The current archive has `metrix-bar` at its root with companion resources and desktop assets; confirm the listing and keep those files together. Run the executable from that extracted directory, inside the user's desktop session. Do not assume a separately published `install.sh` exists in the release index. If dependencies or tray support are missing, explain the desktop/package requirements and let the user decide how to install them; do not guess a different package format.

## Connect and verify

1. Open **Agent** in the running app.
2. Enable **Enable local API** and confirm the status is **Running**.
3. Ask the user to click **Copy Prompt** and send that prompt to this agent session. It includes the actual base URL and Bearer token. Port `6387` is only the preferred default, not a value to assume.
4. Use the supplied loopback address. Do not send an `Origin` header. Keep the token in transient session variables only, out of source files, command tracing, logs, fixtures, and responses. Do not echo it back.
5. Check the two distinct conditions below, using `MB` and `TOKEN` from the supplied prompt:

```bash
curl -fsS "$MB/v0/health"
curl -fsS -H "Authorization: Bearer $TOKEN" "$MB/v0/dashboards"
```

The first is unauthenticated and confirms service reachability only. The second verifies permission. If health fails, check that the app and local API are running and use the actual address; do not scan arbitrary network hosts. If listing returns 401, request a fresh Copy Prompt rather than searching private local files. Do not reveal credentials in troubleshooting output.

Return to [the skill](../SKILL.md) for validation, isolated checks, ETag-safe source updates, ordinary input configuration, and secret isolation.
