#!/usr/bin/env python3
"""
One-time build step: extract the two indices with their structure intact.

The index pages (240-254) are set in two columns, and the main-entry/sub-entry
relationship is carried purely by indentation. Flat text extraction destroys
both: columns interleave line-by-line, and sub-entries lose their parent. Since
the index is what the router reasons over, that mis-attribution would send us to
the wrong pages.

So for these pages only we use `pdftotext -layout`, detect the gutter, read the
columns in the right order, and re-express indentation as nested markdown.

Requires poppler's pdftotext on PATH.

Run:  python3 script/extract_index.py <path-to.pdf>
Output: data/blue-book/indices.md
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "blue-book" / "indices.md"

GENERAL_INDEX = (240, 248)
ACTS_INDEX = (249, 254)

HEADER_RE = re.compile(
    r"The Practice of the Free Church of Scotland\s*[—–-]\s*Page\s+\d+", re.I
)
# Page-heading lines like "Index" / "Index of Acts and Proceedings" sit alone.
HEADING_RE = re.compile(r"^\s*Index(\s+of\s+Acts\s+and\s+Proceedings)?\s*$", re.I)


def raw_page(pdf: pathlib.Path, page: int) -> list[str]:
    out = subprocess.run(
        ["pdftotext", "-layout", "-f", str(page), "-l", str(page), str(pdf), "-"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    lines = []
    for line in out.split("\n"):
        if HEADER_RE.search(line) or HEADING_RE.match(line):
            continue
        if line.strip():
            lines.append(line.rstrip())
    return lines


def find_gutter(lines: list[str]) -> int | None:
    """Return the column where the right-hand column starts, or None if 1-column.

    A gutter is a band of columns that is blank on essentially every line. We
    look only in the middle of the page so that ragged right edges and deep
    sub-entry indents don't masquerade as one.
    """
    if len(lines) < 5:
        return None
    width = max(len(l) for l in lines)
    if width < 60:
        return None

    lo, hi = int(width * 0.30), int(width * 0.72)
    blank_cols = [
        col
        for col in range(lo, hi)
        if all(col >= len(l) or l[col] == " " for l in lines)
    ]
    if not blank_cols:
        return None

    # Longest contiguous run of blank columns = the gutter.
    best = run = [blank_cols[0]]
    for col in blank_cols[1:]:
        if col == run[-1] + 1:
            run.append(col)
        else:
            if len(run) > len(best):
                best = run
            run = [col]
    if len(run) > len(best):
        best = run

    # Real gutters are wide; a 2-space coincidence is not one.
    return best[-1] + 1 if len(best) >= 6 else None


def split_columns(lines: list[str]) -> list[str]:
    gutter = find_gutter(lines)
    if gutter is None:
        return lines
    left = [l[:gutter].rstrip() for l in lines]
    right = [l[gutter:].rstrip() for l in lines]
    return [l for l in left if l.strip()] + [l for l in right if l.strip()]


def to_markdown(lines: list[str]) -> list[str]:
    """Re-express leading indentation as markdown nesting.

    Column 0 is a main entry; anything indented is a sub-entry of the main entry
    above it. Deeper indents are continuation of the previous sub-entry (the
    index wraps long sub-entries onto the next line), so we join those back on.
    """
    out: list[str] = []
    for line in lines:
        indent = len(line) - len(line.lstrip())
        text = " ".join(line.split())
        if not text:
            continue
        if indent == 0:
            out.append(f"\n**{text}**")
        elif indent <= 6:
            out.append(f"- {text}")
        else:
            # Wrapped continuation of the sub-entry above.
            if out and out[-1].startswith("- "):
                out[-1] = f"{out[-1]} {text}"
            else:
                out.append(f"- {text}")
    return out


def find_gutters(lines: list[str], min_width: int = 3) -> list[int]:
    """All column-start positions in a fixed-width table (excluding column 0)."""
    if not lines:
        return []
    width = max(len(l) for l in lines)
    blank = [
        col
        for col in range(width)
        if all(col >= len(l) or l[col] == " " for l in lines)
    ]
    gutters, run = [], []
    for col in blank:
        if run and col == run[-1] + 1:
            run.append(col)
        else:
            if len(run) >= min_width and run[0] != 0:
                gutters.append(run[-1] + 1)
            run = [col]
    if len(run) >= min_width and run[0] != 0 and run[-1] + 1 < width:
        gutters.append(run[-1] + 1)
    return gutters


def acts_table(lines: list[str]) -> list[str]:
    """Render the Acts index as an explicit table.

    It is a three-column layout (Act reference | Title | Blue Book page). Flattened
    to prose, rows like "1845  Assembly Proceedings, page 172  17" are ambiguous
    about which number is the page we should retrieve — so make the columns
    explicit. Rows whose first cell is blank are wrapped continuations.
    """
    # The section opens with full-width prose that would mask the gutters, so
    # detect columns from the table rows alone (a row has a wide internal gap).
    gutters = find_gutters([l for l in lines if re.search(r"\S {3,}\S", l)])
    if len(gutters) < 2:
        return [f"- {' '.join(l.split())}" for l in lines]

    # Use the last two gutters: title starts at the first, pages at the last.
    title_at, pages_at = gutters[0], gutters[-1]

    # Prose runs across the column boundary; table rows and their wrapped
    # continuations always have whitespace sitting at it.
    out, rows = [], []  # type: list[str], list[list[str]]
    for line in lines:
        if len(line) > title_at and line[title_at - 1] != " ":
            out.append(" ".join(line.split()))
            continue
        ref = " ".join(line[:title_at].split())
        title = " ".join(line[title_at:pages_at].split())
        pages = " ".join(line[pages_at:].split())
        # A blank reference cell means a wrapped line. So does a parenthetical
        # one — "(Barrier Act)", "(Class I)" are qualifiers of the reference
        # above, not new Acts.
        if rows and (not ref or ref.startswith("(")):
            if ref:
                rows[-1][0] = f"{rows[-1][0]} {ref}".strip()
            rows[-1][1] = f"{rows[-1][1]} {title}".strip()
            rows[-1][2] = f"{rows[-1][2]} {pages}".strip()
        elif ref or title or pages:
            rows.append([ref, title, pages])

    out += [
        f"- **{r[0]}** — {r[1]} — Blue Book p.{r[2]}" if r[2]
        else f"- **{r[0]}** — {r[1]}"
        for r in rows
    ]
    return out


def section(pdf: pathlib.Path, title: str, span: tuple[int, int], table: bool = False) -> list[str]:
    parts = [f"\n## {title}\n"]
    errata: list[str] = []

    for page in range(span[0], span[1] + 1):
        lines = raw_page(pdf, page)
        if not lines:
            continue

        # ERRATA are official corrections to the printed text. They must not be
        # buried as an index entry — the answering model needs them to avoid
        # quoting a known-wrong Act reference.
        for i, line in enumerate(lines):
            if line.strip().upper() == "ERRATA":
                errata = [
                    " ".join(l.split()) for l in lines[i + 1:] if l.strip()
                ]
                lines = lines[:i]
                break

        if not lines:
            continue
        parts += acts_table(lines) if table else to_markdown(split_columns(lines))

    if errata:
        parts += [
            "\n## ERRATA (official corrections to the printed text)\n",
            "Apply these when citing the affected pages:\n",
        ]
        parts += [f"- {e}" for e in errata]
    return parts


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip())
        return 2
    pdf = pathlib.Path(sys.argv[1]).expanduser()
    if not pdf.is_file():
        print(f"error: no such file: {pdf}", file=sys.stderr)
        return 1

    parts = [
        "# Indices — The Practice of the Free Church of Scotland",
        "",
        "Numbers are printed-book page numbers. Bold lines are main entries;",
        "bulleted lines beneath them are sub-entries of that main entry.",
    ]
    parts += section(pdf, "General Index", GENERAL_INDEX)
    parts += section(pdf, "Index of Acts and Proceedings", ACTS_INDEX, table=True)

    text = re.sub(r"\n{3,}", "\n\n", "\n".join(parts)).strip() + "\n"
    OUT.write_text(text, encoding="utf-8")

    mains = text.count("**") // 2
    print(f"indices     : {OUT}")
    print(f"chars       : {len(text):,}  (~{len(text) // 4:,} tokens)")
    print(f"main entries: {mains}")
    print(f"sub-entries : {text.count(chr(10) + '- ')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
