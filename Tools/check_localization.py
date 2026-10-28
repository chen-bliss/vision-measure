#!/usr/bin/env python3
"""Check that every L("…") key used in Swift sources is translated into every UN official language.

Source strings are Simplified Chinese and double as keys, so zh-Hans needs no Localizable table.
Also verifies printf placeholders match and no Chinese literal bypasses L().
"""
from pathlib import Path
import argparse
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
LOCALIZATION = ROOT / "Resources" / "Localization"
LANGUAGES = ["zh-Hans", "en", "fr", "es", "ru", "ar"]
TRANSLATED = [code for code in LANGUAGES if code != "zh-Hans"]
INFO_PLIST_KEYS = ["CFBundleDisplayName", "CFBundleName", "NSCameraUsageDescription", "NSMicrophoneUsageDescription",
                   "NSSpeechRecognitionUsageDescription", "NSPhotoLibraryAddUsageDescription"]

SWIFT_STRING = r'"((?:[^"\\\n]|\\.)*)"'
L_CALL = re.compile(r'(?<![A-Za-z0-9_])L\(\s*' + SWIFT_STRING)
ANY_LITERAL = re.compile(SWIFT_STRING)
HAN = re.compile(r'[\u3400-\u9fff]')
SPECIFIER = re.compile(r'%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(ld|lld|d|f|@|%)')
# Literals that are data or vocabulary, not interface text.
ALLOWED_LITERALS = {
    "Sources/RefractionCore/Localization.swift": {"简体中文"},
    "Sources/RefractionCore/VoiceAnswerGate.swift": {"左边", "右边", "停止"},
    "Sources/RefractionCore/Models.swift": {"右眼", "左眼"},
    "Sources/VisionMeasure/FunVisionView.swift": {"视界"},
}


def unescape_swift(text):
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), text)


def strip_comments(line):
    in_string = False
    for index, char in enumerate(line):
        if char == '"' and (index == 0 or line[index - 1] != "\\"):
            in_string = not in_string
        if not in_string and line.startswith("//", index):
            return line[:index]
    return line


def source_keys(root=ROOT):
    keys, unwrapped = {}, []
    for path in sorted((root / "Sources").rglob("*.swift")):
        relative = path.relative_to(root).as_posix()
        for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = strip_comments(raw)
            wrapped = set()
            for match in L_CALL.finditer(line):
                keys.setdefault(unescape_swift(match.group(1)), f"{relative}:{number}")
                wrapped.add(match.start(1))
            for match in ANY_LITERAL.finditer(line):
                text = unescape_swift(match.group(1))
                if match.start(1) in wrapped or not HAN.search(text):
                    continue
                if text in ALLOWED_LITERALS.get(relative, set()):
                    continue
                unwrapped.append(f"{relative}:{number}: {text}")
    return keys, unwrapped


def parse_strings(path):
    """Parse a UTF-8 `"key" = "value";` table; comments allowed."""
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'/\*.*?\*/', "", text, flags=re.S)
    text = re.sub(r'^\s*//.*$', "", text, flags=re.M)
    entry = re.compile(r'\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.S)
    table, position = {}, 0
    while position < len(text):
        if not text[position:].strip():
            break
        match = entry.match(text, position)
        if not match:
            line = text.count("\n", 0, position) + 1
            raise ValueError(f"{path}: cannot parse near line {line}")
        key, value = unescape_swift(match.group(1)), unescape_swift(match.group(2))
        if key in table:
            raise ValueError(f"{path}: duplicate key {key!r}")
        table[key] = value
        position = match.end()
    return table


def placeholders(text):
    found, sequential = [], 0
    for match in SPECIFIER.finditer(text):
        kind = match.group(2)
        if kind == "%":
            continue
        # printf integer widths are part of the argument contract. Translating
        # %ld to %d can truncate a Swift Int even though both look like integers.
        if match.group(1):
            found.append((int(match.group(1)), kind))
        else:
            sequential += 1
            found.append((sequential, kind))
    return sorted(set(found))


def check(root=ROOT):
    errors = []
    keys, unwrapped = source_keys(root)
    errors += [f"unlocalized literal {item}" for item in unwrapped]
    localization = root / "Resources" / "Localization"
    for code in LANGUAGES:
        info = localization / f"{code}.lproj" / "InfoPlist.strings"
        if not info.exists():
            errors.append(f"{code}: missing InfoPlist.strings")
            continue
        try:
            table = parse_strings(info)
        except ValueError as error:
            errors.append(str(error)); continue
        errors += [f"{code}: InfoPlist.strings missing {key}" for key in INFO_PLIST_KEYS if not table.get(key)]
    for code in TRANSLATED:
        path = localization / f"{code}.lproj" / "Localizable.strings"
        if not path.exists():
            errors.append(f"{code}: missing Localizable.strings"); continue
        try:
            table = parse_strings(path)
        except ValueError as error:
            errors.append(str(error)); continue
        for key, where in sorted(keys.items(), key=lambda item: item[1]):
            value = table.get(key)
            if not value:
                errors.append(f"{code}: missing translation ({where}) {key!r}")
            elif placeholders(key) != placeholders(value):
                errors.append(f"{code}: placeholder mismatch for {key!r}: {value!r}")
            elif HAN.search(value):
                errors.append(f"{code}: untranslated Chinese in {key!r}")
        errors += [f"{code}: unused key {key!r}" for key in sorted(set(table) - set(keys))]
    return errors, keys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keys", action="store_true", help="print source keys as JSON and exit")
    args = parser.parse_args()
    errors, keys = check()
    if args.keys:
        print(json.dumps(keys, ensure_ascii=False, indent=1)); return 0
    for error in errors:
        print(error, file=sys.stderr)
    print(f"{len(keys)} keys × {len(TRANSLATED)} translated languages; {len(errors)} problem(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
