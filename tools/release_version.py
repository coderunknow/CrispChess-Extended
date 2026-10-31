"""Read the App Store version and build number from pubspec.yaml."""

from __future__ import annotations

from pathlib import Path
import re

PUBSPEC = Path(__file__).resolve().parents[1] / "pubspec.yaml"


def read_version(pubspec: Path = PUBSPEC) -> tuple[str, str]:
    for line in pubspec.read_text().splitlines():
        if line.startswith("version:"):
            value = line.partition(":")[2].partition("#")[0].strip().strip("\"'")
            # Flutter permits prerelease identifiers for development builds.
            # Apple bundle short versions remain numeric x.y.z; the build
            # number distinguishes dev submissions, while the application
            # package metadata still carries the prerelease suffix.
            match = re.fullmatch(r"(\d+\.\d+\.\d+)(?:-[0-9A-Za-z.-]+)?\+(\d+)", value)
            if match:
                return match.group(1), match.group(2)
            break
    raise ValueError(f"{pubspec}: expected version: x.y.z[-prerelease]+BUILD")
