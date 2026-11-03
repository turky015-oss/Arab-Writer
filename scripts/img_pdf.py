#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
img_pdf.py — تحويل الصور إلى PDF والعكس.

صور إلى PDF:
    python3 img_pdf.py to-pdf out.pdf img1.jpg img2.png
    python3 img_pdf.py to-pdf out.pdf folder/            كل صور المجلد بالترتيب
    الخيارات: --fit a4|image (افتراضي a4)  --margin 10  --landscape  --quality 92

PDF إلى صور:
    python3 img_pdf.py to-img file.pdf outdir/
    الخيارات: --dpi 200  --fmt png|jpg  --pages 1-3  --single (صورة واحدة طويلة)
"""
import argparse
import os
import subprocess
import sys

EXT = (".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff", ".heic")


def _pil():
    try:
        from PIL import Image
        return Image
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "pillow",
                        "--break-system-packages", "-q"], check=False)
        from PIL import Image
        return Image


def collect(paths):
    files = []
    for p in paths:
        if os.path.isdir(p):
            files += [os.path.join(p, f) for f in sorted(os.listdir(p))
                      if f.lower().endswith(EXT)]
        elif p.lower().endswith(EXT):
            files.append(p)
    if not files:
        sys.exit("لا توجد صور صالحة في المسار المعطى.")
    return files


def to_pdf(a):
    Image = _pil()
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib.units import mm
    from reportlab.pdfgen import canvas as pdfcanvas

    files = collect(a.inputs)
    if a.fit == "image":
        pages = []
        for f in files:
            im = Image.open(f).convert("RGB")
            pages.append(im)
        pages[0].save(a.output, save_all=True, append_images=pages[1:],
                      resolution=a.dpi, quality=a.quality)
    else:
        size = landscape(A4) if a.landscape else A4
        c = pdfcanvas.Canvas(a.output, pagesize=size)
        W, H = size
        m = a.margin * mm
        for f in files:
            im = Image.open(f)
            if im.mode in ("RGBA", "P", "LA"):
                bg = Image.new("RGB", im.size, "white")
                bg.paste(im, mask=im.convert("RGBA").split()[-1])
                im = bg
            else:
                im = im.convert("RGB")
            iw, ih = im.size
            scale = min((W - 2 * m) / iw, (H - 2 * m) / ih)
            w, h = iw * scale, ih * scale
            tmp = os.path.join("/tmp", "_p_%d.jpg" % abs(hash(f)))
            im.save(tmp, "JPEG", quality=a.quality)
            c.drawImage(tmp, (W - w) / 2, (H - h) / 2, width=w, height=h)
            c.showPage()
            os.remove(tmp)
        c.save()
    print(os.path.abspath(a.output))


def to_img(a):
    os.makedirs(a.output, exist_ok=True)
    stem = os.path.join(a.output, os.path.splitext(os.path.basename(a.inputs[0]))[0])
    cmd = ["pdftoppm", "-r", str(a.dpi),
           "-png" if a.fmt == "png" else "-jpeg", a.inputs[0], stem]
    if a.pages:
        first, _, last = a.pages.partition("-")
        cmd[1:1] = ["-f", first, "-l", last or first]
    if subprocess.run(cmd).returncode != 0:
        sys.exit("فشل التحويل. تأكد من وجود poppler-utils.")
    made = sorted(f for f in os.listdir(a.output)
                  if f.startswith(os.path.basename(stem)))
    if a.single and len(made) > 1:
        Image = _pil()
        ims = [Image.open(os.path.join(a.output, f)) for f in made]
        w = max(i.width for i in ims)
        out = Image.new("RGB", (w, sum(i.height for i in ims)), "white")
        y = 0
        for i in ims:
            out.paste(i, (0, y))
            y += i.height
        path = os.path.join(a.output, "full.%s" % a.fmt)
        out.save(path)
        for f in made:
            os.remove(os.path.join(a.output, f))
        made = [os.path.basename(path)]
    for f in made:
        print(os.path.join(os.path.abspath(a.output), f))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["to-pdf", "to-img"])
    ap.add_argument("output")
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--fit", default="a4", choices=["a4", "image"])
    ap.add_argument("--margin", type=float, default=10)
    ap.add_argument("--landscape", action="store_true")
    ap.add_argument("--quality", type=int, default=92)
    ap.add_argument("--dpi", type=int, default=200)
    ap.add_argument("--fmt", default="png", choices=["png", "jpg"])
    ap.add_argument("--pages", default="")
    ap.add_argument("--single", action="store_true")
    a = ap.parse_args()
    if a.mode == "to-pdf":
        to_pdf(a)
    else:
        # الصيغة: to-img file.pdf outdir  →  الوسيط الأول ملف، الثاني مجلد
        a.inputs, a.output = [a.output], a.inputs[0]
        to_img(a)


if __name__ == "__main__":
    main()
