"""Build the final report from the original .docx (the original is never modified).

  1. Each grey dashed [ SCREENSHOT ] box -> the matching screenshots/fig_X_Y.png
     (fit to the text width, figure caption below it is kept).
  2. Table 6.1 "Actual Output" / "Status" <- screenshots/tests_output.txt
     (text copied from the real sqlplus run; normal black text).
  3. Appendix listing of 04_tests.sql refreshed from database/04_tests.sql.
  4. Scan for leftover placeholders.

Usage (from the repo root):  python3 tools/build_report.py
Only the Python standard library is used.
"""
import re
import struct
import subprocess
import sys
import zipfile
from html import escape, unescape
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "report" / "BCSE302P_Project_KrishitaGupta.docx"
DST = ROOT / "report" / "BCSE302P_Project_KrishitaGupta_final.docx"
SHOTS = ROOT / "screenshots"
TESTS_OUT = SHOTS / "tests_output.txt"
TESTS_SQL = ROOT / "database" / "04_tests.sql"

EMU_PER_TWIP = 635
MAX_W = 9026 * EMU_PER_TWIP           # A4 text width with 1-inch margins
MAX_H = int(7.5 * 914400)             # leave room for the caption on the page

# captions rewritten to match how the test output was actually split across the screenshots
CAPTION_FIXES = {
    "Figure 6.1: Output of TC01–TC06 (booking rules)":
        "Figure 6.1: Output of TC01–TC10 (booking rules and constraints)",
    "Figure 6.2: Output of TC07–TC12 (constraints and status triggers)":
        "Figure 6.2: Output of TC11–TC18 (status triggers, prescription, stock and billing)",
    "Figure 6.3: Output of TC13–TC20 (prescription, stock and billing)":
        "Figure 6.3: Output of TC19–TC22 (billing lock, payment, functions and cursors)",
    "Figure 6.4: Output of TC21–TC22 (functions and cursors)":
        "Figure 6.4: Output of TC22 (cursors) and the audit trail written by trigger T3",
}

PARA_RE = re.compile(r"<w:p[ >].*?</w:p>", re.S)
TEXT_RE = re.compile(r"<w:t[^>]*>([^<]*)</w:t>")


def ptext(xml):
    return unescape("".join(TEXT_RE.findall(xml)))


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit(f"{path.name} is not a PNG file")
    return struct.unpack(">II", head[16:24])


# ------------------------------------------------------------------ 1. screenshots
def image_paragraph(rid, pic_id, name, w_px, h_px):
    cx = MAX_W
    cy = int(cx * h_px / w_px)
    if cy > MAX_H:
        cy = MAX_H
        cx = int(cy * w_px / h_px)
    return (
        '<w:p><w:pPr><w:keepNext/><w:spacing w:before="120" w:after="60" w:line="240" w:lineRule="auto"/>'
        '<w:jc w:val="center"/></w:pPr><w:r><w:drawing>'
        f'<wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="{cx}" cy="{cy}"/>'
        f'<wp:docPr id="{pic_id}" name="Picture {pic_id}"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        f'<pic:nvPicPr><pic:cNvPr id="{pic_id}" name="{name}"/><pic:cNvPicPr/></pic:nvPicPr>'
        f'<pic:blipFill><a:blip r:embed="{rid}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        f'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        "</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"
    )


def insert_screenshots(doc, rels, media):
    box_re = re.compile(r"<w:tbl>(?:(?!<w:tbl>).)*?\[ SCREENSHOT \](?:(?!<w:tbl>).)*?</w:tbl>", re.S)
    out, pos, missing, placed = [], 0, [], []
    for n, m in enumerate(box_re.finditer(doc)):
        caption_xml = PARA_RE.search(doc, m.end()).group(0)
        caption = ptext(caption_xml)
        fm = re.match(r"Figure ([0-9A-Z]+)\.(\d+):", caption)
        if not fm:
            sys.exit(f"Could not find a figure caption after screenshot box #{n + 1}: {caption!r}")
        fname = f"fig_{fm.group(1).lower()}_{fm.group(2)}.png"
        out.append(doc[pos:m.start()])
        img = SHOTS / fname
        if img.exists():
            # a figure may be split over two shots: fig_X_Y.png + fig_X_Yb.png
            extra = img.with_name(img.stem + "b.png")
            for k, part in enumerate([img] + ([extra] if extra.exists() else [])):
                w, h = png_size(part)
                rid = f"rIdShot{n + 1}_{k}"
                target = f"media/{part.name}"
                media[f"word/{target}"] = part.read_bytes()
                rels.append(f'<Relationship Id="{rid}" Type="http://schemas.openxmlformats.org/'
                            f'officeDocument/2006/relationships/image" Target="{target}"/>')
                out.append(image_paragraph(rid, 200 + 10 * n + k, part.name, w, h))
                placed.append(f"{part.name} -> {caption}")
        else:
            out.append(m.group(0))          # keep the box so the gap is obvious
            missing.append(f"{fname}  ({caption})")
        pos = m.end()
    out.append(doc[pos:])
    return "".join(out), placed, missing


# ------------------------------------------------------------------ 2. test table
def parse_tests(text):
    results = {}
    sections = re.split(r"^===== (TC\d\d)\b.*$", text, flags=re.M)
    for tc, body in zip(sections[1::2], sections[2::2]):
        lines = [re.sub(r"\s+:", ":", re.sub(r"\s+", " ", l)).strip() for l in body.splitlines()]
        lines = [l for l in lines if l]
        idx = next((i for i, l in enumerate(lines) if re.match(r"(PASS|FAIL)\b", l)), None)
        if idx is None:
            results[tc] = None
            continue
        status_line = lines[idx]
        status = status_line[:4]
        msg = re.sub(r"^(PASS|FAIL)(\s*\([^)]*\))?:?\s*", "", status_line)
        info = [l for l in lines[:idx] if not l.startswith("ORA-06512")]
        parts = (info if len(info) <= 3 else []) + ([msg] if msg else [])
        results[tc] = ("; ".join(parts) or status_line, status)
    return results


def black_run(run_xml, new_text):
    run_xml = re.sub(r"<w:i/>|<w:iCs/>|<w:color [^>]*/>", "", run_xml)
    return re.sub(r"(<w:t[^>]*>)[^<]*(</w:t>)", lambda m: m.group(1) + escape(new_text, quote=False) + m.group(2), run_xml)


def fill_test_table(doc, results):
    filled, skipped = [], []
    for tc in sorted(results):
        anchor = doc.find(f">{tc}</w:t>")
        if anchor < 0:
            skipped.append(f"{tc}: row not found in Table 6.1")
            continue
        r0 = doc.rfind("<w:tr", 0, anchor)
        r1 = doc.find("</w:tr>", anchor) + len("</w:tr>")
        row = doc[r0:r1]
        if results[tc] is None:
            skipped.append(f"{tc}: no PASS/FAIL line in tests_output.txt")
            continue
        actual, status = results[tc]
        new_row = re.sub(r"<w:r>(?:(?!</w:r>).)*>fill in from run</w:t></w:r>",
                         lambda m: black_run(m.group(0), actual), row, flags=re.S)
        new_row = re.sub(r"<w:r>(?:(?!</w:r>).)*>Pass / Fail</w:t></w:r>",
                         lambda m: black_run(m.group(0), status), new_row, flags=re.S)
        if new_row == row:
            skipped.append(f"{tc}: placeholders already replaced")
            continue
        doc = doc[:r0] + new_row + doc[r1:]
        filled.append((tc, status, actual))
    return doc, filled, skipped


# ------------------------------------------------------------------ 3. appendix listing
LISTINGS = ["database/03_seed.sql", "database/04_tests.sql"]


def file_lines(text):
    return [l.rstrip() for l in text.rstrip("\n").splitlines()]


def committed_versions(rel):
    """Every committed version of a file, as lists of lines (newest first)."""
    shas = subprocess.run(["git", "-C", str(ROOT), "log", "--format=%H", "--", rel],
                          capture_output=True, text=True).stdout.split()
    out = []
    for sha in shas:
        r = subprocess.run(["git", "-C", str(ROOT), "show", f"{sha}:{rel}"], capture_output=True, text=True)
        if r.returncode == 0:
            out.append(file_lines(r.stdout))
    return out


def refresh_listing(doc, rel):
    """Replace the appendix copy of `rel` with the current file, but only if the copy in the
    report matches some committed version of that file (so nothing hand-edited is lost)."""
    current = file_lines((ROOT / rel).read_text())
    paras = list(PARA_RE.finditer(doc))
    texts = [t.rstrip() if t.strip() else "" for t in (ptext(p.group(0)) for p in paras)]
    try:
        head = texts.index(current[1]) - 1        # line 2 of each file is its unique title line
    except ValueError:
        return doc, f"{rel}: listing not found in the appendix - left unchanged"
    if texts[head:head + len(current)] == current:
        return doc, f"{rel}: listing already up to date"
    old = next((v for v in committed_versions(rel) if texts[head:head + len(v)] == v), None)
    if old is None:
        return doc, (f"{rel}: listing in the report doesn't match any committed version - "
                     "left unchanged, please check it by hand")

    template = paras[head + 1].group(0)            # a normal code line paragraph
    def code_para(line):
        return re.sub(r"(<w:t[^>]*>)[^<]*(</w:t>)",
                      lambda m: m.group(1) + escape(line if line else " ", quote=False) + m.group(2),
                      template, count=1)
    new_xml = "".join(code_para(l) for l in current)
    doc = doc[:paras[head].start()] + new_xml + doc[paras[head + len(old) - 1].end():]
    return doc, f"{rel}: listing refreshed ({len(old)} -> {len(current)} lines)"


# ------------------------------------------------------------------ 4. leftovers
def scan(doc):
    issues = []
    for p in PARA_RE.finditer(doc):
        px = p.group(0)
        txt = ptext(px)
        if not txt.strip():
            continue
        is_code = "Courier New" in px
        is_caption = re.match(r"(Figure|Table) [0-9A-Z]+\.\d+:", txt) is not None
        for r in re.findall(r"<w:r>.*?</w:r>", px, re.S):
            rt = ptext(r)
            if not rt.strip():
                continue
            if re.search(r'<w:color w:val="(888888|666666|999999|808080|A6A6A6|7F7F7F)"', r):
                issues.append(("grey text", rt))
            elif "<w:i/>" in r and not is_caption and not is_code:
                issues.append(("italic text (check it is not a placeholder)", rt))
        for word in ("fill in", "Pass / Fail"):
            if word.lower() in txt.lower():
                issues.append((f'contains "{word}"', txt))
        if "SCREENSHOT" in txt:
            issues.append(('contains "SCREENSHOT"', txt))
        if not is_code and re.search(r"[<>]", txt):
            issues.append(("contains < or > (outside code listings)", txt))
        if not is_code and re.search(r"\[[^\]]{2,60}\]", txt) and not re.match(r"\[\d+\]", txt):
            issues.append(("square-bracket text", txt))
    code_angle = sum(1 for p in PARA_RE.finditer(doc)
                     if "Courier New" in p.group(0) and re.search(r"[<>]", ptext(p.group(0))))
    n_comments = len(re.findall(r"<w:commentReference ", doc))
    return issues, code_angle, n_comments


# ------------------------------------------------------------------ main
def main():
    if not SRC.exists():
        sys.exit(f"Missing {SRC}")
    zin = zipfile.ZipFile(SRC)
    doc = zin.read("word/document.xml").decode("utf-8")
    rels_xml = zin.read("word/_rels/document.xml.rels").decode("utf-8")
    new_rels, media = [], {}

    doc, placed, missing = insert_screenshots(doc, new_rels, media)
    for old, new in CAPTION_FIXES.items():
        if f">{escape(old, quote=False)}<" not in doc:
            print(f"  NOTE caption not found (left as is): {old}")
        doc = doc.replace(f">{escape(old, quote=False)}<", f">{escape(new, quote=False)}<")

    if TESTS_OUT.exists():
        results = parse_tests(TESTS_OUT.read_text())
        doc, filled, skipped = fill_test_table(doc, results)
    else:
        filled, skipped = [], [f"{TESTS_OUT.relative_to(ROOT)} not found - run tools/db.sh tests first"]

    listing_notes = []
    for rel in LISTINGS:
        doc, note = refresh_listing(doc, rel)
        listing_notes.append(note)

    rels_xml = rels_xml.replace("</Relationships>", "".join(new_rels) + "</Relationships>")
    with zipfile.ZipFile(DST, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename == "word/document.xml":
                zout.writestr(item, doc.encode("utf-8"))
            elif item.filename == "word/_rels/document.xml.rels":
                zout.writestr(item, rels_xml.encode("utf-8"))
            elif item.filename not in media:
                zout.writestr(item, zin.read(item.filename))
        for name, data in media.items():
            zout.writestr(name, data)

    print(f"\nScreenshots placed ({len(placed)}/{len(placed) + len(missing)}):")
    for p in placed:
        print("  ok  ", p)
    for p in missing:
        print("  MISSING", p)

    print(f"\nTable 6.1 rows filled ({len(filled)}):")
    for tc, status, actual in filled:
        print(f"  {tc}  {status}  {actual}")
    for s in skipped:
        print("  SKIPPED", s)

    print("\nAppendix listings:")
    for note in listing_notes:
        print("  ", note)

    issues, code_angle, n_comments = scan(doc)
    print(f"\nLeftover check ({len(issues)} item(s)):")
    for kind, txt in issues:
        print(f"  - {kind}: {txt[:110]}")
    print(f"  (info) {code_angle} code-listing lines contain < or > - expected in SQL/JS code")
    if n_comments:
        print(f"  - {n_comments} Word comment(s) in the document - delete them before exporting")
    print("  (info) The table of contents is a field: it fills in when Word/LibreOffice updates fields")

    print(f"\nSaved {DST.relative_to(ROOT)}   (original left untouched)")


if __name__ == "__main__":
    main()
