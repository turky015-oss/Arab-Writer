#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pdf_extract.py — يستخرج نص ملف PDF صفحةً صفحة، مع الجداول، لأجل التلخيص والفحص.

الاستخراج العربي يمر بدالة واحدة (extract_pages) يستعملها التلخيص و pdf_tools.py check:
1. pdftotext إن وُجد، ثم pypdf، ثم pdfplumber.
2. حذف رموز الاتجاه والتطويل، NFKC، وإعادة أشكال العرض (ﺍﻓﻀﻞ) إلى الحروف المنطقية (افضل).
3. كشف الترتيب البصري (الحروف مقلوبة) وإعادته إلى الترتيب المنطقي.

الاستعمال:
    python3 pdf_extract.py file.pdf                 نص كامل مقسّم بالصفحات
    python3 pdf_extract.py file.pdf --tables        الجداول فقط
    python3 pdf_extract.py file.pdf --pages 1-5     صفحات محددة
    python3 pdf_extract.py file.pdf --out out.txt   حفظ في ملف
    python3 pdf_extract.py file.pdf --info          عدد الصفحات والكلمات وهل الملف ممسوح ضوئياً

الملف الممسوح ضوئياً (بلا طبقة نص) يُكتشف تلقائياً، وعندها استخدم:
    pdftoppm -png -r 200 file.pdf page   ثم اقرأ الصور بصرياً.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ar_lint  # noqa: E402

COMMON = {"في", "من", "على", "إلى", "الى", "أن", "ان", "عن", "مع", "هذا", "هذه", "التي",
          "الذي", "كان", "كل", "بين", "قد", "لا", "هو", "هي", "ثم", "أو", "او", "إن", "لم",
          "لن", "ذلك", "عند", "بعد", "قبل", "كما", "أي", "حتى"}
TOK = re.compile(rf"[{ar_lint.AR_LET}]+")
LTR_RUN = re.compile(r"[A-Za-z0-9][A-Za-z0-9.,%:/+_@#&'-]*")


def page_range(spec, total):
    if not spec:
        return list(range(total))
    out = []
    for part in spec.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-")
            out += list(range(int(a) - 1, min(int(b), total)))
        elif part:
            out.append(int(part) - 1)
    return [p for p in out if 0 <= p < total]


def _visual_score(text):
    """(كلمات شائعة بالترتيب المنطقي، كلمات شائعة مقلوبة)."""
    toks = TOK.findall(text)
    return sum(t in COMMON for t in toks), sum(t[::-1] in COMMON for t in toks)


def _reverse_line(ln):
    rev = ln[::-1]
    # الأرقام واللاتيني تبقى من اليسار لليمين داخل السطر المقلوب
    return LTR_RUN.sub(lambda m: m.group(0)[::-1], rev)


def clean_arabic(text):
    """تطبيع واحد قبل أي تلخيص أو فحص."""
    # رموز التضمين حول الأرقام واللاتيني تقوم مقام المسافة في الاستخراج
    t = re.sub("[\u202a-\u202e\u2066-\u2069]", " ", text)
    fwd, rev = _visual_score(ar_lint.normalize(t)[0])
    if rev > fwd:
        # يُقلب قبل NFKC: الحرف المركّب (ﻷ) يتفكك بالترتيب المنطقي، فقلبه بعد التفكيك يفسده
        t = "\n".join(_reverse_line(ln) for ln in t.split("\n"))
    t, _ = ar_lint.normalize(t, keep_diac=True, full=True)
    t = re.sub(r"[ \t]+", " ", t)
    t = re.sub(r" +([.،؛؟!:,])", r"\1", t)
    t = re.sub(r" *\n *", "\n", t)
    return re.sub(r"\n{3,}", "\n\n", t).strip()


def _raw_pages(path, idx, password=None):
    exe = shutil.which("pdftotext")
    if exe and not password:
        out = []
        for i in idx:
            r = subprocess.run([exe, "-enc", "UTF-8", "-f", str(i + 1), "-l", str(i + 1), path, "-"],
                               capture_output=True, text=True)
            if r.returncode != 0:
                break
            out.append(r.stdout)
        else:
            return out
    try:
        from pypdf import PdfReader
        rd = PdfReader(path)
        if rd.is_encrypted:
            rd.decrypt(password or "")
        return [rd.pages[i].extract_text() or "" for i in idx]
    except Exception:
        import pdfplumber
        with pdfplumber.open(path, password=password or None) as pdf:
            return [pdf.pages[i].extract_text() or "" for i in idx]


def page_count(path, password=None):
    from pypdf import PdfReader
    rd = PdfReader(path)
    if rd.is_encrypted:
        rd.decrypt(password or "")
    return len(rd.pages)


def extract_pages(path, pages="", password=None):
    """[(رقم الصفحة من 1، النص المطبَّع بالترتيب المنطقي)] — للتلخيص والفحص معاً."""
    idx = page_range(pages, page_count(path, password)) if isinstance(pages, str) else list(pages)
    return [(i + 1, clean_arabic(t)) for i, t in zip(idx, _raw_pages(path, idx, password))]


def tables(path, idx):
    try:
        import pdfplumber
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "pdfplumber",
                        "--break-system-packages", "-q"], check=False)
        import pdfplumber
    chunks = []
    with pdfplumber.open(path) as pdf:
        for i in idx:
            for t in pdf.pages[i].extract_tables():
                rows = ["| " + " | ".join(clean_arabic(c or "") for c in r) + " |" for r in t if any(r)]
                if rows:
                    chunks.append("[جدول صفحة %d]\n%s" % (i + 1, "\n".join(rows)))
    return chunks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("--pages", default="")
    ap.add_argument("--tables", action="store_true")
    ap.add_argument("--info", action="store_true")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    total = page_count(a.pdf)
    idx = page_range(a.pages, total)
    if a.tables:
        text = "\n\n".join(tables(a.pdf, idx))
    else:
        pages = extract_pages(a.pdf, idx)
        if a.info:
            words = sum(len(t.split()) for _, t in pages)
            scanned = words < 12 * max(len(idx), 1)
            print("الصفحات: %d" % total)
            print("الكلمات المستخرجة: %d" % words)
            print("ممسوح ضوئياً: %s" % ("نعم، استخدم التحويل إلى صور" if scanned else "لا"))
            return
        text = "\n\n".join("=== صفحة %d ===\n%s" % (n, t) for n, t in pages)

    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write(text)
        print(os.path.abspath(a.out))
    else:
        sys.stdout.write(text + "\n")


if __name__ == "__main__":
    main()
