#!/usr/bin/env python3
"""Convert the hand-written l10n Dart maps to gen-l10n ARB files.

Reads the five translation tables in lib/l10n/translations/
(en, ja, ko, zh, zh_hant) and writes:

    lib/l10n/app_en.arb, app_ja.arb, app_ko.arb, app_zh.arb,
    app_zh_Hant.arb
    lib/l10n/app_zh_TW.arb, app_zh_HK.arb, app_zh_MO.arb

The three region files are byte-copies of the zh_Hant content (only
``@@locale`` differs). They exist so the generated delegate keeps the
current 8-entry supportedLocales: without them, a device locale of
zh-TW / zh-HK / zh-MO would resolve to Simplified (zh) instead of
Traditional — see the assessment (item 8, §3 R1) and
test/widgets/locale_zh_hant_resolution_test.dart.

Conversion rules:
- ARB keys are the camelCase form of the snake_case Dart keys (the
  same conversion scripts/gen_l10n_keys.py uses for `S`, which
  matches gen-l10n's own conversion). Values are byte-identical to
  the Dart-map values, except ``confirm_remove_msg`` whose ``%d``
  placeholder is renamed to ``{count}`` (``%d`` is not valid ARB
  placeholder syntax).
- Only the 20 placeholder keys carry ``@key`` metadata, with the
  placeholder types read off the actual call-site value types
  (verified against lib/ at the time of writing; see PLACEHOLDERS).
  The rule was: declare ``String`` unless the call site provably
  passes an ``int``. No plurals / ICU syntax is introduced anywhere
  — the migration reproduces the current wording byte-for-byte.
- ``@@locale`` is set from the file name in every file.

Usage (from the repo root):

    python3 scripts/dart_maps_to_arb.py

Paths are resolved relative to this file, so it also works from any
other working directory. The output is deterministic (keys sorted
alphabetically by their snake_case form, no timestamps). Any
mismatch — key sets differing across languages, a placeholder name
differing across languages, a camelCase collision, a Dart reserved
word, or a value containing a literal brace outside the 20 known
placeholder keys — exits non-zero instead of writing bad ARBs.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Language tables, relative to the repo root (lib/l10n/translations/).
LANG_FILES = ("en", "ja", "ko", "zh", "zh_hant")

# ARB locale tag per table file, and the output ARB file name.
ARB_LOCALES = {
    "en": ("en", "app_en.arb"),
    "ja": ("ja", "app_ja.arb"),
    "ko": ("ko", "app_ko.arb"),
    "zh": ("zh", "app_zh.arb"),
    "zh_hant": ("zh_Hant", "app_zh_Hant.arb"),
}

# Region ARBs: (output file, @@locale). Content is a copy of zh_Hant.
REGION_ARBS = (
    ("app_zh_TW.arb", "zh_TW"),
    ("app_zh_HK.arb", "zh_HK"),
    ("app_zh_MO.arb", "zh_MO"),
)

# Placeholder keys: snake_case key -> [(placeholder name, ARB type)].
# Order is the order of first appearance in the English value, which
# is also the generated method's parameter order. Types were read off
# the actual call sites (see the assessment, §3 R2):
# - count/ms/current (search_page_progress): int — `.length`, `int`
#   fields, or `final int` locals at every call site.
# - version/host/error/line/time/detail/latest/total: String — version
#   strings, host names, `response.error ?? ''`, `'$e'`, or the
#   `totalPagesText` String (search_page_progress's {total}).
# - confirm_remove_msg: `%d` renamed to {count}; call site passes
#   `ids.length` (int).
PLACEHOLDERS: dict[str, list[tuple[str, str]]] = {
    "add_to_booklist_failed": [("error", "String")],
    "booklist_book_count": [("count", "int")],
    "booklist_create_failed": [("error", "String")],
    "booklist_delete_failed": [("error", "String")],
    "booklist_remove_book_failed": [("error", "String")],
    "confirm_remove_msg": [("count", "int")],
    "current_version_label": [("version", "String")],
    "login_unknown_failure": [
        ("line", "String"),
        ("time", "String"),
        ("detail", "String"),
    ],
    "mirror_device_ms": [("ms", "int")],
    "mirror_list_updated": [("count", "int")],
    "mirror_trust_body": [("host", "String")],
    "new_version_found": [("version", "String")],
    "reader_log_export_failed": [("error", "String")],
    "reader_resource_log_count": [("count", "int")],
    "search_page_progress": [("current", "int"), ("total", "String")],
    "search_results_count": [("count", "int")],
    "shelf_count": [("count", "int")],
    "update_current_latest": [("current", "String"), ("latest", "String")],
    "update_dropped_links": [("count", "int")],
    "update_found_title": [("version", "String")],
}

# Dart reserved words that may not be used as identifiers.
DART_RESERVED = frozenset(
    """
    abstract as assert async await break case catch class const
    continue covariant default deferred do dynamic else enum export
    extends extension external factory false final finally for
    Function get hide if implements import in interface is late
    library mixin new null of on operator part required rethrow
    return set show static super switch sync this throw true try
    type typedef var void while with yield
    """.split()
)

# Members of the generated AppLocalizations class that a key must not
# collide with (same check the assessment did for the mechanical
# renames).
GENERATED_MEMBERS = frozenset(
    {
        "delegate",
        "of",
        "supportedLocales",
        "localizationsDelegates",
        "locale",
        "load",
    }
)

PLACEHOLDER_RE = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")

# Matches a Dart string literal: triple-quoted (either quote) or a
# single-line single/double-quoted literal with backslash escapes.
STR_RE = re.compile(
    r"""'''(?:[^\\]|\\.)*?'''|\"\"\"(?:[^\\]|\\.)*?\"\"\""""
    r"""|'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*\"""",
    re.S,
)


def fail(message: str) -> "NoReturn":
    """Print an error to stderr and exit non-zero (never returns)."""
    print(f"dart_maps_to_arb: error: {message}", file=sys.stderr)
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
    """Parse one translation table into {snake_case_key: value}."""
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


def to_camel_case(snake: str) -> str:
    """Convert a snake_case key to a lowerCamelCase Dart identifier.

    Same conversion as scripts/gen_l10n_keys.py (and gen-l10n's own).
    """
    words = snake.split("_")
    return words[0] + "".join(word.capitalize() for word in words[1:])


def arb_value(snake: str, value: str) -> str:
    """ARB form of a Dart-map value (only the %d rename differs)."""
    if snake == "confirm_remove_msg":
        return value.replace("%d", "{count}")
    return value


def build_arb(
    table: dict[str, str], locale_tag: str, keys: list[str]
) -> dict[str, object]:
    """Build one ARB document (ordered dict) from a parsed table."""
    arb: dict[str, object] = {"@@locale": locale_tag}
    for snake in keys:
        camel = to_camel_case(snake)
        arb[camel] = arb_value(snake, table[snake])
        if snake in PLACEHOLDERS:
            arb["@" + camel] = {
                "placeholders": {
                    name: {"type": typ}
                    for name, typ in PLACEHOLDERS[snake]
                }
            }
    return arb


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    translations_dir = root / "lib" / "l10n" / "translations"
    l10n_dir = root / "lib" / "l10n"

    tables = {
        lang: parse_table(translations_dir / f"{lang}.dart")
        for lang in LANG_FILES
    }
    reference = tables[LANG_FILES[0]]
    for lang in LANG_FILES[1:]:
        if set(tables[lang]) != set(reference):
            fail(f"{lang}.dart key set differs from {LANG_FILES[0]}.dart")

    keys = sorted(reference)
    if len(keys) != 386:
        fail(f"expected 386 keys, found {len(keys)}")

    # Validate the placeholder table against the actual values, in
    # every language: same placeholder names per key, no other key
    # with braces, no stray braces, no ICU/plural syntax.
    for snake in keys:
        names = {
            lang: tuple(
                m.group(1)
                for m in PLACEHOLDER_RE.finditer(tables[lang][snake])
            )
            for lang in LANG_FILES
        }
        expected = tuple(
            name for name, _ in PLACEHOLDERS.get(snake, [])
        )
        if snake == "confirm_remove_msg":
            if any("%d" not in tables[lang][snake] for lang in LANG_FILES):
                fail("confirm_remove_msg lost its %d placeholder")
            if any(names[lang] for lang in LANG_FILES):
                fail("confirm_remove_msg unexpectedly has {name} placeholders")
            continue
        for lang in LANG_FILES:
            if names[lang] != expected:
                fail(
                    f"{snake}: placeholder names in {lang} are "
                    f"{list(names[lang])}, expected {list(expected)}"
                )
            value = tables[lang][snake]
            if "%d" in value or ", plural," in value or ", select," in value:
                fail(f"{snake} ({lang}): unexpected ICU/%d syntax")
    found_placeholders = set(PLACEHOLDERS)
    actual_placeholders = {
        snake
        for snake in keys
        if any(
            PLACEHOLDER_RE.search(tables[lang][snake]) for lang in LANG_FILES
        )
    } | {"confirm_remove_msg"}
    if found_placeholders != actual_placeholders:
        fail(
            "placeholder table drift: table has "
            f"{sorted(found_placeholders - actual_placeholders)}, values have "
            f"{sorted(actual_placeholders - found_placeholders)}"
        )

    # Validate camelCase conversions: no collisions, no reserved
    # words, no collision with generated-class members.
    seen: dict[str, str] = {}
    for snake in keys:
        camel = to_camel_case(snake)
        if camel in seen and seen[camel] != snake:
            fail(f"keys {seen[camel]!r} and {snake!r} both convert to {camel!r}")
        seen[camel] = snake
        if camel in DART_RESERVED:
            fail(f"key {snake!r} converts to reserved word {camel!r}")
        if camel in GENERATED_MEMBERS:
            fail(f"key {snake!r} collides with generated member {camel!r}")

    written: list[str] = []
    for lang in LANG_FILES:
        locale_tag, filename = ARB_LOCALES[lang]
        arb = build_arb(tables[lang], locale_tag, keys)
        path = l10n_dir / filename
        path.write_text(
            json.dumps(arb, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        written.append(filename)
    zh_hant_arb = build_arb(tables["zh_hant"], "zh_Hant", keys)
    for filename, locale_tag in REGION_ARBS:
        # Byte-copy of the zh_Hant ARB; only @@locale differs.
        # (Reassigning the existing first key keeps it first.)
        arb = dict(zh_hant_arb)
        arb["@@locale"] = locale_tag
        path = l10n_dir / filename
        path.write_text(
            json.dumps(arb, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        written.append(filename)
    print(
        "dart_maps_to_arb: wrote "
        + ", ".join(written)
        + f" ({len(keys)} keys each, {len(PLACEHOLDERS)} with placeholders)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
