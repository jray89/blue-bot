#!/usr/bin/env python3
"""
One-time build step: assemble the routing table the cheap model uses to pick pages.

The Blue Book ships with a human-written General Index (pp.240-248) and an Index
of Acts (pp.249-254). That is a far better retrieval map than anything we could
derive by chunking or embedding: it was written by people who know the subject,
and it already speaks in page numbers, which is exactly our retrieval unit.

Run after extract_blue_book.py and extract_index.py:
  python3 script/build_routing_table.py

Output:
  data/blue-book/routing_table.md   contents outline + both indices, ~7k tokens
"""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
BOOK = ROOT / "data" / "blue-book"
OUT = BOOK / "routing_table.md"
INDICES = BOOK / "indices.md"


def main() -> int:
    manifest = json.loads((BOOK / "manifest.json").read_text(encoding="utf-8"))

    # Collapse the per-page manifest back into contiguous (chapter, section)
    # runs so the outline states a page range rather than 254 individual rows.
    outline, current = [], None
    for page_no in range(1, manifest["page_count"] + 1):
        entry = manifest["pages"][str(page_no)]
        key = (entry["chapter"], entry["section"])
        if current and current[0] == key:
            current[1][1] = page_no
        else:
            if current:
                outline.append(current)
            current = [key, [page_no, page_no]]
    if current:
        outline.append(current)

    parts = [
        "# The Practice of the Free Church of Scotland (The Blue Book)",
        f"## Routing table — {manifest['edition']}",
        "",
        "Page numbers below are the printed book's page numbers and are the unit",
        "of retrieval. Every page of the book is individually addressable.",
        "",
        "## Contents outline",
        "",
    ]

    last_chapter = None
    for (chapter, section), (lo, hi) in outline:
        if chapter != last_chapter:
            parts.append(f"\n### {chapter}")
            last_chapter = chapter
        span = f"p.{lo}" if lo == hi else f"pp.{lo}-{hi}"
        parts.append(f"- {section} — {span}")

    # The indices are extracted separately (extract_index.py) because they are
    # set in two columns and carry meaning in their indentation.
    indices = INDICES.read_text(encoding="utf-8")
    # Drop the standalone H1 so the routing table has a single document title.
    indices = "\n".join(
        line for line in indices.split("\n") if not line.startswith("# ")
    ).strip()

    parts += ["", "", indices]

    text = "\n".join(parts).strip() + "\n"
    OUT.write_text(text, encoding="utf-8")

    print(f"routing table : {OUT}")
    print(f"chars         : {len(text):,}  (~{len(text) // 4:,} tokens)")
    print(f"outline rows  : {len(outline)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
