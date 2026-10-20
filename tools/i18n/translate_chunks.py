#!/usr/bin/env python3
"""Parallel-translation helper for Slavian's .po catalogs.

Splits the still-untranslated strings into chunk files (one per translator),
then merges the filled chunks back into `client/i18n/sr_Latn.po`:

    python3 tools/i18n/translate_chunks.py split [n]   # default 4 chunks
    python3 tools/i18n/translate_chunks.py merge

Chunk files are written to `client/i18n/.translations/chunk_<k>.po` and are
temporary; delete that folder once merged.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract  # noqa: E402

DIR = extract.OUT / ".translations"


def missing_messages():
    messages = extract.collect()
    have = extract.parse_po(extract.OUT / "sr_Latn.po")
    missing = [m for m in messages if not any(have.get(m, []))]
    return messages, missing


def split(n: int) -> None:
    messages, missing = missing_messages()
    DIR.mkdir(parents=True, exist_ok=True)
    for old in DIR.glob("chunk_*.po"):
        old.unlink()
    per = (len(missing) + n - 1) // n
    for i in range(n):
        subset = {m: messages[m] for m in missing[i * per:(i + 1) * per]}
        (DIR / f"chunk_{i + 1}.po").write_text(extract.render(subset, "sr_Latn", {}), encoding="utf-8")
    print(f"{len(missing)} untranslated in {n} chunks of up to {per} -> {DIR}")


def merge() -> None:
    messages, _ = missing_messages()
    translations = extract.parse_po(extract.OUT / "sr_Latn.po")
    filled = 0
    for chunk in sorted(DIR.glob("chunk_*.po")):
        for msgid, msgstr in extract.parse_po(chunk).items():
            if any(msgstr):
                translations[msgid] = msgstr
                filled += 1
    (extract.OUT / "sr_Latn.po").write_text(extract.render(messages, "sr_Latn", translations), encoding="utf-8")
    still = [m for m in messages if not any(translations.get(m, []))]
    print(f"merged {filled} translations; still untranslated: {len(still)}")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "split":
        split(int(sys.argv[2]) if len(sys.argv) > 2 else 4)
    else:
        merge()
