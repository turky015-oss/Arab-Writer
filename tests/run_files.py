#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
اختبار تشغيل لأدوات الملفات: وورد وإكسل و PDF. ينشئ ملفات في مجلد مؤقت،
يشغّل كل أمر، ويتحقق من الناتج. الاستعمال: python3 tests/run_files.py
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SC = os.path.join(HERE, "..", "scripts")
T = tempfile.mkdtemp()
ok = bad = 0


def run(name, script, *args, expect=0, must=None):
    global ok, bad
    r = subprocess.run([sys.executable, os.path.join(SC, script), *args],
                       capture_output=True, text=True, timeout=240)
    out = r.stdout + r.stderr
    good = r.returncode == expect and (must is None or must in out)
    if good:
        ok += 1
        print(f"✓ {name}")
    else:
        bad += 1
        print(f"✗ {name} (رمز {r.returncode})\n{out[-600:]}")
    return out


def p(*parts):
    return os.path.join(T, *parts)


with open(p("in.md"), "w", encoding="utf-8") as f:
    f.write("# تقرير\n\nفي عالم اليوم، حققت الشركه نتائج **ممتازة** , و الفريق انجز اكثر.\n\n"
            "- بند أول\n- بند ثان\n\n| البند | القيمة |\n|---|---|\n| المبيعات | 500 |\n")

# وورد
run("وورد: إنشاء", "ar_docx.py", "build", p("in.md"), p("a.docx"), "--title", "عنوان", must="حُفظ")
run("وورد: قراءة", "ar_docx.py", "read", p("a.docx"), must="الشركه")
run("وورد: فحص يكشف الأخطاء", "ar_docx.py", "check", p("a.docx"), expect=1, must="الشركة")
run("وورد: إصلاح مع بقاء التنسيق", "ar_docx.py", "proof", p("a.docx"), p("b.docx"), must="فقرات معدّلة")
run("وورد: بعد الإصلاح", "ar_docx.py", "read", p("b.docx"), must="الشركة نتائج ممتازة، والفريق أنجز أكثر")
run("وورد: استبدال", "ar_docx.py", "replace", p("b.docx"), p("c.docx"), "--map", "الشركة=المؤسسة", must="1 مرة")
run("وورد: تعديل فقرة", "ar_docx.py", "set", p("c.docx"), p("d.docx"), "--para", "3", "--text", "نص جديد.")
run("وورد: إدراج", "ar_docx.py", "insert", p("d.docx"), p("e.docx"), "--after", "3", "--text", "مضافة.")
run("وورد: حذف", "ar_docx.py", "delete", p("e.docx"), p("f.docx"), "--para", "4")
run("وورد: اتجاه وخط", "ar_docx.py", "rtl", p("f.docx"), p("g.docx"), "--font", "Arial")
run("وورد: منع الكتابة فوق الأصل", "ar_docx.py", "proof", p("a.docx"), p("a.docx"), expect=1)
run("وورد: إلى PDF", "ar_docx.py", "to-pdf", p("g.docx"), T, must="g.pdf")

# إكسل
from openpyxl import Workbook  # noqa: E402
wb = Workbook()
ws = wb.active
ws.title = "المبيعات"
ws.append(["الشهر", "المبيعات", "ملاحظة"])
ws.append(["يناير", 1200, "اداء ممتاز , الشركه حققت هدفها"])
ws.append(["فبراير", 900, "الافضل"])
ws["B4"] = "=SUM(B2:B3)"
wb.save(p("x.xlsx"))
run("إكسل: قراءة", "xlsx_edit.py", "read", p("x.xlsx"), must="المبيعات")
run("إكسل: فحص", "xlsx_edit.py", "check", p("x.xlsx"), expect=1, must="الشركة")
run("إكسل: إصلاح", "xlsx_edit.py", "proof", p("x.xlsx"), p("x2.xlsx"), must="أداء ممتاز، الشركة")
run("إكسل: تعيين قيمة ودالة", "xlsx_edit.py", "set", p("x2.xlsx"), p("x3.xlsx"),
    "--cell", "D1=الضريبة", "--cell", "D2==B2*0.15")
run("إكسل: ورقة جديدة", "xlsx_edit.py", "sheet", p("x3.xlsx"), p("x4.xlsx"), "--add", "تقرير")
run("إكسل: تنسيق", "xlsx_edit.py", "format", p("x4.xlsx"), p("x5.xlsx"), "--sheet", "المبيعات",
    "--range", "A1:D1", "--bold", "--fill", "1B4F72", "--color", "FFFFFF")
run("إكسل: اتجاه", "xlsx_edit.py", "rtl", p("x5.xlsx"), p("x6.xlsx"))
run("إكسل: رسم", "xlsx_edit.py", "chart", p("x6.xlsx"), p("x7.xlsx"), "--sheet", "المبيعات",
    "--data", "B1:B3", "--cats", "A2:A3")
run("إكسل: حماية الصفوف ذات البيانات", "xlsx_edit.py", "rows", p("x7.xlsx"), p("x8.xlsx"),
    "--sheet", "المبيعات", "--delete", "2", expect=1)
run("إكسل: حساب الدوال", "xlsx_edit.py", "recalc", p("x7.xlsx"), p("x9.xlsx"), must="لا يوجد")
run("إكسل: القيم المحسوبة", "xlsx_edit.py", "read", p("x9.xlsx"), must="2100")

# PDF
run("PDF: معلومات", "pdf_tools.py", "info", p("g.pdf"), must="الصفحات")
run("PDF: فحص النص", "pdf_tools.py", "check", p("g.pdf"), must="الأخطاء")
run("PDF: دمج", "pdf_tools.py", "merge", p("m.pdf"), p("g.pdf"), p("g.pdf"), must="2 صفحة")
run("PDF: استخراج", "pdf_tools.py", "extract", p("m.pdf"), p("e.pdf"), "--pages", "2", must="1 صفحة")
run("PDF: حذف", "pdf_tools.py", "delete", p("m.pdf"), p("d.pdf"), "--pages", "1", must="1 صفحة")
run("PDF: تدوير", "pdf_tools.py", "rotate", p("m.pdf"), p("r.pdf"), "--deg", "90")
run("PDF: علامة مائية عربية", "pdf_tools.py", "watermark", p("m.pdf"), p("w.pdf"), "--text", "سري")
run("PDF: ترقيم", "pdf_tools.py", "number", p("w.pdf"), p("n.pdf"), "--fmt", "صفحة {n} من {total}")
run("PDF: حماية", "pdf_tools.py", "protect", p("n.pdf"), p("pr.pdf"), "--password", "1234")
run("PDF: فتح", "pdf_tools.py", "unlock", p("pr.pdf"), p("u.pdf"), "--password", "1234")
run("PDF: كلمة مرور خاطئة", "pdf_tools.py", "unlock", p("pr.pdf"), p("u2.pdf"), "--password", "0000", expect=1)
run("PDF: ضغط", "pdf_tools.py", "compress", p("u.pdf"), p("c.pdf"), must="ك.ب")
run("PDF: تقسيم", "pdf_tools.py", "split", p("m.pdf"), p("parts"), must="2 ملف")
run("PDF: إلى وورد", "pdf_tools.py", "to-docx", p("g.pdf"), p("back.docx"), must="حُفظ")

print(f"\nالنتيجة: {ok} ناجح، {bad} فاشل")
sys.exit(1 if bad else 0)
