#!/usr/bin/env python3
import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


def _which_or_default(name: str, default: str) -> str | None:
    return shutil.which(name) or (default if Path(default).exists() else None)


def _run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)


def _ensure_tool(path: str | None, friendly: str) -> str:
    if not path:
        raise SystemExit(f"missing {friendly}; install and ensure it is on PATH")
    if not Path(path).exists():
        raise SystemExit(f"missing {friendly} at {path}")
    return path


def _is_abs_path_line(line: str) -> bool:
    line = line.strip()
    if not line:
        return False
    if os.name == "nt":
        return bool(re.match(r"^[a-zA-Z]:\\\\", line))
    return line.startswith("/")


def _prompt_url() -> str:
    sys.stderr.write("paste URL (then Enter): ")
    sys.stderr.flush()
    url = sys.stdin.readline().strip()
    if not url:
        raise SystemExit("no URL provided")
    return url


def main() -> int:
    parser = argparse.ArgumentParser(prog="yt-dlp-downloader")
    parser.add_argument("--url", action="append", help="Video/page URL (repeatable). If omitted, prompt/paste.")
    parser.add_argument("--output-dir", default=str(Path.home() / "Downloads"))
    parser.add_argument("--mode", choices=["video", "audio", "subs"], default="video")
    parser.add_argument("--sub-lang", default="en")
    parser.add_argument("--cookies-from-browser", dest="cookies_from_browser")
    parser.add_argument("--cookies")
    parser.add_argument("--force-ipv4", action="store_true")
    parser.add_argument("--ytdlp")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--dry-run", action="store_true", help="Pass --simulate to yt-dlp")
    parser.add_argument("extra", nargs=argparse.REMAINDER, help="Extra yt-dlp args (prefix with --)")
    args = parser.parse_args()

    urls = args.url or []
    if not urls:
        urls = [_prompt_url()]

    ytdlp = _ensure_tool(args.ytdlp or _which_or_default("yt-dlp", "/opt/homebrew/bin/yt-dlp"), "yt-dlp")
    ffmpeg = args.ffmpeg or _which_or_default("ffmpeg", "/opt/homebrew/bin/ffmpeg")

    output_dir = Path(os.path.expanduser(args.output_dir)).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    base = [ytdlp]
    if args.force_ipv4:
        base.append("--force-ipv4")
    if args.cookies_from_browser:
        base += ["--cookies-from-browser", args.cookies_from_browser]
    if args.cookies:
        base += ["--cookies", args.cookies]
    if args.dry_run:
        base.append("--simulate")

    if os.name == "nt":
        base.append("--windows-filenames")

    # Parse `--` separator for extras (argparse keeps it in the list).
    extras = list(args.extra)
    if extras[:1] == ["--"]:
        extras = extras[1:]
    has_sorting = any(x in ("-S", "--format-sort", "--format-sort-force") for x in extras)

    printed_paths: list[str] = []
    for url in urls:
        cmd = base.copy()

        if args.mode == "subs":
            ffmpeg_path = _ensure_tool(ffmpeg, "ffmpeg (required for subtitle conversion)")
            cmd += [
                "--write-sub",
                "--write-auto-sub",
                "--skip-download",
                "--sub-lang",
                args.sub_lang,
                "--convert-subs",
                "srt",
                "--ffmpeg-location",
                ffmpeg_path,
                "-o",
                str(output_dir / "%(id)s.%(ext)s"),
            ]
        elif args.mode == "audio":
            cmd += [
                "-P",
                str(output_dir),
                "-o",
                "%(title).200B (%(id)s).%(ext)s",
                "-x",
                "--audio-format",
                "mp3",
                "--print",
                "after_move:filepath",
            ]
        else:
            cmd += [
                "-P",
                str(output_dir),
                "-o",
                "%(title).200B (%(id)s).%(ext)s",
                *([] if has_sorting else ["-S", "res,ext:mp4:m4a,tbr"]),
                "--print",
                "after_move:filepath",
            ]

        cmd += extras
        cmd.append(url)

        result = _run(cmd)
        if result.returncode != 0:
            sys.stderr.write(result.stdout)
            sys.stderr.write("\n")
            sys.stderr.write("command failed:\n")
            sys.stderr.write("  " + " ".join(shlex.quote(x) for x in cmd) + "\n")
            return result.returncode

        for line in result.stdout.splitlines():
            if _is_abs_path_line(line) and Path(line.strip()).exists():
                printed_paths.append(line.strip())

        # `--skip-download` subtitle mode: find resulting .srt files.
        if args.mode == "subs":
            srt_files = sorted(output_dir.glob("*.srt"), key=lambda p: p.stat().st_mtime, reverse=True)
            if srt_files:
                printed_paths.append(str(srt_files[0]))

    if printed_paths:
        for p in printed_paths:
            print(p)
    else:
        sys.stderr.write("no output path detected\n")
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
