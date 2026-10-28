#!/usr/bin/env python3
"""Verify the distributable Mac bundle, including its actual localization resources."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess

import check_localization as localization


def check(app):
    contents = app / "Contents"
    with (contents / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    models = (localization.ROOT / "Sources/RefractionCore/Models.swift").read_text(encoding="utf-8")
    for field, key in [("version", "CFBundleShortVersionString"), ("build", "CFBundleVersion")]:
        expected = re.search(rf'static let {field} = "([^"]+)"', models).group(1)
        if info.get(key) != expected:
            raise ValueError(f"{key}: expected {expected}, got {info.get(key)}")
    if set(info.get("CFBundleLocalizations", [])) != set(localization.LANGUAGES):
        raise ValueError("The app must declare all six interface languages")
    executable = contents / "MacOS" / info["CFBundleExecutable"]
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError(f"Missing runnable executable: {executable}")
    for language in localization.LANGUAGES:
        for name in ["InfoPlist.strings"] + ([] if language == "zh-Hans" else ["Localizable.strings"]):
            packaged = contents / "Resources" / f"{language}.lproj" / name
            # Apple's parser also validates escaping and encoding in the shipped file.
            result = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(packaged)],
                                    check=True, capture_output=True, text=True)
            actual = json.loads(result.stdout)
            expected = localization.parse_strings(localization.LOCALIZATION / f"{language}.lproj" / name)
            if actual != expected:
                raise ValueError(f"Stale or missing packaged translations: {packaged}")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    print(f"Verified {app}: {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), "
          "six languages, current translations, executable and signature")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    check(parser.parse_args().app)
