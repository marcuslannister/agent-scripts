---
name: video-transcript-downloader
description: Download videos, audio, subtitles, and clean transcripts from YouTube, Twitch, Instagram, Bilibili, X, and any other yt-dlp supported site. Use when asked to “download this video”, “save this clip”, “rip audio”, “get subtitles”, “get transcript as a paragraph”, or to troubleshoot yt-dlp/ffmpeg, cookies/auth, geo/age restrictions, formats, playlists.
---

# Video Transcript Downloader

One Node CLI. Prefer `youtube-transcript-plus` for YouTube transcripts. Fallback: `yt-dlp` subtitles for everything else.

## Setup

```bash
cd ~/Projects/agent-scripts/skills/video-transcript-downloader
npm ci
```

System deps (needed for downloads; transcript fallback needs `yt-dlp`):

```bash
brew install yt-dlp ffmpeg
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

## Auth / cookies (Instagram, Twitch, restricted)

```bash
./scripts/vtd.js transcript --url 'https://…' --cookies-from-browser chrome
./scripts/vtd.js download --url 'https://…' --cookies ./cookies.txt
```

