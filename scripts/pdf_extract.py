#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pdf_extract.py — يستخرج نص ملف PDF صفحةً صفحة، مع الجداول، لأجل التلخيص.

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
import subprocess
import sys


def page_range(spec, total):
    if not spec:
        return list(range(total))
    out = []
    for part in spec.split(","):
        if "-" in part:
            a, b = part.split("-")
            out += list(range(int(a) - 1, min(int(b), total)))
        else:
            out.append(int(part) - 1)
    return [p for p in out if 0 <= p < total]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf")
    ap.add_argument("--pages", default="")
    ap.add_argument("--tables", action="store_true")
    ap.add_argument("--info", action="store_true")
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    try:
        import pdfplumber
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "pdfplumber",
                        "--break-system-packages", "-q"], check=False)
        import pdfplumber

    chunks = []
    with pdfplumber.open(a.pdf) as pdf:
        total = len(pdf.pages)
        idx = page_range(a.pages, total)
        words = 0
        for i in idx:
            page = pdf.pages[i]
            txt = page.extract_text() or ""
            words += len(txt.split())
            if a.tables:
                for t in page.extract_tables():
                    rows = ["| " + " | ".join((c or "").strip() for c in r) + " |"
                            for r in t if any(r)]
                    if rows:
                        chunks.append("[جدول صفحة %d]\n%s" % (i + 1, "\n".join(rows)))
            else:
                chunks.append("=== صفحة %d ===\n%s" % (i + 1, txt.strip()))

    if a.info:
        scanned = words < 12 * max(len(idx), 1)
        print("الصفحات: %d" % total)
        print("الكلمات المستخرجة: %d" % words)
        print("ممسوح ضوئياً: %s" % ("نعم، استخدم التحويل إلى صور" if scanned else "لا"))
        return

    text = "\n\n".join(chunks)
    text = re.sub(r"\n{3,}", "\n\n", text)
    if a.out:
        open(a.out, "w", encoding="utf-8").write(text)
        print(os.path.abspath(a.out))
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
