#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pdf_tools.py — التحكم في ملفات PDF: صفحات، دمج، علامة مائية عربية، ترقيم،
نماذج، حماية، ضغط، فحص النص، وتحويل إلى وورد.

    python3 pdf_tools.py info     file.pdf
    python3 pdf_tools.py check    file.pdf [--pages 1-3]            فحص Arab Writer للنص بأرقام الصفحات
    python3 pdf_tools.py merge    out.pdf a.pdf b.pdf c.pdf         دمج بالترتيب
    python3 pdf_tools.py split    file.pdf outdir/ [--every 1]      تقسيم كل صفحة (أو كل N صفحات)
    python3 pdf_tools.py extract  file.pdf out.pdf --pages "1,3-5"  استخراج صفحات
    python3 pdf_tools.py delete   file.pdf out.pdf --pages "2,7"    حذف صفحات
    python3 pdf_tools.py reorder  file.pdf out.pdf --order "3,1,2"  إعادة ترتيب (الباقي يُلحق بترتيبه)
    python3 pdf_tools.py rotate   file.pdf out.pdf --pages all --deg 90
    python3 pdf_tools.py insert   file.pdf out.pdf --from other.pdf --after 2   إدراج ملف بعد صفحة
    python3 pdf_tools.py watermark file.pdf out.pdf --text "سري" [--opacity 0.12] [--size 60] [--angle 35]
    python3 pdf_tools.py stamp    file.pdf out.pdf --image logo.png [--pos tr|tl|br|bl|c] [--width 30] [--pages all]
    python3 pdf_tools.py number   file.pdf out.pdf [--start 1] [--fmt "صفحة {n} من {total}"] [--skip-first]
    python3 pdf_tools.py fields   file.pdf                          حقول النموذج
    python3 pdf_tools.py fill     file.pdf out.pdf --set "الاسم=تركي" [--set ...] [--flatten]
    python3 pdf_tools.py protect  file.pdf out.pdf --password P [--owner P2] [--no-print] [--no-copy]
    python3 pdf_tools.py unlock   file.pdf out.pdf --password P
    python3 pdf_tools.py compress file.pdf out.pdf
    python3 pdf_tools.py meta     file.pdf out.pdf --title "..." --author "..."
    python3 pdf_tools.py to-docx  file.pdf out.docx                 إلى وورد قابل للتعديل

أرقام الصفحات من 1. الملف الأصلي لا يُكتب فوقه.
"""
import argparse
import io
import os
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


_need("pypdf", "pypdf")
from pypdf import PdfReader, PdfWriter, Transformation   # noqa: E402

AR_RE = re.compile(r"[؀-ۿ]")


def pages_spec(spec, total):
    if not spec or spec in ("all", "الكل"):
        return list(range(total))
    out = []
    for part in str(spec).replace("،", ",").split(","):
        part = part.strip()
        if not part:
            continue
        if part in ("last", "الأخيرة"):
            out.append(total - 1)
            continue
        if "-" in part:
            a, b = part.split("-")
            a = int(a) if a else 1
            b = int(b) if b else total
            out.extend(range(a - 1, b))
        else:
            out.append(int(part) - 1)
    bad = [p + 1 for p in out if not 0 <= p < total]
    if bad:
        sys.exit(f"صفحات خارج الملف: {bad}. عدد الصفحات {total}.")
    return out


def reader(path, password=None):
    r = PdfReader(path)
    if r.is_encrypted:
        if not password or not r.decrypt(password):
            sys.exit("الملف محمي بكلمة مرور. استعمل unlock مع كلمة المرور الصحيحة.")
    return r


def write(w, out, src=None):
    if src and os.path.abspath(src) == os.path.abspath(out):
        sys.exit("لا يُكتب فوق الملف الأصلي. اختر اسماً جديداً.")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "wb") as f:
        w.write(f)
    print(f"حُفظ: {out} · {len(w.pages)} صفحة")


def overlay_pdf(width, height, draw):
    """يرسم طبقة بحجم الصفحة بـ reportlab ويعيدها صفحة pypdf."""
    from reportlab.pdfgen import canvas
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=(width, height))
    draw(c, width, height)
    c.save()
    buf.seek(0)
    return PdfReader(buf).pages[0]


def ar_font():
    """يسجّل خط Amiri ويعيد اسمه، ودالة تشكيل النص العربي."""
    import ar_pdf
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    reg, _ = ar_pdf.find_font("amiri")
    if "AW-Amiri" not in pdfmetrics.getRegisteredFontNames():
        pdfmetrics.registerFont(TTFont("AW-Amiri", reg))
    return "AW-Amiri", ar_pdf.shape


# ---------------------------------------------------------------- الأوامر

def cmd_info(a):
    r = PdfReader(a.input)
    enc = r.is_encrypted
    if enc and not r.decrypt(""):
        print(f"ملف محمي بكلمة مرور · الصفحات: غير معروفة قبل الفتح")
        return
    meta = r.metadata or {}
    sizes = {}
    for p in r.pages:
        w, h = float(p.mediabox.width), float(p.mediabox.height)
        key = f"{w * 0.3528:.0f}×{h * 0.3528:.0f} مم"
        sizes[key] = sizes.get(key, 0) + 1
    text_pages = sum(1 for p in r.pages[:min(5, len(r.pages))] if len((p.extract_text() or "").strip()) > 30)
    fields = r.get_fields() or {}
    print(f"الصفحات {len(r.pages)} · المقاسات {', '.join(f'{k} ({v})' for k, v in sizes.items())}")
    print(f"العنوان {meta.get('/Title', '—')} · المؤلف {meta.get('/Author', '—')}")
    print(f"محمي {'نعم' if enc else 'لا'} · حقول نموذج {len(fields)} · "
          f"{'نص قابل للاستخراج' if text_pages else 'ممسوح ضوئياً على الأغلب (لا نص)'}")
    print(f"الحجم {os.path.getsize(a.input) / 1024:.0f} ك.ب")


def cmd_check(a):
    import ar_lint
    r = reader(a.input, a.password)
    idx = pages_spec(a.pages, len(r.pages))
    err = warn = 0
    for i in idx:
        exe = shutil.which("pdftotext")
        if exe:
            t = subprocess.run([exe, "-layout", "-f", str(i + 1), "-l", str(i + 1), a.input, "-"],
                               capture_output=True, text=True).stdout
        else:
            t = r.pages[i].extract_text() or ""
        t = re.sub("[\u200e\u200f\u202a-\u202e\u2066-\u2069]", "", t)  # رموز الاتجاه من الاستخراج
        t = re.sub(r"[ \t]{2,}", " ", t)
        if not AR_RE.search(t):
            continue
        rep, _ = ar_lint.check(t, en_lines=False)
        for it in rep.items:
            if it["kind"] in ("مسافات", "إيقاع", "بنية", "تنسيق"):
                continue  # استخراج PDF يفسد المسافات والأسطر، فلا يُحكم عليها
            mark = "✗" if it["level"] == "خطأ" else "·"
            at = f"  ⟵ {it['at']}" if "at" in it else ""
            print(f"{mark} ص{i + 1} [{it['kind']}] {it['msg']}{at}")
            err += it["level"] == "خطأ"
            warn += it["level"] != "خطأ"
    print(f"\nالأخطاء {err} · التنبيهات {warn}")
    print("ملاحظة: ملف PDF لا يُصحَّح في مكانه. للتصحيح: to-docx ثم ar_docx.py proof ثم to-pdf.")


def cmd_merge(a):
    w = PdfWriter()
    for f in a.inputs:
        r = reader(f)
        for p in r.pages:
            w.add_page(p)
        print(f"+ {os.path.basename(f)}: {len(r.pages)} صفحة")
    write(w, a.output)


def cmd_split(a):
    r = reader(a.input, a.password)
    os.makedirs(a.outdir, exist_ok=True)
    stem = os.path.splitext(os.path.basename(a.input))[0]
    n = len(r.pages)
    for start in range(0, n, a.every):
        w = PdfWriter()
        for i in range(start, min(start + a.every, n)):
            w.add_page(r.pages[i])
        end = min(start + a.every, n)
        name = f"{stem}_{start + 1}" + (f"-{end}" if a.every > 1 else "") + ".pdf"
        with open(os.path.join(a.outdir, name), "wb") as f:
            w.write(f)
    print(f"حُفظ {(n + a.every - 1) // a.every} ملف في {a.outdir}")


def cmd_extract(a):
    r = reader(a.input, a.password)
    w = PdfWriter()
    for i in pages_spec(a.pages, len(r.pages)):
        w.add_page(r.pages[i])
    write(w, a.output, a.input)


def cmd_delete(a):
    r = reader(a.input, a.password)
    drop = set(pages_spec(a.pages, len(r.pages)))
    if len(drop) >= len(r.pages):
        sys.exit("لا تُحذف كل الصفحات.")
    w = PdfWriter()
    for i, p in enumerate(r.pages):
        if i not in drop:
            w.add_page(p)
    write(w, a.output, a.input)
    print("حُذفت: " + "، ".join(str(i + 1) for i in sorted(drop)))


def cmd_reorder(a):
    r = reader(a.input, a.password)
    order = pages_spec(a.order, len(r.pages))
    rest = [i for i in range(len(r.pages)) if i not in order]
    w = PdfWriter()
    for i in order + rest:
        w.add_page(r.pages[i])
    write(w, a.output, a.input)


def cmd_rotate(a):
    r = reader(a.input, a.password)
    sel = set(pages_spec(a.pages, len(r.pages)))
    w = PdfWriter()
    for i, p in enumerate(r.pages):
        if i in sel:
            p.rotate(a.deg)
        w.add_page(p)
    write(w, a.output, a.input)


def cmd_insert(a):
    r = reader(a.input, a.password)
    o = reader(a.src)
    if not 0 <= a.after <= len(r.pages):
        sys.exit(f"--after بين 0 و {len(r.pages)}")
    w = PdfWriter()
    for i, p in enumerate(r.pages[:a.after]):
        w.add_page(p)
    for p in o.pages:
        w.add_page(p)
    for p in r.pages[a.after:]:
        w.add_page(p)
    write(w, a.output, a.input)


def cmd_watermark(a):
    r = reader(a.input, a.password)
    sel = set(pages_spec(a.pages, len(r.pages)))
    font, shape = ar_font()
    w = PdfWriter()
    for i, p in enumerate(r.pages):
        if i in sel:
            W, H = float(p.mediabox.width), float(p.mediabox.height)

            def draw(c, W, H):
                c.saveState()
                c.setFillColorRGB(*a.rgb)
                c.setFillAlpha(a.opacity)
                c.translate(W / 2, H / 2)
                c.rotate(a.angle)
                c.setFont(font, a.size)
                c.drawCentredString(0, 0, shape(a.text))
                c.restoreState()
            p.merge_page(overlay_pdf(W, H, draw))
        w.add_page(p)
    write(w, a.output, a.input)


def cmd_stamp(a):
    from reportlab.lib.utils import ImageReader
    r = reader(a.input, a.password)
    sel = set(pages_spec(a.pages, len(r.pages)))
    img = ImageReader(a.image)
    iw, ih = img.getSize()
    w = PdfWriter()
    mm = 72 / 25.4
    for i, p in enumerate(r.pages):
        if i in sel:
            W, H = float(p.mediabox.width), float(p.mediabox.height)
            dw = a.width * mm
            dh = dw * ih / iw
            m = a.margin * mm
            x = {"tl": m, "bl": m, "tr": W - dw - m, "br": W - dw - m, "c": (W - dw) / 2}[a.pos]
            y = {"tl": H - dh - m, "tr": H - dh - m, "bl": m, "br": m, "c": (H - dh) / 2}[a.pos]

            def draw(c, W, H, x=x, y=y, dw=dw, dh=dh):
                c.setFillAlpha(a.opacity)
                c.drawImage(img, x, y, dw, dh, mask="auto")
            p.merge_page(overlay_pdf(W, H, draw))
        w.add_page(p)
    write(w, a.output, a.input)


def cmd_number(a):
    r = reader(a.input, a.password)
    font, shape = ar_font()
    total = len(r.pages)
    w = PdfWriter()
    for i, p in enumerate(r.pages):
        if not (a.skip_first and i == 0):
            W, H = float(p.mediabox.width), float(p.mediabox.height)
            n = i + a.start - (1 if a.skip_first else 0)
            label = a.fmt.format(n=n, total=total - (1 if a.skip_first else 0) + a.start - 1)

            def draw(c, W, H, label=label):
                c.setFont(font, a.size)
                c.setFillColorRGB(0.35, 0.37, 0.4)
                c.drawCentredString(W / 2, 22, shape(label))
            p.merge_page(overlay_pdf(W, H, draw))
        w.add_page(p)
    write(w, a.output, a.input)


def cmd_fields(a):
    r = reader(a.input, a.password)
    f = r.get_fields() or {}
    if not f:
        print("لا توجد حقول نموذج قابلة للتعبئة. لإضافة نص فوق ملف غير تفاعلي استعمل ar_pdf أو watermark.")
        return
    for name, fld in f.items():
        kind = {"/Tx": "نص", "/Btn": "اختيار", "/Ch": "قائمة", "/Sig": "توقيع"}.get(fld.get("/FT"), fld.get("/FT"))
        opts = fld.get("/_States_", "")
        print(f"{name} · {kind} · القيمة الحالية: {fld.get('/V', '')}" + (f" · الخيارات {list(opts)}" if opts else ""))


def cmd_fill(a):
    r = reader(a.input, a.password)
    w = PdfWriter(clone_from=r)
    vals = dict(s.split("=", 1) for s in a.set)
    known = set((r.get_fields() or {}).keys())
    missing = [k for k in vals if k not in known]
    if missing:
        sys.exit(f"حقول غير موجودة: {missing}. شغّل fields لرؤية الأسماء.")
    for page in w.pages:
        if a.flatten:
            w.update_page_form_field_values(page, vals, auto_regenerate=False, flatten=True)
        else:
            w.update_page_form_field_values(page, vals, auto_regenerate=False)
    if a.flatten:
        w.remove_annotations(subtypes="/Widget")
    else:
        w.set_need_appearances_writer(True)
    write(w, a.output, a.input)
    print("عُبّئت: " + "، ".join(f"{k}={v}" for k, v in vals.items()))
    if any(AR_RE.search(v) for v in vals.values()):
        print("تنبيه: عرض العربي داخل الحقول يعتمد على خط النموذج. افحص الملف بصرياً.")


def cmd_protect(a):
    r = reader(a.input)
    w = PdfWriter(clone_from=r)
    from pypdf.constants import UserAccessPermissions as P
    perms = P.all()
    if a.no_print:
        perms &= ~P.PRINT & ~P.PRINT_TO_REPRESENTATION
    if a.no_copy:
        perms &= ~P.EXTRACT & ~P.EXTRACT_TEXT_AND_GRAPHICS
    w.encrypt(user_password=a.password, owner_password=a.owner or a.password,
              algorithm="AES-256", permissions_flag=perms)
    write(w, a.output, a.input)


def cmd_unlock(a):
    r = reader(a.input, a.password)
    w = PdfWriter(clone_from=r)
    write(w, a.output, a.input)


def cmd_compress(a):
    before = os.path.getsize(a.input)
    if shutil.which("qpdf"):
        subprocess.run(["qpdf", "--object-streams=generate", "--compress-streams=y",
                        "--recompress-flate", "--compression-level=9", a.input, a.output], check=False)
    else:
        r = reader(a.input)
        w = PdfWriter(clone_from=r)
        for p in w.pages:
            p.compress_content_streams()
        write(w, a.output, a.input)
    after = os.path.getsize(a.output)
    print(f"حُفظ: {a.output} · {before / 1024:.0f} ← {after / 1024:.0f} ك.ب ({100 - after * 100 // max(before, 1)}% أصغر)")
    if after >= before * 0.95:
        print("الملف مضغوط أصلاً أو صوره عالية الدقة. لتصغير أكبر: img_pdf.py to-img ثم to-pdf بجودة أقل.")


def cmd_meta(a):
    r = reader(a.input, a.password)
    w = PdfWriter(clone_from=r)
    md = {}
    if a.title:
        md["/Title"] = a.title
    if a.author:
        md["/Author"] = a.author
    if a.subject:
        md["/Subject"] = a.subject
    w.add_metadata(md)
    write(w, a.output, a.input)


def cmd_to_docx(a):
    subprocess.run([sys.executable, os.path.join(HERE, "ar_docx.py"), "from-pdf", a.input, a.output], check=True)


# ---------------------------------------------------------------- main

def hexrgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) / 255 for i in (0, 2, 4))


def main():
    ap = argparse.ArgumentParser(description="أدوات PDF")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def io_(n):
        p = sub.add_parser(n)
        p.add_argument("input")
        p.add_argument("output")
        p.add_argument("--password")
        return p

    p = sub.add_parser("info"); p.add_argument("input")
    p = sub.add_parser("check"); p.add_argument("input"); p.add_argument("--pages", default="all")
    p.add_argument("--password")
    p = sub.add_parser("merge"); p.add_argument("output"); p.add_argument("inputs", nargs="+")
    p = sub.add_parser("split"); p.add_argument("input"); p.add_argument("outdir")
    p.add_argument("--every", type=int, default=1); p.add_argument("--password")
    p = io_("extract"); p.add_argument("--pages", required=True)
    p = io_("delete"); p.add_argument("--pages", required=True)
    p = io_("reorder"); p.add_argument("--order", required=True)
    p = io_("rotate"); p.add_argument("--pages", default="all"); p.add_argument("--deg", type=int, default=90)
    p = io_("insert"); p.add_argument("--from", dest="src", required=True); p.add_argument("--after", type=int, required=True)
    p = io_("watermark"); p.add_argument("--text", required=True); p.add_argument("--opacity", type=float, default=0.12)
    p.add_argument("--size", type=float, default=64); p.add_argument("--angle", type=float, default=35)
    p.add_argument("--color", default="1B4F72"); p.add_argument("--pages", default="all")
    p = io_("stamp"); p.add_argument("--image", required=True); p.add_argument("--pos", default="tr",
                                                                              choices=["tl", "tr", "bl", "br", "c"])
    p.add_argument("--width", type=float, default=30); p.add_argument("--margin", type=float, default=10)
    p.add_argument("--opacity", type=float, default=1.0); p.add_argument("--pages", default="all")
    p = io_("number"); p.add_argument("--start", type=int, default=1)
    p.add_argument("--fmt", default="{n}"); p.add_argument("--size", type=float, default=10)
    p.add_argument("--skip-first", action="store_true")
    p = sub.add_parser("fields"); p.add_argument("input"); p.add_argument("--password")
    p = io_("fill"); p.add_argument("--set", action="append", required=True)
    p.add_argument("--flatten", action="store_true")
    p = io_("protect"); p.add_argument("--owner"); p.add_argument("--no-print", action="store_true")
    p.add_argument("--no-copy", action="store_true")
    io_("unlock")
    io_("compress")
    p = io_("meta"); p.add_argument("--title"); p.add_argument("--author"); p.add_argument("--subject")
    io_("to-docx")

    a = ap.parse_args()
    if a.cmd == "protect" and not a.password:
        sys.exit("--password مطلوبة.")
    if a.cmd == "watermark":
        a.rgb = hexrgb(a.color)
    fn = globals()["cmd_" + a.cmd.replace("-", "_")]
    return fn(a) or 0


if __name__ == "__main__":
    sys.exit(main())
