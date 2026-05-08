#!/usr/bin/env python3
"""Type a short US-keyboard string into a Parallels VM via prlctl.

Use this only for short launchers such as "/tmp/r\n". For long commands,
write a script inside the guest first and type the short path.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time


KEYS = {
    "1": 10,
    "2": 11,
    "3": 12,
    "4": 13,
    "5": 14,
    "6": 15,
    "7": 16,
    "8": 17,
    "9": 18,
    "0": 19,
    "-": 20,
    "q": 24,
    "w": 25,
    "e": 26,
    "r": 27,
    "t": 28,
    "y": 29,
    "u": 30,
    "i": 31,
    "o": 32,
    "p": 33,
    "a": 38,
    "s": 39,
    "d": 40,
    "f": 41,
    "g": 42,
    "h": 43,
    "j": 44,
    "k": 45,
    "l": 46,
    "z": 52,
    "x": 53,
    "c": 54,
    "v": 55,
    "b": 56,
    "n": 57,
    "m": 58,
    ",": 59,
    ".": 60,
    "/": 61,
    " ": 65,
    "\n": 36,
}


SHIFT_KEYS = {
    "_": 20,
    ":": 47,
    '"': 48,
    "?": 61,
}


def send_key(vm: str, key: int, delay: float) -> None:
    subprocess.run(
        ["prlctl", "send-key-event", vm, "--key", str(key)],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    time.sleep(delay)


def send_shift_key(vm: str, key: int, delay: float) -> None:
    subprocess.run(
        ["prlctl", "send-key-event", vm, "--key", "50", "--event", "press"],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    send_key(vm, key, delay)
    subprocess.run(
        ["prlctl", "send-key-event", vm, "--key", "50", "--event", "release"],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vm", help="Parallels VM name or UUID")
    parser.add_argument("text", help="Text to type. Use $'...\\n' from zsh for Return.")
    parser.add_argument("--delay", type=float, default=0.08, help="Delay between keys in seconds")
    parser.add_argument("--focus-app", help="Guest app to focus first, e.g. Ghostty")
    args = parser.parse_args()

    if args.focus_app:
        subprocess.run(
            ["prlctl", "exec", args.vm, f"sudo -u steipete -H open -a {args.focus_app!r}"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(0.5)

    for char in args.text:
        lower = char.lower()
        if char in SHIFT_KEYS:
            send_shift_key(args.vm, SHIFT_KEYS[char], args.delay)
        elif lower in KEYS and char == lower:
            send_key(args.vm, KEYS[char], args.delay)
        elif lower in KEYS and char != lower:
            send_shift_key(args.vm, KEYS[lower], args.delay)
        else:
            print(f"unsupported character: {char!r}", file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
