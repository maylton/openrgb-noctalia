#!/usr/bin/env python3
"""Apply a Noctalia RGB color to all OpenRGB devices in one process."""

from __future__ import annotations

import argparse
import colorsys
import fcntl
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HEX_RE = re.compile(r"^[0-9A-Fa-f]{6}$")


def parse_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "on"}


def clamp(value: float) -> float:
    return max(0.0, min(1.0, value))


def transform_color(
    raw_color: str,
    *,
    pastel_correction: bool,
    saturation_threshold: float,
    brightness_threshold: float,
    target_saturation: float,
    target_brightness: float,
) -> tuple[str, bool, float, float]:
    color = raw_color.strip().lstrip("#").upper()
    if not HEX_RE.fullmatch(color):
        raise ValueError(f"invalid RGB color: {raw_color!r}")

    red = int(color[0:2], 16) / 255.0
    green = int(color[2:4], 16) / 255.0
    blue = int(color[4:6], 16) / 255.0

    hue, saturation, brightness = colorsys.rgb_to_hsv(red, green, blue)
    original_saturation = saturation
    original_brightness = brightness

    # Correct only actual pastel colors: bright, washed out, but not neutral.
    corrected = (
        pastel_correction
        and 0.08 <= saturation < clamp(saturation_threshold)
        and brightness > clamp(brightness_threshold)
    )

    if corrected:
        saturation = max(saturation, clamp(target_saturation))
        brightness = min(brightness, clamp(target_brightness))

    red, green, blue = colorsys.hsv_to_rgb(hue, saturation, brightness)
    output = f"{round(red * 255):02X}{round(green * 255):02X}{round(blue * 255):02X}"
    return output, corrected, original_saturation, original_brightness


def emit(payload: dict[str, object], exit_code: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return exit_code


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--color", required=True)
    parser.add_argument("--source", default="noctalia")
    parser.add_argument("--mode", default="direct")
    parser.add_argument("--pastel-correction", default="true")
    parser.add_argument("--saturation-threshold", type=float, default=0.45)
    parser.add_argument("--brightness-threshold", type=float, default=0.85)
    parser.add_argument("--target-saturation", type=float, default=0.65)
    parser.add_argument("--target-brightness", type=float, default=0.85)
    parser.add_argument("--sdk-server", default="false")
    parser.add_argument(
        "--lock-file",
        default=os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "openrgb-noctalia.lock"),
    )
    args = parser.parse_args()

    try:
        output, corrected, saturation, brightness = transform_color(
            args.color,
            pastel_correction=parse_bool(args.pastel_correction),
            saturation_threshold=args.saturation_threshold,
            brightness_threshold=args.brightness_threshold,
            target_saturation=args.target_saturation,
            target_brightness=args.target_brightness,
        )
    except ValueError as error:
        return emit({"ok": False, "error": str(error)}, 2)

    lock_path = Path(args.lock_file)
    lock_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        with lock_path.open("w", encoding="utf-8") as lock:
            try:
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return emit(
                    {
                        "ok": True,
                        "skipped": True,
                        "reason": "another update is already running",
                        "input_color": args.color.strip().lstrip("#").upper(),
                        "output_color": output,
                        "corrected": corrected,
                    }
                )

            command = ["openrgb"]
            if not parse_bool(args.sdk_server):
                command.append("--noautoconnect")
            command.extend(["--mode", args.mode, "--color", output])

            completed = subprocess.run(
                command,
                check=False,
                text=True,
                capture_output=True,
                timeout=25,
            )
    except FileNotFoundError:
        return emit({"ok": False, "error": "openrgb command not found"}, 127)
    except subprocess.TimeoutExpired:
        return emit({"ok": False, "error": "OpenRGB timed out"}, 124)
    except OSError as error:
        return emit({"ok": False, "error": str(error)}, 1)

    if completed.returncode != 0:
        error = (completed.stderr or completed.stdout or "").strip()
        if not error:
            error = f"OpenRGB exited with code {completed.returncode}"
        return emit(
            {
                "ok": False,
                "error": error,
                "returncode": completed.returncode,
                "input_color": args.color.strip().lstrip("#").upper(),
                "output_color": output,
            },
            completed.returncode,
        )

    return emit(
        {
            "ok": True,
            "source": args.source,
            "input_color": args.color.strip().lstrip("#").upper(),
            "output_color": output,
            "corrected": corrected,
            "source_saturation": round(saturation, 6),
            "source_brightness": round(brightness, 6),
            "mode": args.mode,
        }
    )


if __name__ == "__main__":
    raise SystemExit(main())
