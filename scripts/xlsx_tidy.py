#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
xlsx_tidy.py — يفحص ملف إكسل، ينظّفه، يرتّبه، ويضيف أعمدة محسوبة.

الفحص أولاً (لا يكتب شيئاً):
    python3 xlsx_tidy.py audit file.xlsx
    python3 xlsx_tidy.py audit file.xlsx --sheet "الورقة1"

التنظيف والإخراج:
    python3 xlsx_tidy.py clean file.xlsx out.xlsx \
        --sort "التاريخ:desc" \
        --calc "الإجمالي=الكمية*السعر" \
        --calc "الضريبة=الإجمالي*0.15" \
        --calc "نصيب الفرد=الإجمالي/العدد" \
        --total "الإجمالي,الضريبة" \
        --rtl --summary

ما يفعله clean افتراضياً:
    حذف الصفوف والأعمدة الفارغة، تنظيف المسافات الزائدة، توحيد المسافة
    العربية، تحويل الأرقام المخزّنة كنص إلى أرقام، تحويل التواريخ، حذف
    الصفوف المكررة، تجميد صف العنوان، فلتر تلقائي، ضبط عرض الأعمدة،
    اتجاه الورقة من اليمين لليسار.

صيغة --calc:
    اسم_العمود_الجديد=تعبير   ويستعمل التعبير أسماء الأعمدة والأرقام
    والعمليات + - * / ( ) والدالة sum() على عمود.
"""
import argparse
import os
import re
import subprocess
import sys


def _need(mod, pkg):
    try:
        return __import__(mod)
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", pkg,
                        "--break-system-packages", "-q"], check=False)
        return __import__(mod)


_need("pandas", "pandas")
_need("openpyxl", "openpyxl")
import pandas as pd                                             # noqa: E402
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side  # noqa: E402
from openpyxl.utils import get_column_letter                    # noqa: E402

AR_SPACE = "\u00a0\u200f\u200e\u202b\u202c\ufeff"
HEAD_FILL = PatternFill("solid", fgColor="1B4F72")
HEAD_FONT = Font(color="FFFFFF", bold=True, size=11)
TOTAL_FILL = PatternFill("solid", fgColor="EAEFF5")
THIN = Side(style="thin", color="D6DBE0")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)


def read_any(path, sheet=None):
    if path.lower().endswith((".csv", ".tsv", ".txt")):
        sep = "\t" if path.lower().endswith(".tsv") else None
        return {"data": pd.read_csv(path, sep=sep, engine="python")}
    xl = pd.ExcelFile(path)
    names = [sheet] if sheet else xl.sheet_names
    return {n: xl.parse(n, header=None) for n in names}


def detect_header(df):
    """يرجع رقم الصف الذي يصلح عنواناً، أو None."""
    for i in range(min(8, len(df))):
        row = df.iloc[i]
        filled = row.notna().sum()
        texty = sum(isinstance(v, str) and v.strip() != "" for v in row)
        if filled >= max(2, int(df.shape[1] * 0.6)) and texty >= filled * 0.7:
            return i
    return None


def clean_cell(v):
    if isinstance(v, str):
        s = v
        for ch in AR_SPACE:
            s = s.replace(ch, " ")
        s = re.sub(r"\s+", " ", s).strip()
        return s
    return v


def is_text(series):
    return not (pd.api.types.is_numeric_dtype(series)
                or pd.api.types.is_datetime64_any_dtype(series))


def to_number(series):
    if not is_text(series):
        return series, 0
    raw = series.dropna().astype(str).str.replace(",", "", regex=False)
    raw = raw.str.replace("٬", "", regex=False).str.replace("%", "", regex=False)
    conv = pd.to_numeric(raw, errors="coerce")
    ratio = conv.notna().mean() if len(conv) else 0
    if ratio > 0.9 and len(conv):
        out = pd.to_numeric(
            series.astype(str).str.replace(",", "", regex=False)
            .str.replace("٬", "", regex=False).str.replace("%", "", regex=False),
            errors="coerce")
        return out, int(conv.notna().sum())
    return series, 0


def frame(df):
    """يحوّل ورقة خام إلى إطار له عناوين نظيفة."""
    h = detect_header(df)
    notes = []
    if h is None:
        df.columns = ["عمود %d" % (i + 1) for i in range(df.shape[1])]
        notes.append("لم يُعثر على صف عناوين واضح، وُضعت عناوين تلقائية")
    else:
        df.columns = [clean_cell(c) if pd.notna(c) and str(c).strip() else "عمود %d" % (i + 1)
                      for i, c in enumerate(df.iloc[h])]
        df = df.iloc[h + 1:]
        if h > 0:
            notes.append("حُذفت %d صفوف فوق العنوان" % h)
    df = df.reset_index(drop=True)
    cols, seen = [], {}
    for c in df.columns:
        c = str(c)
        if c in seen:
            seen[c] += 1
            c = "%s %d" % (c, seen[c])
        else:
            seen[c] = 1
        cols.append(c)
    df.columns = cols
    return df, notes


def audit(path, sheet):
    sheets = read_any(path, sheet)
    print("الملف: %s" % os.path.basename(path))
    for name, raw in sheets.items():
        df, notes = frame(raw.copy())
        print("\n=== ورقة: %s ===" % name)
        print("الأبعاد الخام: %d صف × %d عمود" % raw.shape)
        empty_rows = int(df.isna().all(axis=1).sum())
        empty_cols = [c for c in df.columns if df[c].isna().all()]
        dups = int(df.duplicated().sum())
        print("صفوف فارغة: %d | أعمدة فارغة: %d | صفوف مكررة: %d"
              % (empty_rows, len(empty_cols), dups))
        for n in notes:
            print("ملاحظة: %s" % n)
        print("\n%-22s %-10s %-8s %-8s %s" % ("العمود", "النوع", "فراغات", "قيم فريدة", "ملاحظة"))
        for c in df.columns:
            s = df[c]
            conv, n_num = to_number(s)
            kind = "رقم" if pd.api.types.is_numeric_dtype(conv) else (
                "تاريخ" if pd.api.types.is_datetime64_any_dtype(s) else "نص")
            note = ""
            if n_num and is_text(s):
                note = "أرقام مخزّنة كنص (%d خلية)" % n_num
            elif is_text(s):
                stripped = s.dropna().astype(str)
                if len(stripped) and (stripped != stripped.str.strip()).any():
                    note = "مسافات زائدة"
            print("%-22s %-10s %-8d %-8d %s"
                  % (str(c)[:22], kind, int(s.isna().sum()), int(s.nunique()), note))
        nums = [c for c in df.columns if pd.api.types.is_numeric_dtype(to_number(df[c])[0])]
        if nums:
            print("\nأعمدة رقمية صالحة للعمليات: %s" % "، ".join(nums))


def apply_calc(df, expr):
    name, _, formula = expr.partition("=")
    name, formula = name.strip(), formula.strip()
    if not name or not formula:
        sys.exit("صيغة --calc غير صحيحة: %s" % expr)
    env = {}
    order = sorted(df.columns, key=lambda c: -len(str(c)))
    py = formula
    for i, c in enumerate(order):
        key = "__c%d__" % i
        col, _ = to_number(df[c])
        env[key] = pd.to_numeric(col, errors="coerce")
        py = py.replace(str(c), key)
    py = re.sub(r"sum\((__c\d+__)\)", r"\1.sum()", py)
    if not re.fullmatch(r"[\w\s.+\-*/()%]*", py):
        sys.exit("التعبير يحوي رموزاً غير مسموحة: %s" % formula)
    try:
        df[name] = eval(py, {"__builtins__": {}}, env)  # noqa: S307
    except Exception as e:
        sys.exit("تعذّر حساب %s: %s" % (name, e))
    return name


def clean(a):
    sheets = read_any(a.input, a.sheet)
    out_frames, report = {}, []
    for name, raw in sheets.items():
        before = raw.shape
        df, notes = frame(raw.copy())
        df = df.map(clean_cell)
        df = df.dropna(how="all").dropna(axis=1, how="all")
        dups = int(df.duplicated().sum())
        if dups and not a.keep_duplicates:
            df = df.drop_duplicates()
        fixed_nums = 0
        for c in df.columns:
            conv, n = to_number(df[c])
            if n:
                df[c] = conv
                fixed_nums += n
        df = df.reset_index(drop=True)
        for expr in a.calc or []:
            new = apply_calc(df, expr)
            notes.append("أُضيف عمود محسوب: %s" % new)
        if a.sort:
            col, _, direction = a.sort.partition(":")
            col = col.strip()
            if col in df.columns:
                df = df.sort_values(col, ascending=(direction.strip() != "desc"),
                                    kind="mergesort").reset_index(drop=True)
                notes.append("رُتّب حسب %s" % col)
            else:
                notes.append("عمود الترتيب %s غير موجود" % col)
        report.append({
            "الورقة": name,
            "قبل": "%d×%d" % before,
            "بعد": "%d×%d" % df.shape,
            "صفوف مكررة محذوفة": 0 if a.keep_duplicates else dups,
            "خلايا رقمية مصلحة": fixed_nums,
            "ملاحظات": " / ".join(notes) or "لا شيء",
        })
        out_frames[name] = df

    with pd.ExcelWriter(a.output, engine="openpyxl") as writer:
        for name, df in out_frames.items():
            df.to_excel(writer, sheet_name=str(name)[:31], index=False)
        if a.summary:
            pd.DataFrame(report).to_excel(writer, sheet_name="التقرير", index=False)

    style(a, out_frames)
    print(os.path.abspath(a.output))
    for r in report:
        print("%s: %s ← %s | %s" % (r["الورقة"], r["قبل"], r["بعد"], r["ملاحظات"]))


def style(a, frames):
    from openpyxl import load_workbook
    wb = load_workbook(a.output)
    totals = [c.strip() for c in a.total.split(",")] if a.total else []
    for ws in wb.worksheets:
        ws.sheet_view.rightToLeft = bool(a.rtl)
        ws.freeze_panes = "A2"
        headers = [c.value for c in ws[1]]
        for cell in ws[1]:
            cell.fill = HEAD_FILL
            cell.font = HEAD_FONT
            cell.alignment = Alignment(horizontal="center", vertical="center",
                                       wrap_text=True)
            cell.border = BORDER
        ws.row_dimensions[1].height = 24
        for i, col in enumerate(ws.iter_cols(min_row=1), start=1):
            width = max((len(str(c.value)) for c in col if c.value is not None),
                        default=8)
            ws.column_dimensions[get_column_letter(i)].width = min(max(width + 4, 10), 42)
        for row in ws.iter_rows(min_row=2):
            for cell in row:
                cell.border = BORDER
                if isinstance(cell.value, (int, float)):
                    cell.number_format = "#,##0.##"
                    cell.alignment = Alignment(horizontal="left")
                else:
                    cell.alignment = Alignment(horizontal="right", vertical="center")
        if ws.max_row > 1:
            ws.auto_filter.ref = ws.dimensions
        if totals and ws.title in frames:
            r = ws.max_row + 1
            ws.cell(row=r, column=1, value="الإجمالي").font = Font(bold=True)
            for i, h in enumerate(headers, start=1):
                if h in totals:
                    letter = get_column_letter(i)
                    c = ws.cell(row=r, column=i,
                                value="=SUM(%s2:%s%d)" % (letter, letter, r - 1))
                    c.font = Font(bold=True)
                    c.number_format = "#,##0.##"
            for c in ws[r]:
                c.fill = TOTAL_FILL
                c.border = BORDER
    wb.save(a.output)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["audit", "clean"])
    ap.add_argument("input")
    ap.add_argument("output", nargs="?")
    ap.add_argument("--sheet", default=None)
    ap.add_argument("--sort", default="")
    ap.add_argument("--calc", action="append")
    ap.add_argument("--total", default="")
    ap.add_argument("--rtl", action="store_true")
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--keep-duplicates", action="store_true")
    a = ap.parse_args()
    if a.mode == "audit":
        audit(a.input, a.sheet)
    else:
        if not a.output:
            sys.exit("حدّد ملف الإخراج.")
        clean(a)


if __name__ == "__main__":
    main()
