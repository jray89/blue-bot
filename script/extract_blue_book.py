#!/usr/bin/env python3
"""
One-time build step: turn the Blue Book PDF into per-page markdown.

The PDF's pagination was deliberately aligned to the printed book (see p.1), so
PDF page N == printed page N. That makes the page number a citable anchor, and
it is the unit the router selects on.

Run:  python3 script/extract_blue_book.py <path-to.pdf>

Output (all committed to the repo; the PDF itself is not):
  data/blue-book/pages/p009.md   one file per page, running header stripped
  data/blue-book/manifest.json   page -> {chapter, section} for citation labels
"""

import json
import pathlib
import re
import sys

try:
    from PyPDF2 import PdfReader
except ImportError:  # pypdf is the renamed successor; accept either
    from pypdf import PdfReader

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAGES_DIR = ROOT / "data" / "blue-book" / "pages"
MANIFEST = ROOT / "data" / "blue-book" / "manifest.json"

# The running header repeated at the top of every page. Stripping it saves
# ~3k tokens across the book and stops the model quoting it back at us.
HEADER_RE = re.compile(
    r"^\s*The Practice of the Free Church of Scotland\s*[—–-]\s*Page\s+\d+\s*",
    re.IGNORECASE,
)

# Page ranges taken from the printed Contents (pp.5-7). `section` is the
# finer-grained label used when rendering a citation.
STRUCTURE = [
    ((1, 8), "Front Matter", "Title, Preface and Contents"),
    ((9, 12), "Chapter I: The Kirk Session", "Part I: Constitution"),
    ((13, 24), "Chapter I: The Kirk Session", "Part II: Powers and Functions"),
    ((25, 26), "Chapter I: The Kirk Session", "Supplement: The Deacons' Court — Constitution"),
    ((27, 30), "Chapter I: The Kirk Session", "Supplement: The Deacons' Court — Powers and Functions"),
    ((31, 31), "Chapter I: The Kirk Session", "Appendix: Finance Committees"),
    ((32, 38), "Chapter II: The Presbytery", "Part I: Constitution and Officials"),
    ((39, 56), "Chapter II: The Presbytery", "Part II.A: Original Action of Presbytery"),
    ((57, 61), "Chapter II: The Presbytery", "Part II.B: Review Conducted by Presbytery"),
    ((62, 66), "Chapter II: The Presbytery", "Part II.C: Relations to Superior Courts"),
    ((67, 69), "Chapter II: The Presbytery", "Part II.D: General Conduct of Business"),
    ((70, 72), "Chapter III: The Provincial Synod", "Part I: Constitution and Officials"),
    ((73, 74), "Chapter III: The Provincial Synod", "Part II: Powers and Functions"),
    ((75, 79), "Chapter IV: The General Assembly", "Part I: Constitution and Officials"),
    ((80, 85), "Chapter IV: The General Assembly", "Part II: Powers and Functions"),
    ((86, 87), "Chapter IV: The General Assembly", "Supplement: The Commission of Assembly"),
    ((88, 89), "Chapter V: Discipline", "Part I: Nature, Purpose and Scope"),
    ((90, 93), "Chapter V: Discipline", "Part II: General Procedures in all Church Courts"),
    ((94, 102), "Chapter V: Discipline", "Part III: Processes — Kirk Session"),
    ((103, 110), "Chapter V: Discipline", "Part IV: Processes — Presbytery"),
    ((111, 111), "Chapter V: Discipline", "Part V: Processes — Provincial Synod"),
    ((112, 113), "Chapter V: Discipline", "Part VI: Processes — General Assembly or Commission"),
    ((114, 118), "Chapter V: Discipline", "Supplement: Evidence of Persons Unable to Attend"),
    ((119, 121), "Appendix I: Historical Documents", "Westminster Documents"),
    ((122, 136), "Appendix I: Historical Documents", "Claim, Declaration and Protest, 1842"),
    ((137, 140), "Appendix I: Historical Documents", "Protest by Commissioners, 18 May 1843"),
    ((141, 142), "Appendix I: Historical Documents", "Judgments of the House of Lords"),
    ((143, 147), "Appendix I: Historical Documents", "Churches (Scotland) Act, 1905"),
    ((148, 153), "Appendix II: Election and Admission of Office-Bearers", "General"),
    ((154, 156), "Appendix II: Election and Admission of Office-Bearers", "Elders and Deacons"),
    ((157, 162), "Appendix II: Election and Admission of Office-Bearers", "Ministers"),
    ((163, 173), "Appendix III: Property and Trustees", "Property"),
    ((174, 179), "Appendix III: Property and Trustees", "Trustees"),
    ((180, 196), "Appendix IV: Discipline", "The Form of Process"),
    ((197, 202), "Appendix IV: Discipline", "Report of the Committee on the Form of Process (1855)"),
    ((203, 205), "Appendix IV: Discipline", "Questions of Evidence"),
    ((206, 216), "Appendix V: Sample Minutes and Extracts", "A. Kirk Sessions and Deacons' Courts"),
    ((217, 226), "Appendix V: Sample Minutes and Extracts", "B. Presbyteries"),
    ((227, 230), "Appendix V: Sample Minutes and Extracts", "C. Discipline — Kirk Session, Ordinary"),
    ((231, 231), "Appendix V: Sample Minutes and Extracts", "C. Discipline — Kirk Session, Alleged Heresy"),
    ((232, 233), "Appendix V: Sample Minutes and Extracts", "C. Forms of Citation"),
    ((234, 237), "Appendix V: Sample Minutes and Extracts", "C. Minutes Relevant to Presbyteries"),
    ((238, 238), "Appendix V: Sample Minutes and Extracts", "C. Synod Minute; Forms of Libel"),
    ((239, 239), "Appendix V: Sample Minutes and Extracts", "D. Forms of Extracts"),
    ((240, 248), "Indices", "General Index"),
    ((249, 254), "Indices", "Index of Acts and Proceedings"),
]


def locate(page: int):
    for (lo, hi), chapter, section in STRUCTURE:
        if lo <= page <= hi:
            return chapter, section
    return "Unknown", "Unknown"


def clean(raw: str) -> str:
    text = HEADER_RE.sub("", raw or "")
    # PDF extraction gives ragged runs of spaces where line breaks were; collapse
    # to single spaces so token counts stay honest and quotes read cleanly.
    text = re.sub(r"[ \t\xa0]+", " ", text)
    text = re.sub(r"\s*\n\s*", "\n", text)
    return text.strip()


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip())
        return 2

    pdf_path = pathlib.Path(sys.argv[1]).expanduser()
    if not pdf_path.is_file():
        print(f"error: no such file: {pdf_path}", file=sys.stderr)
        return 1

    reader = PdfReader(str(pdf_path))
    PAGES_DIR.mkdir(parents=True, exist_ok=True)
    for stale in PAGES_DIR.glob("p*.md"):
        stale.unlink()

    manifest, empty, total_chars = {}, [], 0

    for idx, page in enumerate(reader.pages, start=1):
        body = clean(page.extract_text())
        if not body:
            empty.append(idx)
        chapter, section = locate(idx)

        (PAGES_DIR / f"p{idx:03d}.md").write_text(body + "\n", encoding="utf-8")
        manifest[str(idx)] = {
            "page": idx,
            "chapter": chapter,
            "section": section,
            "chars": len(body),
        }
        total_chars += len(body)

    MANIFEST.write_text(
        json.dumps(
            {
                "source": pdf_path.name,
                "edition": "Eighth Edition (Revised), 1995",
                "page_count": len(reader.pages),
                "total_chars": total_chars,
                "pages": manifest,
            },
            indent=2,
        ),
        encoding="utf-8",
    )

    print(f"pages written : {len(reader.pages)}  -> {PAGES_DIR}")
    print(f"total chars   : {total_chars:,}  (~{total_chars // 4:,} tokens)")
    if empty:
        print(f"WARNING empty pages: {empty}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
