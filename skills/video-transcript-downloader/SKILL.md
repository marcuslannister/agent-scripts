---
name: video-transcript-downloader
description: Download videos, audio, subtitles, and clean paragraph-style transcripts from YouTube and any other yt-dlp supported site. Use when asked to “download this video”, “save this clip”, “rip audio”, “get subtitles”, “get transcript”, or to troubleshoot yt-dlp/ffmpeg and formats/playlists.
---

# Video Transcript Downloader

One Node CLI.

How it works:
- Transcript for YouTube: `youtube-transcript-plus` (fast; no files).
- Transcript for everything else (and YouTube fallback): `yt-dlp` downloads subtitles, then this script cleans them into a single paragraph.
- Downloads: `yt-dlp` (optionally uses `ffmpeg` for audio extraction).

## Setup

One-liner:

```bash
cd ~/Projects/agent-scripts/skills/video-transcript-downloader && npm ci
```

## Transcript (default: clean paragraph)

```bash
./scripts/vtd.js transcript --url 'https://…'
./scripts/vtd.js transcript --url 'https://…' --lang en
./scripts/vtd.js transcript --url 'https://…' --timestamps
```

## Download video / audio / subtitles

```bash
./scripts/vtd.js download --url 'https://…' --output-dir ~/Downloads
./scripts/vtd.js audio --url 'https://…' --output-dir ~/Downloads
./scripts/vtd.js subs --url 'https://…' --output-dir ~/Downloads --lang en
```

## Notes

- Default transcript output is a single paragraph. Use `--timestamps` only when asked.
- Pass extra `yt-dlp` args after `--` (works for `transcript` fallback, `download`, `audio`, `subs`):

```bash
./scripts/vtd.js download --url 'https://…' -- --force-ipv4 -v
```

## Troubleshooting (only when needed)

- Missing `yt-dlp` / `ffmpeg`:

```bash
brew install yt-dlp ffmpeg
```

- Verify:

```bash
yt-dlp --version
ffmpeg -version | head -n 1
```
