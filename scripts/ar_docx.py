#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ar_docx.py — التحكم الكامل في ملفات وورد العربية.

القراءة والفحص (لا يكتب شيئاً):
    python3 ar_docx.py read  file.docx                 النص بأرقام الفقرات والجداول
    python3 ar_docx.py check file.docx                 فحص Arab Writer لكل فقرة بموضعها

التعديل (يكتب ملفاً جديداً، والأصل لا يُمس):
    python3 ar_docx.py proof   in.docx out.docx [--highlight]      إصلاح آمن مع بقاء التنسيق
    python3 ar_docx.py replace in.docx out.docx --map "قديم=جديد" [--map ...] [--highlight]
    python3 ar_docx.py set     in.docx out.docx --para 5 --text "نص جديد"
    python3 ar_docx.py insert  in.docx out.docx --after 5 --text "فقرة" [--style "Heading 2"]
    python3 ar_docx.py delete  in.docx out.docx --para 7 [--para 9]
    python3 ar_docx.py rtl     in.docx out.docx [--font "Arial"] [--size 13]   اتجاه وخط عربي لكل الملف
    python3 ar_docx.py meta    in.docx out.docx --title "..." --author "..."

الإنشاء:
    python3 ar_docx.py build input.md out.docx [--title T] [--font Arial] [--size 13] [--logo logo.png]
        صيغة الإدخال: # ## ### عناوين، فقرات، - نقاط، 1. ترقيم، > اقتباس،
        | جدول |، ![](صورة.png)، <<< صفحة جديدة، **عريض** داخل السطر.

التحويل:
    python3 ar_docx.py to-pdf in.docx [outdir]          عبر LibreOffice
    python3 ar_docx.py from-pdf in.pdf out.docx         PDF إلى وورد قابل للتعديل

أرقام الفقرات من 1 كما يطبعها read، وتشمل الفقرات الفارغة. فقرات الجداول
تُعرض بموضعها (ج1 ص2 ع3) وتُفحص وتُصلح مع proof و replace.
"""
import argparse
import os
import warnings
warnings.filterwarnings("ignore")
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def _need(mod, pkg):
    try:
        return __import__(mod)
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", pkg,
                        "--break-system-packages", "-q"], check=False)
        return __import__(mod)


_need("docx", "python-docx")
import ar_lint                                           # noqa: E402
from docx import Document                                # noqa: E402
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_COLOR_INDEX, WD_BREAK  # noqa: E402
from docx.oxml import OxmlElement                        # noqa: E402
from docx.oxml.ns import qn                              # noqa: E402
from docx.shared import Pt, Mm, RGBColor                 # noqa: E402

AR_RE = re.compile(r"[؀-ۿ]")


# ---------------------------------------------------------------- أدوات

def iter_paragraphs(doc):
    """كل فقرات الملف بالترتيب: المتن ثم الجداول، مع وسم الموضع."""
    for i, p in enumerate(doc.paragraphs, 1):
        yield f"ف{i}", p
    for ti, t in enumerate(doc.tables, 1):
        for ri, row in enumerate(t.rows, 1):
            seen = set()
            for ci, cell in enumerate(row.cells, 1):
                if id(cell._tc) in seen:
                    continue
                seen.add(id(cell._tc))
                for pi, p in enumerate(cell.paragraphs, 1):
                    yield f"ج{ti} ص{ri} ع{ci}" + (f" ف{pi}" if len(cell.paragraphs) > 1 else ""), p
    for si, s in enumerate(doc.sections, 1):
        for part, name in ((s.header, "ترويسة"), (s.footer, "تذييل")):
            if part is None or part.is_linked_to_previous:
                continue
            for pi, p in enumerate(part.paragraphs, 1):
                if p.text.strip():
                    yield f"{name}{si} ف{pi}", p


def set_rtl_paragraph(p, align=True):
    pPr = p._p.get_or_add_pPr()
    if pPr.find(qn("w:bidi")) is None:
        pPr.append(OxmlElement("w:bidi"))
    # في الفقرة ثنائية الاتجاه يكون البدء من اليمين تلقائياً، و"right" قد تُقرأ
    # يساراً في بعض البرامج. لذلك تُزال المحاذاة اليسرى ولا تُفرض اليمنى.
    if align and p.alignment in (WD_ALIGN_PARAGRAPH.LEFT, WD_ALIGN_PARAGRAPH.RIGHT):
        p.alignment = None


def set_run_font(run, font=None, size=None, rtl=True):
    rPr = run._r.get_or_add_rPr()
    if rtl and rPr.find(qn("w:rtl")) is None and AR_RE.search(run.text or ""):
        rPr.append(OxmlElement("w:rtl"))
    if font:
        run.font.name = font
        rFonts = rPr.find(qn("w:rFonts"))
        if rFonts is None:
            rFonts = OxmlElement("w:rFonts")
            rPr.insert(0, rFonts)
        for k in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
            rFonts.set(qn(k), font)
    if size:
        run.font.size = Pt(size)
        szCs = rPr.find(qn("w:szCs"))
        if szCs is None:
            szCs = OxmlElement("w:szCs")
            rPr.append(szCs)
        szCs.set(qn("w:val"), str(int(size * 2)))


def fix_text(s):
    """الإصلاح الآمن لنص داخل وورد: بلا فصل الإنجليزية في أسطر."""
    if not s or not AR_RE.search(s):
        return s
    lead = s[:len(s) - len(s.lstrip())]
    trail = s[len(s.rstrip()):]
    out = ar_lint.fix(s, en_lines=False).strip()
    return lead + out + trail if out else s


def fix_paragraph(p, highlight=False):
    """يصلح الفقرة مع بقاء تنسيق كل جزء. يعيد (قبل، بعد) أو None."""
    before = p.text
    if not AR_RE.search(before):
        return None
    changed = False
    for r in p.runs:
        new = fix_text(r.text)
        if new != r.text:
            r.text = new
            changed = True
            if highlight:
                r.font.highlight_color = WD_COLOR_INDEX.YELLOW
    # أخطاء تعبر حدود الأجزاء: أصلحها على مستوى الفقرة إن بقي فرق
    target = fix_text(p.text)
    if target != p.text and p.runs:
        rebuild_runs(p, target, highlight)
        changed = True
    return (before, p.text) if changed and before != p.text else None


def rebuild_runs(p, new_text, highlight=False):
    """يكتب نصاً جديداً في الفقرة: يحافظ على تنسيق أول جزء ويحذف البقية."""
    runs = p.runs
    if not runs:
        p.add_run(new_text)
        return
    runs[0].text = new_text
    if highlight:
        runs[0].font.highlight_color = WD_COLOR_INDEX.YELLOW
    for r in runs[1:]:
        r._r.getparent().remove(r._r)


def replace_in_paragraph(p, old, new, highlight=False):
    if old not in p.text:
        return 0
    n = 0
    for r in p.runs:
        if old in r.text:
            n += r.text.count(old)
            r.text = r.text.replace(old, new)
            if highlight:
                r.font.highlight_color = WD_COLOR_INDEX.YELLOW
    if old in p.text:  # يعبر حدود الأجزاء
        n += p.text.count(old)
        rebuild_runs(p, p.text.replace(old, new), highlight)
    return n


def save(doc, out, src=None):
    if src and os.path.abspath(src) == os.path.abspath(out):
        sys.exit("لا يُكتب فوق الملف الأصلي. اختر اسماً جديداً.")
    doc.save(out)
    print(f"حُفظ: {out}")


def para_by_no(doc, n):
    ps = doc.paragraphs
    if not 1 <= n <= len(ps):
        sys.exit(f"لا توجد فقرة رقم {n}. عدد الفقرات {len(ps)}.")
    return ps[n - 1]


# ---------------------------------------------------------------- الأوامر

def cmd_read(a):
    doc = Document(a.input)
    n_words = 0
    for loc, p in iter_paragraphs(doc):
        t = p.text
        n_words += len(ar_lint.words(t))
        style = p.style.name if p.style is not None else ""
        tag = f" [{style}]" if style and style not in ("Normal", "عادي") else ""
        if t.strip() or a.all:
            print(f"{loc}{tag}: {t}")
    print(f"\n— الفقرات {len(doc.paragraphs)} · الجداول {len(doc.tables)} · الأقسام {len(doc.sections)}"
          f" · الصور {len(doc.inline_shapes)} · الكلمات {n_words}")


def cmd_check(a):
    doc = Document(a.input)
    total_err = total_warn = 0
    for loc, p in iter_paragraphs(doc):
        t = p.text
        if not AR_RE.search(t):
            continue
        r, _ = ar_lint.check(t, en_lines=False)
        if not r.items:
            continue
        for it in r.items:
            lvl = "✗" if it["level"] == "خطأ" else "·"
            at = f"  ⟵ {it['at']}" if "at" in it else ""
            print(f"{lvl} {loc} [{it['kind']}] {it['msg']}{at}")
        total_err += len(r.blocking)
        total_warn += len(r.warnings)
    print(f"\nالأخطاء المانعة {total_err} · التنبيهات {total_warn}")
    return 1 if total_err else 0


def cmd_proof(a):
    doc = Document(a.input)
    log = []
    for loc, p in iter_paragraphs(doc):
        res = fix_paragraph(p, a.highlight)
        if res:
            log.append((loc, *res))
    save(doc, a.output, a.input)
    for loc, b, f in log:
        print(f"{loc}: «{b.strip()[:70]}» ← «{f.strip()[:70]}»")
    print(f"فقرات معدّلة: {len(log)}")
    # ما بقي يحتاج إعادة كتابة (البصمات والنحو)
    rest = 0
    for loc, p in iter_paragraphs(doc):
        if AR_RE.search(p.text):
            r, _ = ar_lint.check(p.text, en_lines=False)
            rest += len(r.blocking)
    if rest:
        print(f"بقي {rest} خطأ يحتاج إعادة صياغة يدوية (بصمات أو نحو). شغّل check لرؤيتها.")


def cmd_replace(a):
    doc = Document(a.input)
    pairs = []
    for m in a.map or []:
        if "=" not in m:
            sys.exit(f"صيغة خاطئة: {m} (المطلوب قديم=جديد)")
        old, new = m.split("=", 1)
        pairs.append((old, new))
    counts = {o: 0 for o, _ in pairs}
    for _, p in iter_paragraphs(doc):
        for old, new in pairs:
            counts[old] += replace_in_paragraph(p, old, new, a.highlight)
    save(doc, a.output, a.input)
    for old, new in pairs:
        print(f"«{old}» ← «{new}»: {counts[old]} مرة")


def cmd_set(a):
    doc = Document(a.input)
    p = para_by_no(doc, a.para)
    before = p.text
    rebuild_runs(p, a.text)
    if AR_RE.search(a.text):
        set_rtl_paragraph(p)
    save(doc, a.output, a.input)
    print(f"ف{a.para}: «{before[:70]}» ← «{a.text[:70]}»")


def cmd_insert(a):
    doc = Document(a.input)
    anchor = para_by_no(doc, a.after) if a.after else None
    new_p = OxmlElement("w:p")
    if anchor is not None:
        anchor._p.addnext(new_p)
    else:
        doc.element.body.insert(0, new_p)
    from docx.text.paragraph import Paragraph
    p = Paragraph(new_p, (anchor or doc.paragraphs[0])._parent)
    if a.style:
        try:
            p.style = doc.styles[a.style]
        except KeyError:
            print(f"النمط {a.style} غير موجود في الملف، استُعمل النمط العادي.")
    run = p.add_run(a.text)
    if AR_RE.search(a.text):
        set_rtl_paragraph(p)
        set_run_font(run)
    save(doc, a.output, a.input)
    print(f"أُضيفت فقرة بعد ف{a.after or 0}")


def cmd_delete(a):
    doc = Document(a.input)
    targets = sorted(set(a.para), reverse=True)
    ps = doc.paragraphs
    for n in targets:
        if not 1 <= n <= len(ps):
            sys.exit(f"لا توجد فقرة رقم {n}.")
    for n in targets:
        el = ps[n - 1]._p
        el.getparent().remove(el)
    save(doc, a.output, a.input)
    print("حُذفت الفقرات: " + "، ".join(f"ف{n}" for n in sorted(targets)))


def cmd_rtl(a):
    doc = Document(a.input)
    n = 0
    for _, p in iter_paragraphs(doc):
        if AR_RE.search(p.text):
            set_rtl_paragraph(p)
            for r in p.runs:
                set_run_font(r, a.font, a.size)
            n += 1
    for s in doc.sections:
        sectPr = s._sectPr
        if sectPr.find(qn("w:bidi")) is None:
            sectPr.append(OxmlElement("w:bidi"))
    for t in doc.tables:
        tblPr = t._tbl.tblPr
        if tblPr.find(qn("w:bidiVisual")) is None:
            tblPr.append(OxmlElement("w:bidiVisual"))
    save(doc, a.output, a.input)
    print(f"فقرات عربية مضبوطة الاتجاه: {n} · جداول معكوسة الاتجاه: {len(doc.tables)}")


def cmd_meta(a):
    doc = Document(a.input)
    cp = doc.core_properties
    if a.title is not None:
        cp.title = a.title
    if a.author is not None:
        cp.author = a.author
        cp.last_modified_by = a.author
    if a.subject is not None:
        cp.subject = a.subject
    save(doc, a.output, a.input)


# ---------------------------------------------------------------- الإنشاء

INLINE_BOLD = re.compile(r"\*\*(.+?)\*\*")


def add_rich(p, text, font, size, bold=False, color=None):
    parts = INLINE_BOLD.split(text)
    for i, part in enumerate(parts):
        if not part:
            continue
        r = p.add_run(part)
        r.bold = bold or (i % 2 == 1)
        if r.bold:
            r._r.get_or_add_rPr().append(OxmlElement("w:bCs"))
        if color:
            r.font.color.rgb = color
        set_run_font(r, font, size)


def style_table(t, font, size):
    t.style = "Table Grid"
    tblPr = t._tbl.tblPr
    tblPr.append(OxmlElement("w:bidiVisual"))
    for ri, row in enumerate(t.rows):
        for cell in row.cells:
            if ri == 0:
                shd = OxmlElement("w:shd")
                shd.set(qn("w:val"), "clear")
                shd.set(qn("w:fill"), "1B4F72")
                cell._tc.get_or_add_tcPr().append(shd)
            for p in cell.paragraphs:
                set_rtl_paragraph(p)
                for r in p.runs:
                    set_run_font(r, font, size - 1)
                    if ri == 0:
                        r.bold = True
                        r.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)


def cmd_build(a):
    doc = Document()
    doc.core_properties.author = a.author or ""
    font, size = a.font, a.size
    for s in doc.sections:
        s.page_height, s.page_width = Mm(297), Mm(210)
        s.left_margin = s.right_margin = Mm(22)
        s.top_margin = s.bottom_margin = Mm(20)
        s._sectPr.append(OxmlElement("w:bidi"))
    st = doc.styles["Normal"]
    st.font.name = font
    st.font.size = Pt(size)
    rpr = st.element.get_or_add_rPr()
    rf = rpr.find(qn("w:rFonts"))
    if rf is None:
        rf = OxmlElement("w:rFonts")
        rpr.insert(0, rf)
    for k in ("w:ascii", "w:hAnsi", "w:cs"):
        rf.set(qn(k), font)
    szcs = OxmlElement("w:szCs")
    szcs.set(qn("w:val"), str(int(size * 2)))
    rpr.append(szcs)
    st.paragraph_format.space_after = Pt(6)
    st.paragraph_format.line_spacing = 1.35

    base = os.path.dirname(os.path.abspath(a.input))
    if a.logo:
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.add_run().add_picture(a.logo, width=Mm(a.logo_width))
    if a.title:
        doc.core_properties.title = a.title
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        set_rtl_paragraph(p, align=False)
        add_rich(p, a.title, font, size + 9, bold=True, color=RGBColor(0x1B, 0x4F, 0x72))

    with open(a.input, encoding="utf-8") as f:
        lines = f.read().split("\n")
    i = 0
    sizes = {1: size + 7, 2: size + 4, 3: size + 2}
    while i < len(lines):
        ln = lines[i].rstrip()
        s_ = ln.strip()
        if not s_:
            i += 1
            continue
        if s_ == "<<<":
            doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
        elif s_ == "---":
            p = doc.add_paragraph()
            pPr = p._p.get_or_add_pPr()
            bdr = OxmlElement("w:pBdr")
            bot = OxmlElement("w:bottom")
            for k, v in (("w:val", "single"), ("w:sz", "6"), ("w:color", "C8CDD2"), ("w:space", "1")):
                bot.set(qn(k), v)
            bdr.append(bot)
            pPr.append(bdr)
        elif m := re.match(r"^(#{1,3})\s+(.*)", s_):
            lvl = len(m.group(1))
            p = doc.add_heading(level=lvl)
            set_rtl_paragraph(p)
            add_rich(p, m.group(2), font, sizes[lvl], bold=True, color=RGBColor(0x1B, 0x4F, 0x72))
        elif m := re.match(r"^!\[[^\]]*\]\(([^)]+)\)", s_):
            path = m.group(1) if os.path.isabs(m.group(1)) else os.path.join(base, m.group(1))
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            if os.path.exists(path):
                p.add_run().add_picture(path, width=Mm(150))
            else:
                print(f"صورة غير موجودة: {path}")
        elif s_.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
                    rows.append(cells)
                i += 1
            ncol = max(len(r) for r in rows)
            t = doc.add_table(rows=len(rows), cols=ncol)
            for ri, r in enumerate(rows):
                for ci in range(ncol):
                    cp = t.cell(ri, ci).paragraphs[0]
                    add_rich(cp, r[ci] if ci < len(r) else "", font, size - 1)
            style_table(t, font, size)
            doc.add_paragraph()
            continue
        elif m := re.match(r"^[-*•]\s+(.*)", s_):
            p = doc.add_paragraph(style="List Bullet")
            set_rtl_paragraph(p)
            add_rich(p, m.group(1), font, size)
        elif m := re.match(r"^\d+[.)]\s+(.*)", s_):
            p = doc.add_paragraph(style="List Number")
            set_rtl_paragraph(p)
            add_rich(p, m.group(1), font, size)
        elif s_.startswith(">"):
            p = doc.add_paragraph()
            set_rtl_paragraph(p)
            p.paragraph_format.right_indent = Mm(8)
            add_rich(p, s_.lstrip("> "), font, size, color=RGBColor(0x55, 0x5B, 0x63))
        else:
            p = doc.add_paragraph()
            set_rtl_paragraph(p)
            p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
            add_rich(p, s_, font, size)
        i += 1

    if a.footer or not a.no_numbers:
        for s in doc.sections:
            fp = s.footer.paragraphs[0]
            fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
            set_rtl_paragraph(fp, align=False)
            if a.footer:
                add_rich(fp, a.footer + (" · " if not a.no_numbers else ""), font, size - 3,
                         color=RGBColor(0x6B, 0x70, 0x78))
            if not a.no_numbers:
                r = fp.add_run()
                for tag, txt in (("begin", None), (None, "PAGE"), ("end", None)):
                    if tag:
                        fc = OxmlElement("w:fldChar")
                        fc.set(qn("w:fldCharType"), tag)
                        r._r.append(fc)
                    else:
                        it = OxmlElement("w:instrText")
                        it.set(qn("xml:space"), "preserve")
                        it.text = txt
                        r._r.append(it)
                set_run_font(r, font, size - 3)
    save(doc, a.output)


# ---------------------------------------------------------------- التحويل

def soffice_convert(src, outdir, fmt):
    exe = shutil.which("soffice") or shutil.which("libreoffice")
    if not exe:
        sys.exit("LibreOffice غير متوفر للتحويل.")
    os.makedirs(outdir, exist_ok=True)
    subprocess.run([exe, "--headless", "--convert-to", fmt, "--outdir", outdir, src],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)
    out = os.path.join(outdir, os.path.splitext(os.path.basename(src))[0] + "." + fmt.split(":")[0])
    if not os.path.exists(out):
        sys.exit("فشل التحويل.")
    print(f"حُفظ: {out}")
    return out


def cmd_to_pdf(a):
    soffice_convert(a.input, a.outdir or os.path.dirname(os.path.abspath(a.input)), "pdf")


def cmd_from_pdf(a):
    _need("pdf2docx", "pdf2docx")
    import logging
    logging.disable(logging.WARNING)
    from pdf2docx import Converter
    cv = Converter(a.input)
    cv.convert(a.output)
    cv.close()
    # ضبط الاتجاه العربي بعد التحويل
    doc = Document(a.output)
    for _, p in iter_paragraphs(doc):
        if AR_RE.search(p.text):
            set_rtl_paragraph(p, align=False)
    doc.save(a.output)
    print(f"حُفظ: {a.output}")


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="وورد عربي: قراءة، فحص، إصلاح، تعديل، إنشاء، تحويل")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("read"); p.add_argument("input"); p.add_argument("--all", action="store_true")
    p = sub.add_parser("check"); p.add_argument("input")
    p = sub.add_parser("proof"); p.add_argument("input"); p.add_argument("output")
    p.add_argument("--highlight", action="store_true")
    p = sub.add_parser("replace"); p.add_argument("input"); p.add_argument("output")
    p.add_argument("--map", action="append"); p.add_argument("--highlight", action="store_true")
    p = sub.add_parser("set"); p.add_argument("input"); p.add_argument("output")
    p.add_argument("--para", type=int, required=True); p.add_argument("--text", required=True)
    p = sub.add_parser("insert"); p.add_argument("input"); p.add_argument("output")
    p.add_argument("--after", type=int, default=0); p.add_argument("--text", required=True)
    p.add_argument("--style")
    p = sub.add_parser("delete"); p.add_argument("input"); p.add_argument("output")
    p.add_argument("--para", type=int, action="append", required=True)
    p = sub.add_parser("rtl"); p.add_argument("input"); p.add_argument("output")
    p.add_argument("--font"); p.add_argument("--size", type=float)
    p = sub.add_parser("meta"); p.add_argument("input"); p.add_argument("output")
    p.add_argument("--title"); p.add_argument("--author"); p.add_argument("--subject")
    p = sub.add_parser("build"); p.add_argument("input"); p.add_argument("output")
    p.add_argument("--title"); p.add_argument("--font", default="Arial")
    p.add_argument("--size", type=float, default=13); p.add_argument("--logo")
    p.add_argument("--logo-width", type=float, default=35); p.add_argument("--footer")
    p.add_argument("--no-numbers", action="store_true"); p.add_argument("--author")
    p = sub.add_parser("to-pdf"); p.add_argument("input"); p.add_argument("outdir", nargs="?")
    p = sub.add_parser("from-pdf"); p.add_argument("input"); p.add_argument("output")

    a = ap.parse_args()
    fn = {"read": cmd_read, "check": cmd_check, "proof": cmd_proof, "replace": cmd_replace,
          "set": cmd_set, "insert": cmd_insert, "delete": cmd_delete, "rtl": cmd_rtl,
          "meta": cmd_meta, "build": cmd_build, "to-pdf": cmd_to_pdf, "from-pdf": cmd_from_pdf}[a.cmd]
    return fn(a) or 0


if __name__ == "__main__":
    sys.exit(main())
