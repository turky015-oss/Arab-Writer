#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ar_pdf.py — يبني ملف PDF عربي سليم الاتجاه من نص ماركداون مبسّط.

الاستعمال:
    python3 ar_pdf.py input.md output.pdf --title "عنوان" --logo logo.png

الخيارات:
    --title T        عنوان يظهر في ترويسة الصفحات وفي بيانات الملف
    --subtitle T     سطر تحت العنوان في صفحة الغلاف
    --logo PATH      صورة أو شعار (png/jpg) يوضع أعلى الصفحة الأولى
    --logo-width N   عرض الشعار بالمليمتر (افتراضي 32)
    --cover          صفحة غلاف مستقلة للعنوان والشعار
    --font NAME      amiri (افتراضي) أو مسار ملف خط ttf يدعم أشكال العرض العربية
    --size N         حجم النص الأساسي (افتراضي 11.5)
    --footer T       نص ثابت أسفل كل صفحة
    --ltr            نص إنجليزي: تخطيط من اليسار لليمين
    --no-numbers     بلا ترقيم صفحات

صيغة الإدخال:
    # عنوان رئيسي        ## عنوان فرعي        ### عنوان صغير
    فقرة عادية
    - نقطة
    1. نقطة مرقّمة
    > اقتباس
    | عمود | عمود |      (صف ثانٍ من الشرطات يُهمَل)
    ---                   خط فاصل
    ![](path/img.png)     صورة
    <<<                   صفحة جديدة
"""
import argparse
import os
import re
import subprocess
import sys


def _ensure(mod, pkg):
    try:
        return __import__(mod)
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", pkg,
                        "--break-system-packages", "-q"], check=False)
        return __import__(mod)


_ensure("arabic_reshaper", "arabic-reshaper")
_ensure("bidi", "python-bidi")

import arabic_reshaper                                  # noqa: E402
from bidi.algorithm import get_display                  # noqa: E402
from reportlab.lib.pagesizes import A4                  # noqa: E402
from reportlab.lib.units import mm                      # noqa: E402
from reportlab.lib.utils import ImageReader             # noqa: E402
from reportlab.pdfbase import pdfmetrics                # noqa: E402
from reportlab.pdfbase.ttfonts import TTFont            # noqa: E402
from reportlab.pdfgen import canvas as pdfcanvas        # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIRS = [
    os.path.join(HERE, "..", "assets", "fonts"),
    os.path.join(HERE, "fonts"),
    "/usr/share/fonts/truetype",
]
INK = (0.09, 0.09, 0.11)
MUTED = (0.42, 0.44, 0.48)
RULE = (0.85, 0.86, 0.88)
ACCENT = (0.10, 0.38, 0.55)
BAND = (0.955, 0.957, 0.965)

_reshaper = arabic_reshaper.ArabicReshaper(
    configuration={"delete_harakat": False, "support_ligatures": True})


def shape(text, rtl=True):
    """يحوّل النص المنطقي إلى نص معروض جاهزاً للرسم."""
    if not text:
        return ""
    if not rtl and not re.search(r"[\u0600-\u06FF]", text):
        return text
    return get_display(_reshaper.reshape(text), base_dir="R" if rtl else "L")


def find_font(name):
    if os.path.exists(name):
        return [name, name]
    targets = {
        "amiri": ("Amiri-Regular.ttf", "Amiri-Bold.ttf"),
        "tajawal": ("Tajawal-Regular.ttf", "Tajawal-Bold.ttf"),
    }.get(name, ("Amiri-Regular.ttf", "Amiri-Bold.ttf"))
    found = []
    for target in targets:
        hit = None
        for d in FONT_DIRS:
            for root, _, files in os.walk(os.path.abspath(d)) if os.path.isdir(d) else []:
                if target in files:
                    hit = os.path.join(root, target)
                    break
            if hit:
                break
        found.append(hit)
    if not all(found):
        if name != "amiri":
            sys.stderr.write("لم يُعثر على الخط %s. التحويل إلى Amiri.\n" % name)
            return find_font("amiri")
        sys.exit("ضع ملفي Amiri-Regular.ttf و Amiri-Bold.ttf في assets/fonts.")
    return found


def covers_arabic(path):
    """يتحقق أن الخط يحوي أشكال العرض العربية (Presentation Forms-B)."""
    try:
        face = TTFont("probe", path).face
        cmap = face.charToGlyph
        return all(cmap.get(cp) for cp in (0xFE8D, 0xFEE0, 0xFEDF, 0xFE91))
    except Exception:
        return True


class Doc:
    def __init__(self, out, args):
        self.args = args
        self.rtl = not args.ltr
        reg, bold = find_font(args.font)
        if not covers_arabic(reg):
            sys.stderr.write(
                "الخط %s لا يغطي أشكال العرض العربية. التحويل إلى Amiri.\n"
                % os.path.basename(reg))
            reg, bold = find_font("amiri")
        pdfmetrics.registerFont(TTFont("AR", reg))
        pdfmetrics.registerFont(TTFont("AR-B", bold))
        self.W, self.H = A4
        self.ml = self.mr = 20 * mm
        self.mt = 22 * mm
        self.mb = 20 * mm
        self.c = pdfcanvas.Canvas(out, pagesize=A4)
        self.c.setTitle(args.title or "")
        self.c.setAuthor(args.author or "")
        self.size = args.size
        self.lead = args.size * 1.85
        self.y = self.H - self.mt
        self.page = 1
        self.first_body_page = True

    # ---------- أدوات القياس ----------
    def width(self, txt, font, size):
        return pdfmetrics.stringWidth(shape(txt, self.rtl), font, size)

    def wrap(self, text, font, size, maxw):
        words, lines, cur = text.split(), [], ""
        for w in words:
            trial = (cur + " " + w).strip()
            if self.width(trial, font, size) <= maxw or not cur:
                cur = trial
            else:
                lines.append(cur)
                cur = w
        if cur:
            lines.append(cur)
        return lines or [""]

    # ---------- الصفحة ----------
    def avail(self):
        return self.W - self.ml - self.mr

    def need(self, h):
        if self.y - h < self.mb:
            self.new_page()

    def new_page(self):
        self.footer()
        self.c.showPage()
        self.page += 1
        self.y = self.H - self.mt

    def footer(self):
        c = self.c
        c.setFont("AR", 8.5)
        c.setFillColorRGB(*MUTED)
        base = self.mb - 8 * mm
        if self.args.footer:
            t = shape(self.args.footer, self.rtl)
            if self.rtl:
                c.drawRightString(self.W - self.mr, base, t)
            else:
                c.drawString(self.ml, base, t)
        if not self.args.no_numbers:
            n = shape(str(self.page), self.rtl)
            if self.rtl:
                c.drawString(self.ml, base, n)
            else:
                c.drawRightString(self.W - self.mr, base, n)
        c.setFillColorRGB(*INK)

    def text_line(self, txt, font, size, indent=0, color=INK):
        c = self.c
        c.setFont(font, size)
        c.setFillColorRGB(*color)
        t = shape(txt, self.rtl)
        if self.rtl:
            c.drawRightString(self.W - self.mr - indent, self.y, t)
        else:
            c.drawString(self.ml + indent, self.y, t)
        c.setFillColorRGB(*INK)

    # ---------- العناصر ----------
    def cover(self, title, subtitle, logo):
        c = self.c
        y = self.H * 0.62
        if logo and os.path.exists(logo):
            y = self.draw_image(logo, y, self.args.logo_width * mm, center=True)
            y -= 16 * mm
        c.setFont("AR-B", 26)
        for line in self.wrap(title, "AR-B", 26, self.avail()):
            c.setFillColorRGB(*INK)
            c.drawCentredString(self.W / 2, y, shape(line, self.rtl))
            y -= 26 * 1.6
        if subtitle:
            c.setFont("AR", 13)
            c.setFillColorRGB(*MUTED)
            for line in self.wrap(subtitle, "AR", 13, self.avail() * 0.8):
                c.drawCentredString(self.W / 2, y, shape(line, self.rtl))
                y -= 13 * 1.7
        c.setStrokeColorRGB(*ACCENT)
        c.setLineWidth(2)
        c.line(self.W / 2 - 18 * mm, y - 6 * mm, self.W / 2 + 18 * mm, y - 6 * mm)
        c.setFillColorRGB(*INK)
        self.c.showPage()
        self.page += 1
        self.y = self.H - self.mt

    def draw_image(self, path, y, target_w, center=False):
        img = ImageReader(path)
        iw, ih = img.getSize()
        w = min(target_w, self.avail())
        h = w * ih / iw
        if y - h < self.mb:
            self.new_page()
            y = self.y
        if center:
            x = (self.W - w) / 2
        else:
            x = (self.W - self.mr - w) if self.rtl else self.ml
        self.c.drawImage(img, x, y - h, width=w, height=h,
                         mask="auto", preserveAspectRatio=True)
        return y - h

    def heading(self, text, level):
        sizes = {1: self.size + 8, 2: self.size + 3.5, 3: self.size + 1}
        size = sizes[level]
        gap = {1: 9 * mm, 2: 7 * mm, 3: 5 * mm}[level]
        lines = self.wrap(text, "AR-B", size, self.avail())
        self.need(gap + len(lines) * size * 1.6 + 4 * mm)
        self.y -= gap
        for ln in lines:
            self.text_line(ln, "AR-B", size, color=INK if level > 1 else ACCENT)
            self.y -= size * 1.6
        if level == 1:
            self.c.setStrokeColorRGB(*RULE)
            self.c.setLineWidth(0.8)
            self.c.line(self.ml, self.y + 4 * mm, self.W - self.mr, self.y + 4 * mm)
            self.y -= 2 * mm

    def paragraph(self, text, indent=0, size=None, color=INK, font="AR"):
        size = size or self.size
        lines = self.wrap(text, font, size, self.avail() - indent)
        for ln in lines:
            self.need(self.lead)
            self.text_line(ln, font, size, indent, color)
            self.y -= self.lead
        self.y -= 1.5 * mm

    def bullet(self, text, marker="•"):
        indent = 7 * mm
        lines = self.wrap(text, "AR", self.size, self.avail() - indent)
        for i, ln in enumerate(lines):
            self.need(self.lead)
            if i == 0:
                self.text_line(marker, "AR", self.size, 0, ACCENT)
            self.text_line(ln, "AR", self.size, indent)
            self.y -= self.lead
        self.y -= 0.8 * mm

    def quote(self, text):
        indent = 6 * mm
        lines = self.wrap(text, "AR", self.size, self.avail() - indent - 4 * mm)
        top = self.y + self.size
        self.need(len(lines) * self.lead)
        for ln in lines:
            self.need(self.lead)
            self.text_line(ln, "AR", self.size, indent + 3 * mm, MUTED)
            self.y -= self.lead
        self.c.setStrokeColorRGB(*ACCENT)
        self.c.setLineWidth(2)
        x = self.W - self.mr - indent if self.rtl else self.ml + indent
        self.c.line(x, top, x, self.y + self.lead - 2)
        self.y -= 2 * mm

    def hr(self):
        self.need(6 * mm)
        self.y -= 3 * mm
        self.c.setStrokeColorRGB(*RULE)
        self.c.setLineWidth(0.7)
        self.c.line(self.ml, self.y, self.W - self.mr, self.y)
        self.y -= 4 * mm

    def table(self, rows):
        cols = max(len(r) for r in rows)
        rows = [r + [""] * (cols - len(r)) for r in rows]
        total = self.avail()
        raw = [max(self.width(r[i], "AR", self.size) for r in rows) + 8 * mm
               for i in range(cols)]
        scale = total / sum(raw)
        widths = [w * scale for w in raw]
        pad = 3 * mm
        for ri, row in enumerate(rows):
            font = "AR-B" if ri == 0 else "AR"
            cells = [self.wrap(row[i], font, self.size - 0.5, widths[i] - 2 * pad)
                     for i in range(cols)]
            h = max(len(c) for c in cells) * (self.size * 1.6) + 3 * mm
            self.need(h)
            top = self.y + self.size
            if ri == 0:
                self.c.setFillColorRGB(*BAND)
                self.c.rect(self.ml, top - h, total, h, stroke=0, fill=1)
                self.c.setFillColorRGB(*INK)
            x = self.W - self.mr if self.rtl else self.ml
            for i in range(cols):
                w = widths[i]
                cx = x - pad if self.rtl else x + pad
                yy = self.y
                for ln in cells[i]:
                    self.c.setFont(font, self.size - 0.5)
                    self.c.setFillColorRGB(*INK)
                    t = shape(ln, self.rtl)
                    if self.rtl:
                        self.c.drawRightString(cx, yy, t)
                    else:
                        self.c.drawString(cx, yy, t)
                    yy -= self.size * 1.6
                x = x - w if self.rtl else x + w
            self.c.setStrokeColorRGB(*RULE)
            self.c.setLineWidth(0.6)
            self.c.line(self.ml, top - h, self.W - self.mr, top - h)
            self.y = top - h - self.size + 2
        self.y -= 4 * mm


TABLE_SEP = re.compile(r"^\s*\|?[\s:\-|]+\|[\s:\-|]*$")


def parse(md, doc, base_dir):
    lines = md.replace("\r\n", "\n").split("\n")
    i, buf, table = 0, [], []

    def flush_par():
        if buf:
            doc.paragraph(" ".join(buf).strip())
            buf.clear()

    def flush_table():
        if table:
            doc.table([[c.strip() for c in r] for r in table])
            table.clear()

    while i < len(lines):
        ln = lines[i].rstrip()
        s = ln.strip()
        if s.startswith("|") and s.endswith("|") and s.count("|") >= 2:
            flush_par()
            if not TABLE_SEP.match(s):
                table.append([c for c in s.strip("|").split("|")])
            i += 1
            continue
        flush_table()
        if not s:
            flush_par()
        elif s == "<<<":
            flush_par()
            doc.new_page()
        elif re.match(r"^(-{3,}|_{3,}|\*{3,})$", s):
            flush_par()
            doc.hr()
        elif s.startswith("!["):
            flush_par()
            m = re.search(r"\((.+?)\)", s)
            if m:
                p = m.group(1)
                p = p if os.path.isabs(p) else os.path.join(base_dir, p)
                if os.path.exists(p):
                    doc.y = doc.draw_image(p, doc.y - 3 * mm, doc.avail() * 0.7)
                    doc.y -= 5 * mm
        elif s.startswith("#"):
            flush_par()
            level = min(len(s) - len(s.lstrip("#")), 3)
            doc.heading(s.lstrip("#").strip(), level)
        elif s.startswith(">"):
            flush_par()
            doc.quote(s.lstrip(">").strip())
        elif re.match(r"^[-*•]\s+", s):
            flush_par()
            doc.bullet(re.sub(r"^[-*•]\s+", "", s))
        elif re.match(r"^\d+[.)]\s+", s):
            flush_par()
            num = re.match(r"^(\d+)", s).group(1)
            doc.bullet(re.sub(r"^\d+[.)]\s+", "", s), marker=num + ".")
        else:
            buf.append(s.replace("**", "").replace("`", ""))
        i += 1
    flush_par()
    flush_table()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--title", default="")
    ap.add_argument("--subtitle", default="")
    ap.add_argument("--author", default="")
    ap.add_argument("--logo", default="")
    ap.add_argument("--logo-width", type=float, default=32)
    ap.add_argument("--cover", action="store_true")
    ap.add_argument("--font", default="amiri")
    ap.add_argument("--size", type=float, default=11.5)
    ap.add_argument("--footer", default="")
    ap.add_argument("--ltr", action="store_true")
    ap.add_argument("--no-numbers", action="store_true")
    a = ap.parse_args()

    md = open(a.input, encoding="utf-8").read() if os.path.exists(a.input) else a.input
    base_dir = os.path.dirname(os.path.abspath(a.input)) if os.path.exists(a.input) else os.getcwd()
    doc = Doc(a.output, a)

    if a.cover and (a.title or a.logo):
        doc.cover(a.title, a.subtitle, a.logo)
    elif a.logo and os.path.exists(a.logo):
        doc.y = doc.draw_image(a.logo, doc.y, a.logo_width * mm)
        doc.y -= 6 * mm
        if a.title:
            doc.heading(a.title, 1)
    elif a.title:
        doc.heading(a.title, 1)

    parse(md, doc, base_dir)
    doc.footer()
    doc.c.save()
    print(a.output)


if __name__ == "__main__":
    main()
