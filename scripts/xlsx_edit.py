#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
xlsx_edit.py — التحكم في ملفات إكسل خلية خلية، مكمّل لـ xlsx_tidy.py.

القراءة والفحص:
    python3 xlsx_edit.py read  file.xlsx [--sheet S] [--rows 30] [--formulas]
    python3 xlsx_edit.py find  file.xlsx --text "قيمة"            أين تظهر القيمة
    python3 xlsx_edit.py check file.xlsx                          فحص Arab Writer للخلايا النصية العربية

التعديل (ملف جديد دائماً):
    python3 xlsx_edit.py proof   in.xlsx out.xlsx [--highlight]   إصلاح آمن للنصوص العربية
    python3 xlsx_edit.py set     in.xlsx out.xlsx --cell "الورقة1!B2=1500" --cell "C2==B2*0.15"
    python3 xlsx_edit.py replace in.xlsx out.xlsx --map "قديم=جديد" [--sheet S] [--whole]
    python3 xlsx_edit.py sheet   in.xlsx out.xlsx --add "تقرير" | --rename "قديم=جديد" | --delete "S" | --copy "S=نسخة"
    python3 xlsx_edit.py rows    in.xlsx out.xlsx --sheet S --insert 5 [--count 2] | --delete 7 [--count 1]
    python3 xlsx_edit.py cols    in.xlsx out.xlsx --sheet S --insert C | --delete D | --width "A=30,B=12"
    python3 xlsx_edit.py format  in.xlsx out.xlsx --range "B2:B50" [--number "#,##0.00"] [--bold] [--fill 1B4F72] [--color FFFFFF] [--align center]
    python3 xlsx_edit.py rtl     in.xlsx out.xlsx [--font Arial]  اتجاه من اليمين لكل الأوراق
    python3 xlsx_edit.py chart   in.xlsx out.xlsx --sheet S --type bar|line|pie --data "B1:B13" --cats "A2:A13" [--at E2] [--title "..."]

التحويل:
    python3 xlsx_edit.py to-pdf in.xlsx [outdir]
    python3 xlsx_edit.py recalc in.xlsx out.xlsx                 حساب قيم الدوال عبر LibreOffice

صيغة --cell: [الورقة!]الخلية=القيمة. القيمة التي تبدأ بـ = دالة. الرقم يُخزَّن رقماً.
"""
import argparse
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


_need("openpyxl", "openpyxl")
import ar_lint                                                   # noqa: E402
from openpyxl import load_workbook                               # noqa: E402
from openpyxl.chart import BarChart, LineChart, PieChart, Reference  # noqa: E402
from openpyxl.styles import Alignment, Font, PatternFill         # noqa: E402
from openpyxl.utils import column_index_from_string, get_column_letter  # noqa: E402

AR_RE = re.compile(r"[؀-ۿ]")
YELLOW = PatternFill("solid", fgColor="FFF59D")


def load(path, data_only=False):
    if path.lower().endswith(".xls") or path.lower().endswith(".csv"):
        sys.exit("حوّل الملف أولاً: xlsx_tidy.py clean يقرأ csv و xls ويخرج xlsx.")
    return load_workbook(path, data_only=data_only)


def save(wb, out, src):
    if os.path.abspath(out) == os.path.abspath(src):
        sys.exit("لا يُكتب فوق الملف الأصلي. اختر اسماً جديداً.")
    wb.save(out)
    print(f"حُفظ: {out}")


def sheets(wb, name):
    if name:
        if name not in wb.sheetnames:
            sys.exit(f"لا توجد ورقة باسم {name}. الأوراق: {'، '.join(wb.sheetnames)}")
        return [wb[name]]
    return wb.worksheets


def coerce(v):
    if v.startswith("="):
        return v
    t = v.replace(",", "").replace("٬", "")
    if re.fullmatch(r"-?\d+", t):
        return int(t)
    if re.fullmatch(r"-?\d*\.\d+", t):
        return float(t)
    if v.endswith("%") and re.fullmatch(r"-?\d+(\.\d+)?", t[:-1]):
        return float(t[:-1]) / 100
    return v


# ---------------------------------------------------------------- القراءة

def cmd_read(a):
    wb = load(a.input)
    wv = load(a.input, data_only=True)
    for ws in sheets(wb, a.sheet):
        vs = wv[ws.title]
        print(f"\n■ {ws.title} · {ws.max_row} صف × {ws.max_column} عمود · النطاق {ws.dimensions}"
              f"{' · من اليمين' if ws.sheet_view.rightToLeft else ''}")
        for r in range(1, min(ws.max_row, a.rows) + 1):
            cells = []
            for c in range(1, ws.max_column + 1):
                v = ws.cell(r, c).value
                if v is None:
                    cells.append("")
                    continue
                if isinstance(v, str) and v.startswith("=") and not a.formulas:
                    cv = vs.cell(r, c).value
                    cells.append(f"{cv if cv is not None else '؟'} ⟨دالة⟩")
                else:
                    cells.append(str(v))
            if any(cells):
                print(f"  {r}: " + " | ".join(cells))
        if ws.max_row > a.rows:
            print(f"  … {ws.max_row - a.rows} صف آخر")
        charts = len(getattr(ws, "_charts", []))
        merged = len(ws.merged_cells.ranges)
        if charts or merged:
            print(f"  رسوم {charts} · خلايا مدمجة {merged}")


def cmd_find(a):
    wb = load(a.input)
    n = 0
    for ws in wb.worksheets:
        for row in ws.iter_rows():
            for c in row:
                if c.value is not None and a.text in str(c.value):
                    print(f"{ws.title}!{c.coordinate}: {c.value}")
                    n += 1
    print(f"النتائج: {n}")


def cmd_check(a):
    wb = load(a.input)
    err = warn = 0
    for ws in sheets(wb, a.sheet):
        for row in ws.iter_rows():
            for c in row:
                v = c.value
                if not isinstance(v, str) or v.startswith("=") or not AR_RE.search(v):
                    continue
                r, _ = ar_lint.check(v, en_lines=False)
                for it in r.items:
                    if it["kind"] in ("إيقاع", "بنية"):
                        continue
                    mark = "✗" if it["level"] == "خطأ" else "·"
                    print(f"{mark} {ws.title}!{c.coordinate} [{it['kind']}] {it['msg']}")
                    err += it["level"] == "خطأ"
                    warn += it["level"] != "خطأ"
    print(f"\nالأخطاء المانعة {err} · التنبيهات {warn}")
    return 1 if err else 0


# ---------------------------------------------------------------- التعديل

def cmd_proof(a):
    wb = load(a.input)
    n = 0
    for ws in sheets(wb, a.sheet):
        for row in ws.iter_rows():
            for c in row:
                v = c.value
                if not isinstance(v, str) or v.startswith("=") or not AR_RE.search(v):
                    continue
                new = ar_lint.fix(v, en_lines=False).strip()
                if new and new != v.strip():
                    print(f"{ws.title}!{c.coordinate}: «{v}» ← «{new}»")
                    c.value = new
                    if a.highlight:
                        c.fill = YELLOW
                    n += 1
    save(wb, a.output, a.input)
    print(f"خلايا مصحّحة: {n}")


def cmd_set(a):
    wb = load(a.input)
    for spec in a.cell:
        m = re.match(r"^(?:(.+)!)?([A-Za-z]{1,3}\d+)=(.*)$", spec, re.S)
        if not m:
            sys.exit(f"صيغة خاطئة: {spec} (المطلوب الورقة!B2=القيمة)")
        sh, ref, val = m.groups()
        ws = wb[sh] if sh else wb.active
        before = ws[ref].value
        ws[ref].value = coerce(val)
        print(f"{ws.title}!{ref.upper()}: {before!r} ← {ws[ref].value!r}")
    save(wb, a.output, a.input)


def cmd_replace(a):
    wb = load(a.input)
    pairs = [m.split("=", 1) for m in a.map]
    n = 0
    for ws in sheets(wb, a.sheet):
        for row in ws.iter_rows():
            for c in row:
                v = c.value
                if not isinstance(v, str) or v.startswith("="):
                    continue
                new = v
                for old, rep in pairs:
                    new = (rep if new.strip() == old else new) if a.whole else new.replace(old, rep)
                if new != v:
                    c.value = coerce(new) if a.whole else new
                    n += 1
    save(wb, a.output, a.input)
    print(f"خلايا مستبدلة: {n}")


def cmd_sheet(a):
    wb = load(a.input)
    if a.add:
        ws = wb.create_sheet(a.add)
        ws.sheet_view.rightToLeft = True
        print(f"أُضيفت الورقة: {a.add}")
    if a.rename:
        old, new = a.rename.split("=", 1)
        sheets(wb, old)[0].title = new
        print(f"«{old}» ← «{new}» (الدوال التي تشير للاسم القديم لا تتحدث تلقائياً، راجعها بـ find)")
    if a.copy:
        src, new = a.copy.split("=", 1)
        cp = wb.copy_worksheet(sheets(wb, src)[0])
        cp.title = new
        print(f"نُسخت {src} إلى {new}")
    if a.delete:
        if len(wb.sheetnames) == 1:
            sys.exit("لا تُحذف الورقة الوحيدة.")
        wb.remove(sheets(wb, a.delete)[0])
        print(f"حُذفت الورقة: {a.delete}")
    save(wb, a.output, a.input)


def cmd_rows(a):
    wb = load(a.input)
    ws = sheets(wb, a.sheet)[0]
    if a.insert:
        ws.insert_rows(a.insert, a.count)
        print(f"أُدرج {a.count} صف قبل الصف {a.insert}")
    if a.delete:
        has = any(ws.cell(r, c).value is not None
                  for r in range(a.delete, a.delete + a.count) for c in range(1, ws.max_column + 1))
        if has and not a.force:
            sys.exit(f"الصفوف {a.delete} إلى {a.delete + a.count - 1} فيها بيانات. أضف --force بعد تأكيد المستخدم.")
        ws.delete_rows(a.delete, a.count)
        print(f"حُذف {a.count} صف من الصف {a.delete}")
    print("تنبيه: الدوال التي تشير لصفوف بعد الموضع لا تُزاح تلقائياً، راجعها." if a.insert or a.delete else "")
    save(wb, a.output, a.input)


def cmd_cols(a):
    wb = load(a.input)
    ws = sheets(wb, a.sheet)[0]
    if a.insert:
        ws.insert_cols(column_index_from_string(a.insert), a.count)
        print(f"أُدرج {a.count} عمود قبل {a.insert}")
    if a.delete:
        idx = column_index_from_string(a.delete)
        has = any(ws.cell(r, c).value is not None
                  for c in range(idx, idx + a.count) for r in range(1, ws.max_row + 1))
        if has and not a.force:
            sys.exit(f"العمود {a.delete} فيه بيانات. أضف --force بعد تأكيد المستخدم.")
        ws.delete_cols(idx, a.count)
        print(f"حُذف {a.count} عمود من {a.delete}")
    if a.width:
        for part in a.width.split(","):
            col, w = part.split("=")
            ws.column_dimensions[col.strip().upper()].width = float(w)
        print(f"عرض الأعمدة: {a.width}")
    save(wb, a.output, a.input)


def cmd_format(a):
    wb = load(a.input)
    ws = sheets(wb, a.sheet)[0] if a.sheet else wb.active
    n = 0
    for row in ws[a.range]:
        for c in (row if isinstance(row, tuple) else (row,)):
            if a.number:
                c.number_format = a.number
            if a.bold or a.color or a.size:
                f = c.font
                c.font = Font(name=f.name, size=a.size or f.size, bold=a.bold or f.bold,
                              color=a.color or (f.color.rgb if f.color and isinstance(f.color.rgb, str) else None))
            if a.fill:
                c.fill = PatternFill("solid", fgColor=a.fill)
            if a.align:
                c.alignment = Alignment(horizontal=a.align, vertical="center", wrap_text=a.wrap)
            n += 1
    save(wb, a.output, a.input)
    print(f"خلايا منسّقة: {n} في {ws.title}!{a.range}")


def cmd_rtl(a):
    wb = load(a.input)
    for ws in wb.worksheets:
        ws.sheet_view.rightToLeft = True
        if a.font:
            for row in ws.iter_rows():
                for c in row:
                    if c.value is not None:
                        f = c.font
                        c.font = Font(name=a.font, size=f.size, bold=f.bold, italic=f.italic,
                                      color=f.color.rgb if f.color and isinstance(f.color.rgb, str) else None)
    save(wb, a.output, a.input)
    print(f"أوراق من اليمين لليسار: {len(wb.worksheets)}")


def cmd_chart(a):
    wb = load(a.input)
    ws = sheets(wb, a.sheet)[0] if a.sheet else wb.active

    def ref(rng):
        s, e = rng.split(":")
        c1, r1 = re.match(r"([A-Z]+)(\d+)", s.upper()).groups()
        c2, r2 = re.match(r"([A-Z]+)(\d+)", e.upper()).groups()
        return Reference(ws, min_col=column_index_from_string(c1), min_row=int(r1),
                         max_col=column_index_from_string(c2), max_row=int(r2))

    ch = {"bar": BarChart, "line": LineChart, "pie": PieChart}[a.type]()
    ch.add_data(ref(a.data), titles_from_data=True)
    if a.cats:
        ch.set_categories(ref(a.cats))
    if a.title:
        ch.title = a.title
    ch.width, ch.height = 18, 9
    ws.add_chart(ch, a.at)
    save(wb, a.output, a.input)
    print(f"رسم {a.type} في {ws.title}!{a.at}")


def soffice(src, outdir, fmt):
    exe = shutil.which("soffice") or shutil.which("libreoffice")
    if not exe:
        sys.exit("LibreOffice غير متوفر.")
    os.makedirs(outdir, exist_ok=True)
    subprocess.run([exe, "--headless", "--convert-to", fmt, "--outdir", outdir, src],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)
    return os.path.join(outdir, os.path.splitext(os.path.basename(src))[0] + "." + fmt.split(":")[0])


def cmd_to_pdf(a):
    out = soffice(a.input, a.outdir or os.path.dirname(os.path.abspath(a.input)), "pdf")
    print(f"حُفظ: {out}")


def cmd_recalc(a):
    import tempfile
    tmp = tempfile.mkdtemp()
    out = soffice(a.input, tmp, "xlsx:Calc MS Excel 2007 XML")
    shutil.move(out, a.output)
    wb = load(a.output, data_only=True)
    errs = []
    for ws in wb.worksheets:
        for row in ws.iter_rows():
            for c in row:
                if isinstance(c.value, str) and re.fullmatch(r"#(REF!|DIV/0!|VALUE!|NAME\?|N/A|NUM!|NULL!)", c.value):
                    errs.append(f"{ws.title}!{c.coordinate}={c.value}")
    print(f"حُفظ: {a.output}")
    print("أخطاء الدوال: " + ("، ".join(errs) if errs else "لا يوجد"))
    return 1 if errs else 0


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="إكسل خلية خلية")
    sub = ap.add_subparsers(dest="cmd", required=True)
    io = lambda n: (lambda p: (p.add_argument("input"), p.add_argument("output"), p)[2])(sub.add_parser(n))

    p = sub.add_parser("read"); p.add_argument("input"); p.add_argument("--sheet")
    p.add_argument("--rows", type=int, default=30); p.add_argument("--formulas", action="store_true")
    p = sub.add_parser("find"); p.add_argument("input"); p.add_argument("--text", required=True)
    p = sub.add_parser("check"); p.add_argument("input"); p.add_argument("--sheet")
    p = io("proof"); p.add_argument("--sheet"); p.add_argument("--highlight", action="store_true")
    p = io("set"); p.add_argument("--cell", action="append", required=True)
    p = io("replace"); p.add_argument("--map", action="append", required=True)
    p.add_argument("--sheet"); p.add_argument("--whole", action="store_true")
    p = io("sheet"); p.add_argument("--add"); p.add_argument("--rename"); p.add_argument("--delete")
    p.add_argument("--copy")
    p = io("rows"); p.add_argument("--sheet"); p.add_argument("--insert", type=int)
    p.add_argument("--delete", type=int); p.add_argument("--count", type=int, default=1)
    p.add_argument("--force", action="store_true")
    p = io("cols"); p.add_argument("--sheet"); p.add_argument("--insert"); p.add_argument("--delete")
    p.add_argument("--count", type=int, default=1); p.add_argument("--width")
    p.add_argument("--force", action="store_true")
    p = io("format"); p.add_argument("--sheet"); p.add_argument("--range", required=True)
    p.add_argument("--number"); p.add_argument("--bold", action="store_true"); p.add_argument("--fill")
    p.add_argument("--color"); p.add_argument("--size", type=float); p.add_argument("--align")
    p.add_argument("--wrap", action="store_true")
    p = io("rtl"); p.add_argument("--font")
    p = io("chart"); p.add_argument("--sheet"); p.add_argument("--type", default="bar",
                                                                choices=["bar", "line", "pie"])
    p.add_argument("--data", required=True); p.add_argument("--cats"); p.add_argument("--at", default="H2")
    p.add_argument("--title")
    p = sub.add_parser("to-pdf"); p.add_argument("input"); p.add_argument("outdir", nargs="?")
    io("recalc")

    a = ap.parse_args()
    fn = {"read": cmd_read, "find": cmd_find, "check": cmd_check, "proof": cmd_proof, "set": cmd_set,
          "replace": cmd_replace, "sheet": cmd_sheet, "rows": cmd_rows, "cols": cmd_cols,
          "format": cmd_format, "rtl": cmd_rtl, "chart": cmd_chart, "to-pdf": cmd_to_pdf,
          "recalc": cmd_recalc}[a.cmd]
    return fn(a) or 0


if __name__ == "__main__":
    sys.exit(main())
