---
name: yt-dlp-downloader
description: Download videos/audio/subtitles from YouTube, Twitch, Instagram, Bilibili, X, and any other yt-dlp supported site. Use when asked to “download this video”, “save this clip”, “rip audio”, “grab subtitles/transcript”, or when troubleshooting yt-dlp/ffmpeg download failures, formats, cookies, geo/age restrictions, or playlists.
---

# yt-dlp Downloader

Practical, reproducible `yt-dlp` workflows (multi-platform sites) + a small wrapper script.

## Prereqs

- `yt-dlp`
- `ffmpeg` + `ffprobe`

macOS (Homebrew):

```bash
brew install yt-dlp ffmpeg
```

Verify:

```bash
yt-dlp --version
ffmpeg -version | head -n 1
ffprobe -version | head -n 1
```

## Quick use (direct yt-dlp)

Note: in `zsh`, always quote URLs containing `?` or `&` (or use `noglob`), otherwise globbing breaks:

```bash
noglob yt-dlp 'https://www.youtube.com/watch?v=…'
```

Download best quality to `~/Downloads`, print final file path:

```bash
yt-dlp -P ~/Downloads -o '%(title).200B (%(id)s).%(ext)s' --print after_move:filepath 'https://…'
```

Prefer MP4 container (remux when possible; no re-encode):

```bash
yt-dlp -P ~/Downloads -o '%(title).200B (%(id)s).%(ext)s' --remux-video mp4 --print after_move:filepath 'https://…'
```

Audio-only (MP3):

```bash
yt-dlp -P ~/Downloads -o '%(title).200B (%(id)s).%(ext)s' -x --audio-format mp3 --print after_move:filepath 'https://…'
```

Subtitles (auto + manual), SRT output, no video:

```bash
yt-dlp --write-sub --write-auto-sub --skip-download --sub-lang en --convert-subs srt \
  --ffmpeg-location "$(command -v ffmpeg)" \
  -o "$HOME/Downloads/%(id)s.%(ext)s" 'https://…'
```

## Formats + quality control

List formats:

```bash
yt-dlp -F 'https://…'
```

Pick a specific format:

```bash
yt-dlp -f 137+140 -P ~/Downloads -o '%(title).200B (%(id)s).%(ext)s' 'https://…'
```

Sort/bias “best” selection (higher resolution first, prefer mp4/m4a when available):

```bash
yt-dlp -S 'res,ext:mp4:m4a,tbr' -P ~/Downloads -o '%(title).200B (%(id)s).%(ext)s' 'https://…'
```

## Auth / cookies (Instagram, Twitch, age/geo restricted)

Use browser cookies (usually simplest):

```bash
yt-dlp --cookies-from-browser chrome -P ~/Downloads -o '%(title).200B (%(id)s).%(ext)s' 'https://…'
```

Or a cookies file (Netscape format):

```bash
yt-dlp --cookies ./cookies.txt -P ~/Downloads -o '%(title).200B (%(id)s).%(ext)s' 'https://…'
```

## Troubleshooting checklist

- Update: `brew upgrade yt-dlp` (or your package manager)
- Try IPv4: `--force-ipv4`
- Inspect errors with `-v`
- If format merge fails: ensure `ffmpeg` is installed, set `--ffmpeg-location`

## Wrapper script (avoids shell URL globbing)

Use when you want “paste URL, get filepath” without shell parsing:

```bash
python3 ./scripts/download.py
```

Non-interactive:

```bash
python3 ./scripts/download.py --url 'https://…' --output-dir ~/Downloads
python3 ./scripts/download.py --mode audio --url 'https://…'
python3 ./scripts/download.py --mode subs --sub-lang en --url 'https://…'
```

