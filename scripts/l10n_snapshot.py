#!/usr/bin/env python3
"""Dump the current hand-written l10n tables to a JSON snapshot.

Reads the five translation tables in lib/l10n/translations/
(en, ja, ko, zh, zh_hant) and writes scripts/l10n_snapshot.json:
a {locale: {snake_case_key: value}} dump, keys sorted.

The snapshot is the gen-l10n migration's oracle: the string-diff
test (test/l10n/generated_strings_diff_test.dart) compares the
generated gen-l10n output against it, so any user-visible string
that changes during the migration fails the test.

Usage (from the repo root):

    python3 scripts/l10n_snapshot.py

Paths are resolved relative to this file, so it also works from any
other working directory. The output is deterministic (sorted keys,
no timestamps). The five tables must contain exactly the same key
set (386 keys each at the time of writing); any difference, duplicate
key, or unparsable entry exits non-zero instead of writing a bad
snapshot.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Language tables, relative to the repo root (lib/l10n/translations/).
LANG_FILES = ("en", "ja", "ko", "zh", "zh_hant")

# Matches a Dart string literal: triple-quoted (either quote) or a
# single-line single/double-quoted literal with backslash escapes.
STR_RE = re.compile(
    r"""'''(?:[^\\]|\\.)*?'''|\"\"\"(?:[^\\]|\\.)*?\"\"\""""
    r"""|'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*\"""",
    re.S,
)


def fail(message: str) -> "NoReturn":
    """Print an error to stderr and exit non-zero (never returns)."""
    print(f"l10n_snapshot: error: {message}", file=sys.stderr)
    raise SystemExit(1)


def unescape_dart_string(literal: str) -> str:
    """Decode one Dart string literal (quotes included) to its value."""
    if literal.startswith("'''") or literal.startswith('"""'):
        body = literal[3:-3]
    else:
        body = literal[1:-1]
    out: list[str] = []
    i = 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            nxt = body[i + 1]
            simple = {
                "n": "\n",
                "r": "\r",
                "t": "\t",
                "\\": "\\",
                "'": "'",
                '"': '"',
                "$": "$",
            }
            if nxt in simple:
                out.append(simple[nxt])
                i += 2
                continue
            if nxt == "x":
                out.append(chr(int(body[i + 2 : i + 4], 16)))
                i += 4
                continue
            if nxt == "u":
                if body[i + 2] == "{":
                    end = body.index("}", i + 3)
                    out.append(chr(int(body[i + 3 : end], 16)))
                    i = end + 1
                    continue
                out.append(chr(int(body[i + 2 : i + 6], 16)))
                i += 6
                continue
            out.append(nxt)
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def parse_table(path: Path) -> dict[str, str]:
    """Parse one translation table into {snake_case_key: value}.

    A value is one or more adjacent string literals (Dart concatenates
    them); a value may therefore span several lines. Keys are the
    `'key':` entries at the start of a line inside the map literal.
    """
    if not path.is_file():
        fail(f"missing translation table: {path}")
    text = path.read_text(encoding="utf-8")
    tokens = [(m.start(), m.end(), m.group(0)) for m in STR_RE.finditer(text)]
    brace = text.find("{")
    if brace < 0:
        fail(f"{path}: no map literal found")
    entries: dict[str, str] = {}
    idx = 0
    while idx < len(tokens):
        start, end, raw = tokens[idx]
        if start < brace:
            idx += 1
            continue
        j = end
        while j < len(text) and text[j] in " \t\r\n":
            j += 1
        if j >= len(text) or text[j] != ":":
            idx += 1
            continue
        key = unescape_dart_string(raw)
        values: list[str] = []
        k = idx + 1
        prev_end = j + 1  # just after ':'
        while k < len(tokens):
            vs, ve, vraw = tokens[k]
            if text[prev_end:vs].strip() != "":
                break
            values.append(unescape_dart_string(vraw))
            prev_end = ve
            k += 1
            p = ve
            while p < len(text) and text[p] in " \t\r\n":
                p += 1
            if p < len(text) and text[p] == ",":
                break
        if not values:
            fail(f"{path}: no value for key {key!r}")
        if key in entries:
            fail(f"{path}: duplicate key {key!r}")
        entries[key] = "".join(values)
        idx = k
    return entries


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    translations_dir = root / "lib" / "l10n" / "translations"
    output_path = root / "scripts" / "l10n_snapshot.json"

    tables = {
        lang: parse_table(translations_dir / f"{lang}.dart")
        for lang in LANG_FILES
    }
    reference = tables[LANG_FILES[0]]
    for lang in LANG_FILES[1:]:
        if set(tables[lang]) != set(reference):
            missing = sorted(set(reference) - set(tables[lang]))
            extra = sorted(set(tables[lang]) - set(reference))
            fail(
                f"{lang}.dart key set differs from {LANG_FILES[0]}.dart "
                f"(missing: {missing}; extra: {extra})"
            )

    snapshot = {lang: dict(sorted(tables[lang].items())) for lang in LANG_FILES}
    output_path.write_text(
        json.dumps(snapshot, ensure_ascii=False, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )
    counts = ", ".join(f"{lang}={len(tables[lang])}" for lang in LANG_FILES)
    print(f"l10n_snapshot: wrote {output_path} ({counts} keys each)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
