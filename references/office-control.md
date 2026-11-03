# التحكم في وورد وإكسل و PDF

مرجع الأوامر الكاملة. المسارات نسبية لمجلد المهارة. كل أمر يكتب ملفاً جديداً، والأصل لا يُكتب فوقه أبداً (السكربتات ترفض ذلك).

## القاعدة: اقرأ، افحص، عدّل، تحقق

1. **اقرأ** الملف كاملاً قبل أي تعديل (`read` أو `info`). أرقام الفقرات والخلايا والصفحات تأتي من القراءة لا من التخمين.
2. **افحص** النص العربي داخله (`check`) إن كان الطلب تدقيقاً أو تنظيفاً.
3. **عدّل** بالأمر المناسب. التعديلات المتتالية تُسلسل: ناتج كل أمر مدخل التالي، وأسماء الملفات الوسيطة في مجلد مؤقت.
4. **تحقق**: أعد القراءة، وحوّل إلى PDF وافحص بصرياً أول صفحة على الأقل (`pdftoppm -png -r 60 -f 1 -l 1`).
5. **سلّم** الملف النهائي وحده بسطر واحد: ما تغيّر.

## وورد: `scripts/ar_docx.py`

| الطلب | الأمر |
|---|---|
| وش في الملف | `read file.docx` |
| دقّق الملف، صحح الأخطاء | `check` ثم `proof in out [--highlight]` |
| غيّر كلمة في كل الملف | `replace in out --map "قديم=جديد"` |
| عدّل فقرة / أضف / احذف | `set --para N --text` · `insert --after N --text [--style "Heading 2"]` · `delete --para N` |
| الملف اتجاهه خطأ، الخط مكسور | `rtl in out [--font Arial] [--size 13]` |
| سوّ لي ملف وورد / تقرير / خطاب | اكتب النص ماركداون، مرّره بالمراحل الثلاث، ثم `build in.md out.docx --title "..." [--logo] [--footer]` |
| حوّله PDF | `to-pdf in.docx [outdir]` |
| حوّل PDF لوورد | `from-pdf in.pdf out.docx` |

- `proof` يصلح الآمن فقط (إملاء مؤكد، ترقيم، مسافات) جزءاً جزءاً، فيبقى العريض والألوان والخطوط كما هي. البصمات الآلية والنحو تبقى للمراجعة: اقرأ تقرير `check`، أعد كتابة الفقرة بنفسك، وضعها بـ `set`.
- `--highlight` يظلل كل جزء تغيّر بالأصفر ليراجعه المستخدم. استعمله حين يطلب "وريني وش غيّرت" على ملف.
- الإنجليزية داخل الفقرة تبقى في مكانها في وورد. قاعدة السطر المستقل للرد في المحادثة، لا للمستندات.
- `set` يستبدل نص الفقرة كلها بتنسيق أول جزء منها.
- أرقام الفقرات من `read` تشمل الفقرات الفارغة. الجداول تُعدَّل بـ `replace` أو بإعادة البناء.
- ملف `.doc` القديم: حوّله أولاً `soffice --headless --convert-to docx file.doc`.

## إكسل: `scripts/xlsx_edit.py` مع `scripts/xlsx_tidy.py`

`xlsx_tidy.py` للتنظيف الشامل والترتيب والأعمدة المحسوبة (وضع الجداول). `xlsx_edit.py` للتحكم خلية خلية:

| الطلب | الأمر |
|---|---|
| وش في الملف | `read file.xlsx [--sheet S] [--rows 50] [--formulas]` |
| وين القيمة الفلانية | `find file.xlsx --text "..."` |
| دقّق النصوص العربية | `check` ثم `proof in out [--highlight]` |
| غيّر خلية أو ضع دالة | `set in out --cell "الورقة!B2=1500" --cell "C2==B2*0.15"` |
| استبدل قيمة في كل الملف | `replace in out --map "قديم=جديد" [--whole]` |
| أوراق | `sheet in out --add / --rename "أ=ب" / --copy "أ=ب" / --delete` |
| صفوف وأعمدة | `rows --insert N / --delete N` · `cols --insert C / --delete D / --width "A=30"` |
| تنسيق | `format --range "A1:D1" --bold --fill 1B4F72 --color FFFFFF --number "#,##0" --align center` |
| من اليمين لليسار | `rtl in out [--font Arial]` |
| رسم بياني | `chart --type bar\|line\|pie --data "B1:B13" --cats "A2:A13" --title "..."` |
| احسب الدوال وتأكد ما فيها أخطاء | `recalc in out` |
| حوّله PDF | `to-pdf in.xlsx` |

- القيمة التي تبدأ بـ `=` دالة حية، وما عداها يُخزَّن رقماً إن كان رقماً.
- حذف صف أو عمود فيه بيانات يُرفض إلا بـ `--force`، ولا تستعمله قبل تأكيد المستخدم بسؤال واحد.
- بعد أي `set` فيه دوال: شغّل `recalc`، ورمز الخروج غير الصفر يعني خطأ دالة (#REF! وغيرها) يُصلح قبل التسليم.
- إدراج صفوف أو حذفها لا يزيح الدوال التي تشير إليها. راجعها بـ `read --formulas`.

## PDF: `scripts/pdf_tools.py` مع `ar_pdf.py` و `pdf_extract.py` و `img_pdf.py`

| الطلب | الأمر |
|---|---|
| وش في الملف | `info file.pdf` ثم `pdf_extract.py` للنص |
| دقّق النص | `check file.pdf [--pages 1-3]` |
| ادمج | `merge out.pdf a.pdf b.pdf` |
| قسّم | `split file.pdf outdir/ [--every N]` |
| طلّع صفحات / احذف / رتّب / دوّر | `extract --pages "1,3-5"` · `delete --pages` · `reorder --order "3,1,2"` · `rotate --pages 2 --deg 90` |
| أضف ملفاً داخل ملف | `insert in out --from other.pdf --after 2` |
| علامة مائية بالعربي | `watermark in out --text "سري" [--opacity 0.12] [--color 1B4F72]` |
| شعار على الصفحات | `stamp in out --image logo.png --pos tr --width 30` |
| ترقيم الصفحات | `number in out --fmt "صفحة {n} من {total}" [--skip-first]` |
| عبّئ النموذج | `fields` ثم `fill in out --set "الاسم=..." [--flatten]` |
| احمِه بكلمة مرور / افتحه | `protect in out --password P [--no-copy] [--no-print]` · `unlock in out --password P` |
| صغّر الحجم | `compress in out` |
| عدّل النص داخله | `to-docx` ← `ar_docx.py proof/set/replace` ← `ar_docx.py to-pdf` |
| لخّصه وأخرجه PDF | وضع المستندات (`ar_pdf.py`) |
| صور ↔ PDF | وضع التحويل (`img_pdf.py`) |

- PDF لا يُعدَّل نصه في مكانه. التعديل يمر بوورد: حوّله، عدّله، أعده PDF، وقل للمستخدم إن التنسيق قد يختلف قليلاً عن الأصل.
- `check` يتجاهل المسافات والأسطر لأن استخراج النص من PDF يفسدها؛ يكشف الإملاء والبصمات فقط.
- كلمة المرور يكتبها المستخدم في طلبه؛ لا تُحفظ ولا تُكرر في الرد.
- الملف الممسوح ضوئياً (info يقول: لا نص) لا يُفحص نصه. حوّله صوراً واقرأه بصرياً.

## تحويلات بين الصيغ

| من ← إلى | الأمر |
|---|---|
| وورد ← PDF | `ar_docx.py to-pdf` |
| PDF ← وورد | `pdf_tools.py to-docx` أو `ar_docx.py from-pdf` |
| إكسل ← PDF | `xlsx_edit.py to-pdf` |
| ماركداون ← وورد | `ar_docx.py build` |
| ماركداون ← PDF | `ar_pdf.py` |
| صور ↔ PDF | `img_pdf.py` |
| CSV أو xls ← xlsx | `xlsx_tidy.py clean` |
