#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ar_lint.py — الفاحص الآلي لـ Arab Writer.

يفحص النص العربي فحصاً حتمياً قبل التسليم: الأخطاء الإملائية والنحوية،
الترقيم والمسافات، زوائد التنسيق، الكلمة الإنجليزية داخل السطر العربي،
الطول المطلوب، والمعلومات المضافة على الأصل. وينبّه على بصمات الذكاء
الاصطناعي ورتابة الإيقاع. ويصلح الآمن منها تلقائياً في النص الأصلي نفسه.

الاستعمال:
    python3 ar_lint.py check  text.txt                 تقرير
    python3 ar_lint.py check  text.txt --words 60      مع قفل الطول (±10%)
    python3 ar_lint.py check  text.txt --lines 3       قفل عدد الأسطر
    python3 ar_lint.py check  text.txt --source src.txt  كشف المعلومات المضافة
    python3 ar_lint.py check  text.txt --strict-style  البصمات الآلية أخطاء مانعة
    python3 ar_lint.py fix    text.txt -o out.txt      إصلاح آمن ثم تقرير
    python3 ar_lint.py diff   before.txt after.txt     ماذا تغيّر
    python3 ar_lint.py stats  text.txt                 عدّاد الكلمات والجمل
    أي أمر يقبل - بدل اسم الملف للقراءة من الإدخال القياسي، و --json للمخرج الآلي.

رمز الخروج: 0 نظيف، 1 فيه أخطاء مانعة، 2 خطأ في الاستعمال.

الأخطاء المانعة: الإملاء، النحو المؤكد، الترقيم، المسافات، زوائد التنسيق،
الاتجاه، الطول، والاختلاق. البصمات والإيقاع والثلاثيات تنبيهات لا تغيّر رمز
الخروج، إلا مع --strict-style.
"""
import argparse
import difflib
import json
import re
import statistics
import sys
import unicodedata

# ---------------------------------------------------------------- التطبيع

AR = "؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿"
DIAC_CHARS = frozenset([chr(c) for c in range(0x064B, 0x0653)] + ["ٰ"])
TATWEEL = "ـ"
BIDI_CHARS = frozenset("​‌‍‎‏‪‫‬‭"
                       "‮⁦⁧⁨⁩؜﻿")
# حروف عربية فقط: بلا الأرقام الهندية ولا علامات الترقيم العربية (، ؛ ؟) ولا التشكيل
AR_LET = "\u0621-\u064A\u066E-\u06D3\u06D5\u06FA-\u06FF\u0750-\u077F"
WORD_RE = re.compile(rf"[{AR_LET}\u064B-\u0652\u0670A-Za-z0-9٠-٩]+")
B = rf"(?<![{AR_LET}\w])"    # بداية كلمة
E = rf"(?![{AR_LET}\w])"     # نهاية كلمة


def _is_presentation(ch):
    cp = ord(ch)
    return 0xFB50 <= cp <= 0xFDFF or 0xFE70 <= cp <= 0xFEFF


def _nfkc_char(ch, full):
    if ord(ch) == 0xFDFA:
        return ch   # ﷺ: صيغة علمية مختصرة، لا تُفكك إلى حروف
    if not (full or _is_presentation(ch)):
        return ch
    o = unicodedata.normalize("NFKC", ch)
    # أشكال الحركات المنفصلة (FE70…) تتحول إلى «مسافة + حركة»: المسافة ليست من النص
    if len(o) > 1 and o[0] == " ":
        o = o[1:]
    return o


def normalize(text, keep_diac=False, full=True):
    """يطبّع النص ويُرجع (النص المطبَّع، خريطة المواضع).

    يحذف رموز الاتجاه والتطويل، ويعيد أشكال العرض إلى الحروف المنطقية،
    ويطبّق NFKC (حين full)، ويحذف التشكيل (إلا مع keep_diac).
    الخريطة: idx[i] = موضع الحرف i من النص المطبَّع في النص الأصلي.
    """
    out, idx = [], []
    for i, ch in enumerate(text):
        if ch in BIDI_CHARS:
            continue
        if ch == TATWEEL:
            # «هـ» علامة السنة الهجرية (٦٤هـ): التطويل هنا جزء من الرمز لا زخرفة
            # و«ـ» المفردة (لأخيه ـ أو قال ـ): علامة شك لا زخرفة داخل كلمة
            prev = text[i - 1] if i > 0 else ""
            nxt = text[i + 1] if i + 1 < len(text) else ""
            if prev == "ه" and not re.match(rf"[{AR_LET}\u064B-\u0652\u0670]", nxt):
                out.append(ch)
                idx.append(i)
            elif not re.match(rf"[{AR_LET}]", prev):
                out.append(ch)
                idx.append(i)
            continue
        for c in _nfkc_char(ch, full):
            if c in BIDI_CHARS or c == TATWEEL:
                continue
            if not keep_diac and c in DIAC_CHARS:
                continue
            out.append(c)
            idx.append(i)
    return "".join(out), idx


def canon(text):
    """تطبيع آمن للنص المسلَّم: أشكال العرض ← حروف، حذف رموز الاتجاه والتطويل،
    مع بقاء التشكيل وبقية الرموز كما هي."""
    return normalize(text, keep_diac=True, full=False)[0]


def strip_diac(s):
    return normalize(s)[0]


def words(s):
    return WORD_RE.findall(s)


def sentences(s):
    parts = re.split(r"(?<=[.!؟?])\s+|\n+", s)
    return [p.strip() for p in parts if len(words(p)) > 0]


def read(path):
    if path == "-":
        return sys.stdin.read()
    with open(path, encoding="utf-8") as f:
        return f.read()


def line_col(text, idx):
    return text.count("\n", 0, idx) + 1


def snippet(text, a, b, pad=18):
    s = text[max(0, a - pad):min(len(text), b + pad)].replace("\n", " ⏎ ")
    return s.strip()


FOLD = str.maketrans({"أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ى": "ي", "ة": "ه"})


def fold(s):
    return s.translate(FOLD)


# ---------------------------------------------------------------- القوائم

# بصمات آلية: (عبارة، فئة). تُطابق بعد التطبيع وتوحيد الألف، وبعد نزع «ال» والسوابق.
MARKERS = {
    "افتتاح آلي": [
        "في عالم اليوم", "في عالمنا المعاصر", "في عصرنا الحالي", "في عصرنا الحديث",
        "في ظل التطور", "في ظل التقدم", "مع تطور التكنولوجيا", "مع التطور التكنولوجي",
        "لا شك أن", "لا شك ان", "مما لا شك فيه", "لا يخفى على أحد", "من المعروف أن",
        "من المعلوم أن", "كما نعلم جميعا", "بطبيعة الحال", "بكل تأكيد",
        "دعنا نستكشف", "دعونا نستكشف", "دعونا نتعرف", "دعنا نتعرف",
        "سنتناول في هذا", "في هذا المقال سن", "هل تساءلت يوما", "هل سبق لك أن",
        "تخيل معي", "أهلا بك في عالم", "مرحبا بك في عالم",
    ],
    "تأكيد فارغ": [
        "بشكل كبير", "بشكل ملحوظ", "بشكل فعال", "بشكل واضح", "بشكل عام", "بشكل خاص",
        "بشكل أساسي", "بصورة أساسية", "بصورة كبيرة", "على نحو متزايد", "إلى حد كبير",
        "بلا أدنى شك", "الجدير بالذكر", "من الجدير بالإشارة", "تجدر الإشارة", "ومن الملاحظ",
        "ومن اللافت", "يعتبر من أهم", "يعد واحدا من أبرز", "يعد من أبرز", "لا يمكن إنكار",
        "من الضروري أن نذكر", "على حد سواء", "بكل سهولة", "بكل يسر",
    ],
    "ختام آلي": [
        "في الختام", "وفي الختام", "ختاما", "خلاصة القول", "وبهذا نكون قد", "نأمل أن يكون",
        "نتمنى أن تكون قد استفدت", "لا تتردد في", "لا تترددوا في", "شاركنا رأيك",
        "شاركونا آراءكم", "أخبرنا في التعليقات", "تابعنا للمزيد", "تابعونا للمزيد",
        "وإلى اللقاء في", "دمتم بخير", "آمل أن يفيدك", "أتمنى أن يكون مفيدا",
    ],
    "ترجمة حرفية": [
        "يلعب دورا", "تلعب دورا", "يفتح الباب أمام", "تفتح الباب أمام", "يفتح آفاقا",
        "تفتح آفاقا", "يشكل تحديا", "يمثل نقلة نوعية", "نقلة نوعية", "يغير قواعد اللعبة",
        "تغير قواعد اللعبة", "يعيد تشكيل", "تعيد تشكيل", "إعادة تشكيل", "إعادة التشكيل",
        "يعيد تعريف", "تعيد تعريف", "إعادة تعريف",
        "على نطاق واسع", "في نهاية المطاف", "تجربة مستخدم سلسة", "حلول متكاملة",
        "الاستفادة القصوى", "إطلاق العنان", "استكشاف الإمكانيات", "ثوري", "ثورية",
    ],
    "حشو": [
        "عبارة عن", "بالنسبة ل", "يقوم بتوفير", "تقوم بتوفير", "يقوم ب", "تقوم ب",
        "قام ب", "قامت ب", "الأمر الذي", "حيث أن", "حيث إن", "في الواقع",
        "ببساطة", "بكل بساطة", "باختصار شديد", "بمعنى آخر", "بكلمات أخرى",
        "كما ذكرنا سابقا", "دعني أوضح", "يمكن القول إن", "يمكن القول أن",
    ],
    "تلطيف": [
        "إلى حد ما", "نوعا ما", "من الممكن أن", "قد يكون من",
    ],
    "حكم مبهم": [
        "تداعيات مهمة", "نتائج مهمة", "الأسباب متعددة", "الفوائد عديدة", "هناك العديد من",
        "الكثير من الناس", "كثير من الناس", "تشير الدراسات", "بعض الخبراء", "يعتقد الكثيرون",
        "الجميع يعرف",
    ],
}

# كلمات مفردة تُعد حشواً حين تأتي ظرفاً (تحذير لا منع)
SOFT_ADVERBS = ["حقا", "فعلا", "تماما", "بالفعل", "للغاية", "جدا", "صراحة"]

# أخطاء إملائية مؤكدة: (الخطأ، الصواب). المطابقة بحدود الكلمة وبعد التطبيع.
# لا تُضاف هنا كلمة لها قراءة صحيحة أخرى: «علي» و«ان» و«اعتقد» لها قواعد سياق أدناه.
# التنوين على الهمزة المتطرفة (جزءًا، بناءً) له قاعدة مستقلة تعمل على النص المشكول.
SPELL = {
    "اذا": "إذا", "الى": "إلى", "افضل": "أفضل", "اكثر": "أكثر", "اسرع": "أسرع",
    "اهم": "أهم", "اول": "أول", "الاول": "الأول", "الاولى": "الأولى", "الان": "الآن",
    "الأن": "الآن", "او": "أو", "ايضا": "أيضاً", "أيظا": "أيضاً", "ايظا": "أيضاً",
    "هذة": "هذه", "هاذا": "هذا", "هاذه": "هذه", "هاؤلاء": "هؤلاء", "ذالك": "ذلك",
    "لذالك": "لذلك", "كذالك": "كذلك", "لاكن": "لكن", "أولائك": "أولئك",
    "مسئول": "مسؤول", "مسئولية": "مسؤولية", "مسئولين": "مسؤولين", "شئون": "شؤون",
    "شئ": "شيء", "اشياء": "أشياء", "إنشاء الله": "إن شاء الله", "انشالله": "إن شاء الله",
    "انشاالله": "إن شاء الله", "بأذن الله": "بإذن الله",
    "إستخدام": "استخدام", "إستخدم": "استخدم", "إجتماع": "اجتماع", "إنطلاق": "انطلاق",
    "إحترام": "احترام", "إنتقال": "انتقال", "إستفادة": "استفادة", "إستثمار": "استثمار",
    "إسم": "اسم", "إبن": "ابن", "إمرأة": "امرأة", "إثنان": "اثنان", "إثنين": "اثنين",
    "انشاء": "إنشاء", "ارسال": "إرسال", "اعلان": "إعلان", "اضافة": "إضافة",
    "اطلاق": "إطلاق", "اصدار": "إصدار", "اعداد": "إعداد", "ادارة": "إدارة",
    "امكانية": "إمكانية", "احصائية": "إحصائية", "اجراءات": "إجراءات",
    "تقنيه": "تقنية", "شركه": "شركة", "مدرسه": "مدرسة", "فكره": "فكرة", "طريقه": "طريقة",
    "خدمه": "خدمة", "ميزه": "ميزة", "منصه": "منصة", "مرحله": "مرحلة", "الشركه": "الشركة",
    "التقنيه": "التقنية", "المنصه": "المنصة", "الخدمه": "الخدمة",
    "اليه": "إليه", "اليها": "إليها", "مياة": "مياه", "اتجاة": "اتجاه",
    "الذى": "الذي", "التى": "التي", "فى": "في",
    "نضام": "نظام", "النضام": "النظام", "ملاحضة": "ملاحظة", "لاحضت": "لاحظت",
    "انتضر": "انتظر", "حفض": "حفظ", "لحضة": "لحظة", "ظروري": "ضروري", "بعظ": "بعض",
    "مبادىء": "مبادئ", "قارىء": "قارئ", "شاطىء": "شاطئ", "خطئا": "خطأً",
    "مئه": "مئة", "الرحمان": "الرحمن", "هاكذا": "هكذا",
    "لا تنسى": "لا تنسَ", "لم يسعى": "لم يسعَ",
    "انجز": "أنجز", "انجزت": "أنجزت", "اعلن": "أعلن", "اعلنت": "أعلنت", "اطلق": "أطلق",
    "اطلقت": "أطلقت", "اكد": "أكد", "اكدت": "أكدت", "اضاف": "أضاف", "اضافت": "أضافت",
    "اصبح": "أصبح", "اصبحت": "أصبحت", "اصدر": "أصدر", "اصدرت": "أصدرت", "ارسل": "أرسل",
    "احمد": "أحمد", "اداء": "أداء", "اسلوب": "أسلوب", "اسعار": "أسعار", "ارقام": "أرقام",
    "اخبار": "أخبار", "افكار": "أفكار", "اجهزة": "أجهزة", "ادوات": "أدوات", "اعمال": "أعمال",
    "اسئلة": "أسئلة", "اهداف": "أهداف", "اسباب": "أسباب", "اطفال": "أطفال", "اشهر": "أشهر",
    "ايام": "أيام", "اسبوع": "أسبوع", "اكبر": "أكبر", "اصغر": "أصغر", "اقل": "أقل",
    "احسن": "أحسن", "اقوى": "أقوى", "اعلى": "أعلى", "ادنى": "أدنى", "ابريل": "أبريل", "اغسطس": "أغسطس",
    "مصطفي": "مصطفى", "متي": "متى", "حتي": "حتى",
    # أفعال المضارع للمتكلم: لا قراءة صحيحة لها بلا همزة
    "اظن": "أظن", "ارى": "أرى", "اريد": "أريد", "اتمنى": "أتمنى", "احاول": "أحاول",
    "استطيع": "أستطيع", "ارجو": "أرجو",
    # الأعداد
    "اربع": "أربع", "اربعة": "أربعة", "اربعون": "أربعون", "اربعين": "أربعين",
}

# السوابق التي تلتصق بالكلمة: و ف ب ك ل وال التعريف وما يتركب منها
PRE = r"[وف]?(?:بال|كال|لل|ال|[بكل])?"

# أخطاء نحوية نمطية ثابتة (تحذير مع اقتراح، لا إصلاح آلي)
GRAMMAR = [
    (r"أعلن الشركة", "أعلنت الشركة", "تأنيث الفعل مع الفاعل المؤنث"),
    (r"(قال|أعلن|أطلق|كشف|أكد) (الوزارة|الهيئة|الشركة|المنصة|الجامعة)", None,
     "الفعل يؤنث مع الفاعل المؤنث"),
    (r"هؤلاء ال(أجهزة|كتب|سيارات|تطبيقات|ميزات|أدوات|ملفات)", "هذه ال…",
     "هؤلاء للعاقل، هذه لجمع غير العاقل"),
    (r"المدير المدرسة|الوزارة الصحة|المدير الشركة", None, "لا تدخل ال على المضاف"),
    (r"عشرون (أيام|ساعات|دقائق|سنوات)", None, "المعدود بعد العقود مفرد منصوب"),
    (r"يؤثر على", "يؤثر في", "حرف الجر الصحيح"),
    (rf"بحاجة ل(?=[{AR}])", "بحاجة إلى", "حرف الجر الصحيح"),
    (r"يتكون على", "يتكون من", "حرف الجر الصحيح"),
    (r"مفندا", "مفنّداً", "الحال منصوب بالتنوين والشدة"),
    (r"الأ?موين", None, "«الأموين»: إن قصدت الصفة ف«الأموية» وإن قصدت الجمع ف«الأمويين»"),
    (r"الفوارق الأدوارية", "فوارق الأدوار", "صياغة شاذة"),
]

EMOJI_RE = re.compile(
    "[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0001F000-\U0001F2FF"
    "\U00002B00-\U00002BFF\U0000FE0F\U0000200D✅❌✔✖]"
)
DASH_RE = re.compile(r"[—–‒―]|--")
DIGITS = set("0123456789٠١٢٣٤٥٦٧٨٩")
HR_RE = re.compile(r"^---+\s*$", re.M)
MD_HEAD = re.compile(r"^\s{0,3}#{1,6}\s", re.M)
MD_BOLD = re.compile(r"\*\*[^*\n]+\*\*|__[^_\n]+__")
BULLET = re.compile(r"^\s*([-*•●▪✓✅]|\d+[.)])\s+", re.M)
PREAMBLE = re.compile(
    r"^\s*(إليك|اليك|هذا هو|هذه هي|فيما يلي|في ما يلي|تفضل|بالتأكيد|بكل سرور|حسنا|طبعا)[^\n]{0,40}[:：]?\s*$",
    re.M,
)


# ---------------------------------------------------------------- قواعد السياق
# كل قاعدة تأخذ النص المطبَّع وتُرجع عناصر: (بداية، نهاية، البديل أو None، النوع، الرسالة، المستوى)
# البديل يُكتب في النص الأصلي عبر خريطة المواضع، فلا يضيع تشكيل ما حوله.

TOK = re.compile(rf"[{AR_LET}]+")


def _tokens(norm):
    return [(m.start(), m.end(), m.group(0)) for m in TOK.finditer(norm)]


def _bare(w):
    """الكلمة بلا واو أو فاء العطف."""
    return w[1:] if len(w) > 3 and w[0] in "وف" else w


def _same_clause(norm, a_end, b_start):
    return not re.search(r"[.،؛؟!:\n]", norm[a_end:b_start])


def rule_spell(norm):
    alt = "|".join(re.escape(w).replace(r"\ ", r"\s+")
                   for w in sorted(SPELL, key=len, reverse=True))
    for m in re.finditer(rf"{B}({PRE})({alt}){E}", norm):
        key = re.sub(r"\s+", " ", m.group(2))
        right = SPELL[key]
        yield (m.start(2), m.end(2), right, "إملاء",
               f"«{m.group(0)}» ← «{m.group(1)}{right}»", "خطأ")


# على / علي: حرف الجر قبل اسم ظاهر، مقابل اسم العلم
ALA_GOV = set("""يجب ينبغي حصل حصلت يحصل تحصل نحصل اعتمد يعتمد تعتمد نعتمد ركز يركز تركز ركزت
وافق يوافق وافقت اطلع يطلع اطلعت تعرف يتعرف تعرفت بناء رد يرد ردت قضى يقضي تغلب يتغلب حافظ يحافظ
تحافظ أكد يؤكد أكدت تؤكد شدد يشدد شددت يدل تدل دليل يقع تقع وقع وقعت علاوة أثنى اعترض يعترض حرص
يحرص تحرص حرصت اتفق اتفقوا يتفق نتفق نص ينص تنص قادر قادرة قادرون قادرين يتوقف توقف يجيب أجاب
الحضور حضور الحفاظ الحصول التعرف التركيز الاعتماد قائم قائمة يقوم تقوم مبني مبنية يسيطر سيطر
يطلق أطلق اعتاد يعتاد تعتاد سلم يسلم سلمت السلام يرتكز ترتكز يشتمل تشتمل يحتوي تحتوي احتوى
عرض يعرض تعرض عرضت يطبق تطبق طبق ينطبق تنطبق يؤثر تؤثر أثر""".split())
ALA_FIXED_NEXT = set("""الرغم رغم الأقل الاقل الفور الإطلاق الاطلاق سبيل حد مدى مدار ضوء الأرجح
الارجح الأغلب الاغلب أساس اساس حساب طول امتداد خلاف غرار قدم وشك""".split())
NAME_PREV = set("""قال قالت ذكر أضاف صرح أوضح مع يا الأستاذ الاستاذ المهندس الدكتور الشيخ الأمير
الامير الملك أخي اخي أخو أخوك ابن بن أبو ابو والد والده السيد الكابتن المدير الطالب زميلي صديقي
اسمه اسمي سمى سميته""".split())
# ما يأتي بعد «علي» العلم مباشرة في النسب: يُفحص قبل أي حكومة فعل.
KINSHIP_NEXT = set("""بن بنت ابن ابنة أخ أخت أخو أبو أم عم عمة خال خالة""".split())
# أسماء أعلام محتملة بعد «علي»: لا إصلاح آلياً، تنبيه للمراجعة فقط.
# تُقارن بلا «ال» لتغطي «الحسن/الحسين» أيضاً.
PROPER_NEXT = {fold(w) for w in """محمد أحمد خالد سعد فهد عبدالله عبدالعزيز عبدالرحمن عبدالمجيد
عبدالإله تركي سلطان ناصر يوسف حسن حسين عمر عثمان ابراهيم إبراهيم يوسف كريم سامي ماجد
نايف فيصل هند سارة فاطمة نورة مريم ريم لينا سلمى""".split()}


# «ثوري/ثورية» بعد اسم علم (سفيان الثوري) نسبة لا بصمة ترجمة.
THAWRI_OK = PROPER_NEXT | {"سفيان", "ابن", "بن"}


def _strip_al(w):
    return w[2:] if w.startswith("ال") and len(w) > 4 else w


def rule_ala(norm):
    toks = _tokens(norm)
    for i, (a, b, w) in enumerate(toks):
        bare = _bare(w) if w != "علي" else w
        if bare != "علي":
            continue
        off = len(w) - 3
        prev = toks[i - 1][2] if i > 0 and _same_clause(norm, toks[i - 1][1], a) else ""
        nxt = toks[i + 1][2] if i + 1 < len(toks) and _same_clause(norm, b, toks[i + 1][0]) else ""
        prev_b = _bare(prev) if prev else ""
        nxt_b = _bare(nxt) if nxt else ""
        right = "على"
        if nxt in KINSHIP_NEXT or nxt_b in KINSHIP_NEXT:
            continue
        if nxt in ALA_FIXED_NEXT:
            yield (a + off, b, right, "إملاء", f"«{w} {nxt}» ← «على {nxt}»", "خطأ")
        elif prev_b in NAME_PREV or prev in NAME_PREV:
            continue
        elif (fold(nxt) in PROPER_NEXT or fold(nxt_b) in PROPER_NEXT
                or fold(_strip_al(nxt)) in PROPER_NEXT or fold(_strip_al(nxt_b)) in PROPER_NEXT
                or nxt.startswith("عبد") or nxt_b.startswith("عبد")):
            yield (a + off, b, None, "إملاء",
                   f"«{w} {nxt}»: إن كان علماً فأبقه، وإن كان حرف جر فصححه إلى «على»", "تنبيه")
        elif prev_b in ALA_GOV or prev in ALA_GOV:
            yield (a + off, b, right, "إملاء", f"«{prev} {w}» ← «{prev} على»", "خطأ")
        elif nxt.startswith("ال") and not nxt.endswith(("ي", "ية")):
            yield (a + off, b, None, "إملاء",
                   f"«{w} {nxt}»: حرف الجر «على» قبل اسم ظاهر، إلا إن كان «علي» اسماً", "تنبيه")


# «صراحة» بعد فعل قول (نصت صراحة) بمعنى «بوضوح» لا حشو خطاب.
SAY_PREV = {fold(w) for w in """نص نصت ذكر ذكرت ورد وردت جاء جاءت ثبت ثبتت
صرح صرحت أكد أكدت أفاد أفادت قال قالت""".split()}


def _prev_words(folded, pos, n=3):
    toks = [t for t in re.findall(rf"[{AR_LET}٠-٩]+", folded[:pos])
            if not re.fullmatch(r"[٠-٩0-9]+", t)]
    return toks[-n:]


# أن / إن / ان
ANNA_GOV = set("""اعتقد أعتقد يعتقد نعتقد تعتقد أظن اظن يظن نظن تظن أرى ارى يرى ترى نرى أريد اريد
يريد تريد نريد يجب ينبغي يمكن يمكنك يمكنكم يمكننا أود اود يود نود تود قبل بعد لابد بد عسى أتمنى
اتمنى يتمنى نتمنى أحب احب يحب نحب أرجو ارجو نرجو أحاول احاول يحاول نحاول حاول تحاول قرر قررت
يستطيع تستطيع أستطيع استطيع نستطيع أعلم اعلم يعلم نعلم تعلم أعرف يعرف نعرف تعرف تبين اتضح لاحظ
لاحظت لاحظنا أكد أكدت يؤكد أوضح أوضحت ذكر ذكرت أعلن أعلنت بما رغم مع كما إلا الا لولا لو يبدو
بدا شرط بشرط على أخشى يخشى أخاف يخاف أرغب يرغب نرغب أفضل الأفضل المفترض المهم الممكن الضروري""".split())
INNA_GOV = set("قال قالت يقول تقول أقول نقول قلت قلنا حيث".split())
ANNA_VERB_1P = {"اعتقد": "أعتقد", "احب": "أحب", "اعلم": "أعلم"}


def rule_anna(norm):
    toks = _tokens(norm)
    for i, (a, b, w) in enumerate(toks):
        bare = _bare(w) if w not in ("ان",) else w
        if bare != "ان":
            continue
        off = len(w) - 2
        prev = toks[i - 1] if i > 0 and _same_clause(norm, toks[i - 1][1], a) else None
        pw = _bare(prev[2]) if prev else ""
        if w.startswith("ف") and len(w) == 3:
            yield (a + off, b, "إن", "إملاء", f"«{w}» ← «فإن»", "خطأ")
        elif any(_bare(toks[j][2]) in INNA_GOV or toks[j][2] in INNA_GOV
                 for j in range(max(0, i - 5), i) if _same_clause(norm, toks[j][1], a)):
            yield (a + off, b, "إن", "إملاء", f"«{w}» بعد «قال» ← «إن»", "خطأ")
        elif pw in ANNA_GOV or (prev and prev[2] in ANNA_GOV):
            yield (a + off, b, "أن", "إملاء", f"«{prev[2]} {w}» ← «{prev[2]} أن»", "خطأ")
            # «اعتقد ان» في أول الجملة: مضارع المتكلم
            if pw in ANNA_VERB_1P and (i < 2 or not _same_clause(norm, toks[i - 2][1], prev[0])):
                pa = prev[0] + (len(prev[2]) - len(pw))
                yield (pa, prev[1], ANNA_VERB_1P[pw], "إملاء",
                       f"«{pw}» ← «{ANNA_VERB_1P[pw]}»", "خطأ")
        else:
            yield (a, b, None, "إملاء", f"«{w}»: «أن» أو «إن» في الفصحى، و«ان» عامية", "تنبيه")


# العدد من 3 إلى 10 يخالف المفرد: المفرد مؤنث فالعدد بلا تاء، والمفرد مذكر فالعدد بالتاء.
NUM_FORMS = {  # الجذر: (صيغة مع المفرد المؤنث، صيغة مع المفرد المذكر)
    "ثلاث": ("ثلاث", "ثلاثة"), "أربع": ("أربع", "أربعة"), "خمس": ("خمس", "خمسة"),
    "ست": ("ست", "ستة"), "سبع": ("سبع", "سبعة"), "ثمان": ("ثماني", "ثمانية"),
    "تسع": ("تسع", "تسعة"), "عشر": ("عشر", "عشرة"),
}
# آحاد التركيب 11-19 والترتيب (أحد عشر... التاسع عشر): «عشر» بعدها تتمة لا عدد مستقل.
TEEN_ONES = {fold(w) for w in """أحد إحدى اثنا اثني اثنتا اثنتي ثلاث ثلاثة
أربع أربعة خمس خمسة ست ستة سبع سبعة ثمان ثمانية تسع تسعة تاسع عاشر""".split()}
FEM_PLURALS = set("""نساء سيدات بنات ساعات دقائق طرق مرات سنوات سنين ميزات أدوات عيون أيد أرجل دول
مدن غرف صور فرص رسائل حقائق وظائف شرائح نقاط خطوات""".split())
MASC_PLURALS = set("""رجال أيام أشهر شهور أسابيع أعوام قرون كتب ملفات تطبيقات مستندات سجلات حسابات
قطارات مطارات جوالات حمامات مختبرات مؤتمرات منتجات محركات مصطلحات مجالات مقالات مستويات مكونات
أطفال طلاب أولاد إخوة أفكار أسباب أجهزة أهداف أسئلة أعمال أسعار أرقام أخبار مشاريع مواقع فيديوهات
ملايين آلاف مليارات دروس فصول أبواب أقسام أسطر سطور أمتار كيلومترات""".split())
# جمع «ـات» الذي عُرف مفرده: لا يُحكم بالشكل وحده.
# مذكر مفرده مذكر (إجراء/قرار/اتفاق...) — كان يُصلَّح خطأً إلى بلا تاء.
MASC_AT_PLURALS = {fold(w) for w in """إجراءات اجراءات قرارات اتفاقات بيانات اختبارات اجتماعات
استخدامات اقتراحات إنجازات انجازات تدريبات تصميمات تحليلات تعليقات مجالات منتجات ملفات
مؤتمرات مختبرات قطارات مطارات محركات مصطلحات مقالات مستويات مكونات جوانب""".split()}
# مؤنث عُرف مفرده (سيارة/شركة/جامعة/استشارة/معلومة...) — يُصلَّح آلياً.
FEM_AT_PLURALS = {fold(w) for w in """شركات سيارات جامعات منصات مكتبات عيادات عائلات لغات
ساعات ميزات أدوات سنوات طرق مرات دول مدن غرف صور فرص رسائل حقائق وظائف نقاط خطوات
استشارات معلومات استقالات استمارات صفحات""".split()}


def plural_gender(w):
    if w.startswith("ال") or len(w) < 3:
        return None
    fw = fold(w)
    if w in FEM_PLURALS or fw in {fold(x) for x in FEM_PLURALS}:
        return "f"
    if w in MASC_PLURALS or fw in {fold(x) for x in MASC_PLURALS}:
        return "m"
    if fw in MASC_AT_PLURALS:
        return "m"
    if fw in FEM_AT_PLURALS:
        return "f"
    if w.endswith(("ين", "ون")) and len(w) >= 5:
        return "m"   # جمع المذكر السالم وحده يُحسم بالشكل: لا مؤنث ينتهي بهما
    # كل ما عداها مجهول: لا إصلاح آلي إلا من قائمة المفرد، لا من شكل الجمع.
    # أوزان استفعال ومفعول وفعائل لا تكفي وحدها (استشارة/معلومة مؤنث رغم استـ).
    return None


NUM_RE = re.compile(rf"{B}([وفبكل]?)(ثلاث|[اأ]ربع|خمس|ست|سبع|ثمان|تسع|عشر)(ية|ي|ة)?\s+([{AR_LET}]+){E}")


def rule_number(norm):
    for m in NUM_RE.finditer(norm):
        root = m.group(2).replace("ا", "أ", 1) if m.group(2).startswith("اربع") else m.group(2)
        suf, noun = m.group(3) or "", m.group(4)
        if noun in ("عشر", "عشرة"):
            continue   # 13 إلى 19 لها حكم آخر
        if root == "عشر":
            # «عشر» تتمة تركيب لا عدد مستقل: التاسع عشر، ثلاثة عشر (تمييزها مفرد منصوب)
            prevs = list(re.finditer(rf"[{AR_LET}]+", norm[:m.start(2)]))
            if prevs and _same_clause(norm, prevs[-1].end(), m.start(2)) \
                    and fold(_strip_al(prevs[-1].group(0))) in TEEN_ONES:
                continue
        g = plural_gender(noun)
        g = plural_gender(noun)
        if g is None:
            yield (m.start(2), m.end(3) if m.group(3) else m.end(2), None, "نحو",
                   f"«{m.group(2)}{suf} {noun}»: جنس المفرد غير معروف — لا إصلاح آلياً، راجع المفرد", "تنبيه")
            continue
        has_ta = suf in ("ة", "ية")
        fem_form, masc_form = NUM_FORMS[root]
        want = fem_form if g == "f" else masc_form
        if (g == "f" and has_ta) or (g == "m" and not has_ta):
            yield (m.start(2), m.end(3) if m.group(3) else m.end(2), want, "نحو",
                   f"«{m.group(2)}{suf} {noun}»: العدد يخالف المعدود ← «{want} {noun}»", "خطأ")


# الأفعال الخمسة بعد الجازم والناصب: تُحذف النون.
# القاعدة صرفية لا حرفية: الفعل المضارع (ي/ت + جذر) + واو الجماعة/ألف الاثنين + نون الرفع.
# المفرد القصير (يكون/يصون/يهون: طول 4) يُستثنى بالطول لا بآخر ثلاثة حروف،
# والمفرد الطويل (يتعاون: ينتهي بألف) يُستثنى بالألف.
FIVE_TRIG = r"لم|لن|كي|لكي|أن|ان|ألا|لئلا"


def rule_five_verbs(norm):
    for m in re.finditer(rf"{B}(?:[وف]?)({FIVE_TRIG})\s+([يت][{AR_LET}]+?)(ون|ان|ين){E}", norm):
        trig = m.group(1)
        stem_full, end = m.group(2), m.group(3)
        word = stem_full + end
        body = stem_full[1:]  # الجذر بعد ياء/تاء المضارعة
        if end == "ين":
            if stem_full.startswith("ت") and len(body) >= 3 and not body.endswith("ا"):
                yield (m.start(2), m.end(3), None, "نحو",
                       f"«{trig} {word}»: إن كان للمخاطبة فتُحذف النون بعد الجازم والناصب", "تنبيه")
            continue
        # المفرد القصير: يكون/يصون/يهون (4 حروف) — النون أصلية لا نون رفع.
        if len(word) <= 4:
            continue
        # المفرد المزيد بالألف: يتعاون/يتسامح — الألف قبل النون أصلية.
        if body.endswith("ا"):
            continue
        # بقية الجذر أقصر من حرفين: ليس جمعاً (حماية إضافية).
        if len(body) < 2:
            continue
        if end == "ون":
            right = word[:-1] + "ا"   # يقولون ← يقولوا
        else:  # ان → ا للمثنى: يكتبان ← يكتبا
            right = word[:-1]          # حذف نون الرفع
        yield (m.start(2), m.end(3), right, "نحو",
               f"«{trig} {word}»: الأفعال الخمسة تُجزم وتُنصب بحذف النون ← «{trig} {right}»", "خطأ")


# المثنى المبتدأ المؤخر بعد خبر مقدم (للدولة الأموية شبهتان): مرفوع بالألف لا بالياء.
# ضيقة عمداً: «شبهتين» وحدها، فالمنصوب الصحيح («استعرض شبهتين») لا يُمس.
KHABAR_PREPS = set("""عن إلى الى من في على مع ضد حول خلال بين قبل بعد منذ حتى""".split())


def rule_dual_nominative(norm):
    for m in re.finditer(rf"{B}(ل(?:ل)?دول(?:ة|تين)?)\s+([{AR_LET}]+)\s+(شبهتين){E}", norm):
        if _bare(m.group(2)) in KHABAR_PREPS or m.group(2) in KHABAR_PREPS:
            continue   # «للدولتين عن شبهتين»: مجرور صحيح بعد حرف جر
        yield (m.start(3), m.end(3), "شبهتان", "نحو",
               f"«{m.group(1)} {m.group(2)} شبهتين»: المبتدأ المؤخر مثنى مرفوع ← «شبهتان»", "خطأ")


# تنوين الفتح على الهمزة المتطرفة: جزءًا، بناءً. يعمل على النص المشكول.
def rule_tanween(diac):
    for m in re.finditer(rf"([{AR}])ء([ً-ْ]*)ا([ً]?){E}", diac):
        prev = m.group(1)
        if prev not in "؀-ۿ" and not ("؀" <= prev <= "ۿ"):
            continue
        if prev == "ا":   # بناءا ← بناءً: لا ألف بعد همزة قبلها ألف
            right = prev + "ءً"
        else:             # جزءا / جزءاً ← جزءًا
            right = prev + "ءًا"
        if diac[m.start():m.end()] != right:
            ws = m.start()
            while ws > 0 and re.match(rf"[{AR_LET}\u064B-\u0652]", diac[ws - 1]):
                ws -= 1
            head = diac[ws:m.start()]
            yield (m.start(), m.end(), right, "إملاء",
                   f"«{head}{diac[m.start():m.end()]}» ← «{head}{right}»: تنوين الفتح على الهمزة", "خطأ")


# همزة الوصل بالوزن: مصادر الخماسي والسداسي (افتعال، انفعال، استفعال) تبدأ بألف وصل.
# مصدر الرباعي (إفعال: إنجاز، إنتاج) خمسة أحرف فلا يدخل في الوزن.
_L = f"[{AR_LET}]"
WASL_RE = re.compile(rf"{B}([وف]?(?:بال|كال|لل|ال|[بكل])?)([أإ])({_L}ت{_L}ا{_L}|ن{_L}{_L}ا{_L}|ست{_L}{_L}ا{_L})"
                     rf"(ة|ات|ي|ية|يا|ه|ها|هم)?{E}")


def rule_hamza_wasl(norm):
    for m in WASL_RE.finditer(norm):
        word = m.group(0)
        right = "ا"
        yield (m.start(2), m.end(2), right, "إملاء",
               f"«{word}» ← «{m.group(1)}ا{m.group(3)}{m.group(4) or ''}»: همزة وصل في مصدر الخماسي والسداسي",
               "خطأ")


# «للعدين/العدين» ← «للعديد/العديد»: ياء «العديد» ساقطة.
# قاعدة مستقلة لا SPELL: مفتاح SPELL بلا «ال» يلتهم باء «بعدين»، ومفتاحه بها
# يضاعف اللام إذا سبقته سابقة «لل»، أما المفتاحان الصريحان فآمنان من الجهتين.
ADEED = {"للعدين": "للعديد", "العدين": "العديد"}


def rule_adeed(norm):
    for m in re.finditer(rf"{B}(للعدين|العدين){E}", norm):
        w = m.group(1)
        yield (m.start(1), m.end(1), ADEED[w], "إملاء",
               f"«{w}» ← «{ADEED[w]}»", "خطأ")


RULES = [rule_spell, rule_ala, rule_anna, rule_number, rule_five_verbs, rule_dual_nominative, rule_adeed, rule_hamza_wasl]


# ---------------------------------------------------------------- الاختلاق

def norm_digits(s):
    s = s.translate(str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹٫٬٪", "01234567890123456789.,%"))
    return s


def numbers_of(s):
    out = []
    for n in re.findall(r"\d+(?:[.,]\d+)*", norm_digits(s)):
        if re.fullmatch(r"\d{1,3}(?:,\d{3})+", n):
            n = n.replace(",", "")
        out.append(n.replace(",", "."))
    return out


def _fset(s):
    return {fold(w) for w in s.split()}


FACT_WORDS = {
    "عدد": _fset("""واحد واحدة اثنان اثنين اثنتان اثنتين ثلاث ثلاثة أربع أربعة خمس خمسة ست ستة سبع
سبعة ثمان ثماني ثمانية تسع تسعة عشر عشرة عشرون عشرين ثلاثون ثلاثين أربعون أربعين خمسون خمسين ستون
ستين سبعون سبعين ثمانون ثمانين تسعون تسعين مئة مائة مئتين مئتان مئات ألف ألفين ألفان ألفي آلاف
مليون مليوني مليونين مليونان ملايين مليار مليارين ملياري مليارات نصف ربع ثلث ضعف أضعاف المئة المائة"""),
    "تاريخ": _fset("""يناير فبراير مارس أبريل ابريل إبريل مايو يونيو يونيه يوليو يوليه أغسطس اغسطس
سبتمبر أكتوبر اكتوبر نوفمبر ديسمبر كانون شباط آذار اذار نيسان أيار ايار حزيران تموز أيلول ايلول
تشرين محرم صفر جمادى رجب شعبان رمضان شوال القعدة الحجة السبت الأحد الاحد الاثنين الإثنين الثلاثاء
الأربعاء الاربعاء الخميس الجمعة أمس غدا"""),
    "عملة": _fset("""ريال ريالات دولار دولارات يورو درهم دراهم دينار دنانير جنيه جنيهات ليرة ليرات
روبية فرنك"""),
}
STOP = _fset("""في من على عن إلى الى مع هذا هذه ذلك تلك التي الذي الذين هو هي هم هن أن إن ان أو او
ثم قد لقد لا لم لن ما كل كان كانت يكون تكون بعد قبل عند حتى كما لكن بل إذا اذا لأن لان أي أيضا
غير بين فيه فيها منه منها عليه عليها له لها لهم به بها هنا هناك جدا كثير قليل نفس نفسه جميع بعض
كذلك لذلك وهو وهي يوم""")
ENTITY_CUES = _fset("""شركة شركه مدينة منطقة محافظة جامعة وزارة هيئة بنك مصرف منصة تطبيق مشروع مؤسسة
مستشفى مدرسة نادي فريق السيد السيدة الدكتور الأستاذ المهندس الأمير الملك الرئيس الوزير الشيخ في""")
PREFIX_RE = re.compile(r"^(?:وال|فال|بال|كال|لل|ال|و|ف|ب|ك|ل)")
SUFFIX_RE = re.compile(r"(?:هما|كما|ها|هم|هن|كم|نا|ات|ون|ين|ان|ه|ي)$")


def stem(w):
    w = fold(w)
    s = PREFIX_RE.sub("", w) if len(w) > 4 else w
    s2 = SUFFIX_RE.sub("", s) if len(s) > 4 else s
    return s2 or s


def fact_key(w):
    w = fold(w)
    for p in ("وب", "وال", "بال", "و", "ب", "ل", "ف"):
        if w.startswith(p) and len(w) - len(p) >= 2 and any(w[len(p):] in v for v in FACT_WORDS.values()):
            return w[len(p):]
    return w


def check_source(r, norm, src_text):
    src, _ = normalize(src_text)
    src_nums = set(numbers_of(src))
    for n in dict.fromkeys(numbers_of(norm)):
        if n not in src_nums:
            r.add("خطأ", "اختلاق", f"الرقم {n} غير موجود في الأصل: احذفه أو اسأل عنه")
    if re.search(r"[%٪]|بالمئة|بالمائة|في المئة|في المائة", norm) and not re.search(
            r"[%٪]|بالمئة|بالمائة|في المئة|في المائة", src):
        r.add("خطأ", "اختلاق", "نسبة مئوية غير موجودة في الأصل")

    src_toks = [m.group(0) for m in TOK.finditer(src)]
    src_keys = {fact_key(w) for w in src_toks}
    src_stems = {stem(w) for w in src_toks} | {fold(w) for w in src_toks}
    toks = [(m.start(), m.group(0)) for m in TOK.finditer(norm)]
    seen = set()
    for kind, vocab in FACT_WORDS.items():
        for _, w in toks:
            k = fact_key(w)
            if k in vocab and k not in src_keys and k not in seen:
                seen.add(k)
                r.add("خطأ", "اختلاق", f"«{w}» ({kind}) غير موجود في الأصل: احذفه أو اسأل عنه")

    named, fresh = [], []
    for i, (pos, w) in enumerate(toks):
        f = fold(w)
        if len(f) < 3 or f in STOP or fact_key(w) in seen or stem(w) in src_stems or f in src_stems:
            continue
        prev = fold(toks[i - 1][1]) if i > 0 else ""
        prev_k = PREFIX_RE.sub("", prev) if prev not in ENTITY_CUES else prev
        if (prev in ENTITY_CUES or prev_k in ENTITY_CUES) and not (prev == "في" and f.startswith("ال")):
            named.append(w)
        else:
            fresh.append(w)
    for w in dict.fromkeys(named):
        r.add("تنبيه", "اختلاق محتمل", f"اسم أو جهة غير موجودة في الأصل: «{w}»")
    fresh = list(dict.fromkeys(fresh))
    if fresh:
        more = f" و{len(fresh) - 15} غيرها" if len(fresh) > 15 else ""
        r.add("تنبيه", "اختلاق محتمل",
              "كلمات لا توجد في الأصل، تأكد أنها لا تحمل معلومة جديدة: " + "، ".join(fresh[:15]) + more)


# ---------------------------------------------------------------- الفحص

class Report:
    def __init__(self):
        self.items = []

    def add(self, level, kind, msg, text=None, a=None, b=None, fix=None):
        it = {"level": level, "kind": kind, "msg": msg}
        if text is not None and a is not None:
            it["line"] = line_col(text, a)
            it["at"] = snippet(text, a, b)
        if fix:
            it["fix"] = fix
        self.items.append(it)

    @property
    def blocking(self):
        return [i for i in self.items if i["level"] == "خطأ"]

    @property
    def warnings(self):
        return [i for i in self.items if i["level"] == "تنبيه"]


MARKER_PRE = r"(?:[وف]?(?:بال|كال|لل|ال|ب)?)"


def find_phrase(folded, phrase):
    p = re.escape(phrase).replace(r"\ ", r"\s+")
    # و ف ب و«ال» وما يتركب منها تُقبل قبل العبارة: «الحل الثوري» كـ«حل ثوري»
    return re.finditer(rf"(?<![{AR_LET}\w]){MARKER_PRE}{p}", folded)


def rule_findings(text):
    """كل ما تجده قواعد الإملاء والنحو، بمواضعه في النص الأصلي."""
    norm, idx = normalize(text)
    diac, didx = normalize(text, keep_diac=True)
    found = []

    def to_orig(a, b, imap, src):
        oa = imap[a]
        ob = imap[b - 1] + 1
        while ob < len(text) and (text[ob] in DIAC_CHARS or text[ob] == TATWEEL):
            ob += 1
        return oa, ob

    for rule in RULES:
        for a, b, right, kind, msg, level in rule(norm):
            oa, ob = to_orig(a, b, idx, norm)
            found.append((oa, ob, right, kind, msg, level, a, b, "n"))
    for a, b, right, kind, msg, level in rule_tanween(diac):
        oa, ob = didx[a], didx[b - 1] + 1
        found.append((oa, ob, right, kind, msg, level, a, b, "d"))
    return norm, diac, found


def check(text, words_target=None, lines_target=None, source=None, en_lines=True,
          strict_style=False):
    r = Report()
    norm, diac, found = rule_findings(text)
    folded = norm.translate(str.maketrans("أإآ", "ااا"))
    style = "خطأ" if strict_style else "تنبيه"

    # 1. البصمات الآلية (تنبيه، ومانعة مع --strict-style)
    hits = []
    for kind, phrases in MARKERS.items():
        for ph in phrases:
            fph = strip_diac(ph).translate(str.maketrans("أإآ", "ااا"))
            for m in find_phrase(folded, fph):
                if ph in ("ثوري", "ثورية"):
                    pw = _prev_words(folded, m.start(), 1)
                    if pw and fold(pw[0]) in THAWRI_OK:
                        continue   # نسبة إلى علم (سفيان الثوري) لا ترجمة حرفية
                hits.append((m.start(), m.end(), kind, ph))
    taken = []
    for a0, b0, kind, ph in sorted(hits, key=lambda h: (h[0], -(h[1] - h[0]))):
        if any(a0 < tb and ta < b0 for ta, tb in taken):
            continue   # «لا شك أن» و«لا شك ان»، «في الختام» و«وفي الختام»: موضع واحد
        taken.append((a0, b0))
        r.add(style, "بصمة آلية: " + kind, f"«{ph}»", norm, a0, b0,
              "احذفها أو ضع مكانها الحقيقة المحددة")

    # ترجمة حرفية بفاصل: «يلعب ... دوراً» (يلعب دوراً مهماً في/يلعب التطبيق دوراً).
    for m in re.finditer(rf"{B}(يلعب|تلعب|يلعبون|تلعبون|لعبت|يلعبا)(?:\s+[{AR_LET}]+){{1,3}}\s+(دورا|دوراً|دور){E}", folded):
        if any(m.start() < tb and ta < m.end() for ta, tb in taken):
            continue
        taken.append((m.start(), m.end()))
        r.add(style, "بصمة آلية: ترجمة حرفية", f"«{m.group(0).strip()}»", norm, m.start(), m.end(),
              "سمِّ الفعل الحقيقي: من فعل ماذا؟")

    for adv in SOFT_ADVERBS:
        for m in re.finditer(rf"{B}{adv}{E}", folded):
            if adv == "صراحة" and any(fold(t) in SAY_PREV for t in _prev_words(folded, m.start())):
                continue   # «نصت صراحة»: بصراحة النص لا حشو الخطاب
            r.add("تنبيه", "ظرف حشو", f"«{adv}»", norm, m.start(), m.end(),
                  "احذفه إلا إذا حمل معنى")

    # 2. الإملاء والنحو بقواعد السياق
    for oa, ob, right, kind, msg, level, a, b, view in found:
        t = norm if view == "n" else diac
        r.add(level, kind, msg, t, a, b, right)

    # 3. النحو النمطي الثابت
    for pat, sug, why in GRAMMAR:
        for m in re.finditer(pat, norm):
            r.add("تنبيه", "نحو", f"«{m.group(0)}»: {why}" + (f" ← «{sug}»" if sug else ""),
                  norm, m.start(), m.end())

    # 4. الترقيم والمسافات
    for m in re.finditer(rf"(?<=[{AR}])\s*,\s*(?=[{AR}])", norm):
        r.add("خطأ", "ترقيم", "فاصلة إنجليزية بين كلمات عربية ← «،»", norm, m.start(), m.end(), "،")
    for m in re.finditer(rf"(?<=[{AR}])\s*;\s*", norm):
        r.add("خطأ", "ترقيم", "فاصلة منقوطة إنجليزية ← «؛»", norm, m.start(), m.end(), "؛")
    for m in re.finditer(rf"(?<=[{AR}])\s*\?", norm):
        r.add("خطأ", "ترقيم", "علامة استفهام إنجليزية ← «؟»", norm, m.start(), m.end(), "؟")
    for m in re.finditer(r"[ \t]+([،؛؟.!:,])", norm):
        if m.group(1) == ":" and re.search(r"\d\s*$", norm[:m.start()]):
            continue
        r.add("خطأ", "مسافات", "مسافة قبل علامة الترقيم", norm, m.start(), m.end())
    for m in re.finditer(rf"([،؛؟])(?=[{AR}A-Za-z0-9])", norm):
        r.add("خطأ", "مسافات", "لا مسافة بعد علامة الترقيم", norm, m.start(), m.end())
    for m in re.finditer(rf"{B}و\s+(?=[{AR}])", norm):
        r.add("خطأ", "مسافات", "واو العطف منفصلة ← تلتصق بما بعدها", norm, m.start(), m.end())
    for m in re.finditer(r"[^\S\n]{2,}", norm):
        if norm[:m.start()].endswith("\n") or m.start() == 0:
            continue
        r.add("خطأ", "مسافات", "مسافة مزدوجة", norm, m.start(), m.end())
    for m in re.finditer(r"([!؟?])\1+|!؟|؟!", norm):
        r.add("تنبيه", "ترقيم", "علامات مكررة", norm, m.start(), m.end())

    # 5. زوائد التنسيق (الإيموجي يُفحص في النص الأصلي: رموز الربط جزء منه)
    for m in EMOJI_RE.finditer(text):
        r.add("خطأ", "تنسيق", "إيموجي", text, m.start(), m.end())
    hr_spans = [(m.start(), m.end()) for m in HR_RE.finditer(norm)]
    for m in DASH_RE.finditer(norm):
        if any(a <= m.start() < b for a, b in hr_spans):
            continue   # فاصل أفقي: تنبيه أدناه لا خطأ
        pa, pb = m.start() - 1, m.end()
        while pa >= 0 and norm[pa] in " \t":
            pa -= 1
        while pb < len(norm) and norm[pb] in " \t":
            pb += 1
        if pa >= 0 and pb < len(norm) and norm[pa] in DIGITS and norm[pb] in DIGITS:
            continue   # مدى رقمي (ص ١٧٣–١٧٤): شرطة مشروعة
        r.add("خطأ", "تنسيق", "شرطة طويلة", norm, m.start(), m.end())
    for a, b in hr_spans:
        r.add("تنبيه", "تنسيق", "فاصل أفقي (مقبول في المستندات فقط)", norm, a, b)
    for m in MD_HEAD.finditer(norm):
        r.add("تنبيه", "تنسيق", "ترويسة ماركداون (مقبولة في المستندات فقط)", norm, m.start(), m.end())
    for m in MD_BOLD.finditer(norm):
        r.add("تنبيه", "تنسيق", "خط عريض", norm, m.start(), m.end())
    for m in PREAMBLE.finditer(norm):
        r.add("خطأ", "تنسيق", "مقدمة عن النص بدل النص نفسه", norm, m.start(), m.end())
    bullets = BULLET.findall(norm)
    if len(bullets) >= 3 and len(sentences(norm)) <= len(bullets) + 2:
        r.add("تنبيه", "بنية", f"{len(bullets)} نقاط: إن كان النص سرداً فحوّلها إلى جمل متصلة")

    # 6. الإنجليزية داخل السطر العربي (تفضيل المستخدم: سطر مستقل)
    if en_lines:
        for ln_no, ln in enumerate(norm.split("\n"), 1):
            if re.search(f"[{AR}]", ln) and re.search(r"[A-Za-z]", ln):
                ens = re.findall(r"[A-Za-z][A-Za-z0-9.+#'&/-]*(?:\s+[A-Za-z0-9.+#'&/-]+)*", ln)
                if ens and not ln.lstrip().startswith(("http", "#")):
                    r.add("خطأ", "اتجاه", "كلمة إنجليزية داخل سطر عربي ← سطر مستقل: "
                          + "، ".join(dict.fromkeys(ens)))
                    r.items[-1]["line"] = ln_no

    # 7. البنى (أسلوب)
    for m in re.finditer(rf"ليس[ت]?\s[^.،؟\n]{{1,40}}[،,]?\s*(بل|وإنما|إنما)\s", norm):
        r.add(style, "بصمة آلية: بنية", "«ليس … بل …»: قل الثاني مباشرة", norm, m.start(), m.end())
    for m in re.finditer(rf"([{AR_LET}]+)،\s*([{AR_LET}]+)،\s*و([{AR_LET}]+)", norm):
        a, b2, c = m.groups()
        if max(len(a), len(b2), len(c)) <= 8:
            r.add("تنبيه", "بصمة آلية: ثلاثية", f"«{m.group(0)}»: اثنتان أو حقيقة واحدة أصدق",
                  norm, m.start(), m.end())
    for m in re.finditer(rf"([{AR_LET}]{{2,}})\s+و([{AR_LET}]{{2,}})\s+و([{AR_LET}]{{2,}})", norm):
        r.add("تنبيه", "بصمة آلية: ثلاثية", f"«{m.group(0)}»", norm, m.start(), m.end())
    for m in re.finditer(rf"^[^\n؟]{{0,60}}؟\s*\n?\s*(لأن|الجواب|السبب)", norm, re.M):
        r.add(style, "بصمة آلية: بنية", "سؤال بلاغي يتبعه جوابه: احذف السؤال", norm, m.start(), m.end())

    # 8. الإيقاع
    sents = sentences(norm)
    lens = [len(words(s)) for s in sents]
    if len(lens) >= 4:
        for i in range(len(lens) - 2):
            trio = lens[i:i + 3]
            if max(trio) - min(trio) <= 2 and min(trio) >= 4:
                r.add("تنبيه", "إيقاع", f"ثلاث جمل متتالية بطول متقارب ({trio[0]}، {trio[1]}، {trio[2]} كلمة): نوّع")
                break
        short = sum(1 for n in lens if n <= 2)
        if short >= 3:
            r.add("تنبيه", "إيقاع", f"{short} جمل من كلمة أو كلمتين: تقطيع درامي، أعد الجمل لطولها")

    # 9. الطول
    nw = len(words(norm))
    if words_target:
        lo, hi = int(words_target * 0.9), int(round(words_target * 1.1))
        if not lo <= nw <= hi:
            r.add("خطأ", "طول", f"{nw} كلمة والمطلوب {words_target} (المسموح {lo} إلى {hi})")
    if lines_target:
        nl = len([l for l in norm.split("\n") if l.strip()])
        if nl != lines_target:
            r.add("خطأ", "طول", f"{nl} سطر والمطلوب {lines_target}")

    # 10. المعلومات المضافة مقارنة بالأصل
    if source is not None:
        check_source(r, norm, source)
        caps = set(re.findall(r"\b[A-Z][A-Za-z0-9]+\b", norm)) - set(re.findall(r"\b[A-Z][A-Za-z0-9]+\b", source))
        for c in sorted(caps):
            r.add("خطأ", "اختلاق", f"الاسم {c} غير موجود في الأصل")
        nsrc = len(words(normalize(source)[0]))
        if nw > max(40, int(nsrc * 1.25)):
            r.add("تنبيه", "طول", f"النص أطول من الأصل بأكثر من 25% ({nw} مقابل {nsrc})")

    return r, {"words": nw, "sentences": len(sents), "avg_sentence": round(statistics.mean(lens), 1) if lens else 0,
               "lines": len([l for l in norm.split("\n") if l.strip()])}


# ---------------------------------------------------------------- الإصلاح الآمن

def apply_rule_fixes(t):
    """يطبّق إصلاحات قواعد الإملاء والنحو على النص الأصلي، حتى يستقر."""
    for _ in range(4):
        _, _, found = rule_findings(t)
        edits, last = [], -1
        for oa, ob, right, *_ in sorted((f for f in found if f[2]), key=lambda f: (f[0], -f[1])):
            if oa < last or t[oa:ob] == right:
                continue
            edits.append((oa, ob, right))
            last = ob
        if not edits:
            break
        for oa, ob, right in reversed(edits):
            t = t[:oa] + right + t[ob:]
    return t


def fix(text, en_lines=True):
    t = canon(text)
    t = EMOJI_RE.sub("", t)
    t = re.sub(r"(?<![0-9٠-٩])\s*[—–‒―]\s*(?![0-9٠-٩])|(?<![0-9٠-٩])\s+--\s+(?![0-9٠-٩])", "، ", t)
    t = MD_BOLD.sub(lambda m: m.group(0)[2:-2], t)
    t = re.sub(rf"(?<=[{AR}])\s*,\s*", "، ", t)
    t = re.sub(rf"(?<=[{AR}])\s*;\s*", "؛ ", t)
    t = re.sub(rf"(?<=[{AR}])\s*\?", "؟", t)
    t = re.sub(r"[ \t]+([،؛؟!.])", r"\1", t)
    t = re.sub(rf"([،؛])(?=[{AR}A-Za-z0-9])", r"\1 ", t)
    t = re.sub(rf"{B}و\s+(?=[{AR}])", "و", t)
    t = re.sub(r"([!؟])\1+", r"\1", t)
    t = apply_rule_fixes(t)
    if en_lines:
        out = []
        for ln in t.split("\n"):
            if re.search(f"[{AR}]", ln) and re.search(r"[A-Za-z]", ln) and not ln.lstrip().startswith("http"):
                parts = re.split(r"([A-Za-z][A-Za-z0-9.+#'&/-]*(?:\s+[A-Za-z0-9.+#'&/-]+)*)", ln)
                for p in parts:
                    p = p.strip()
                    if p:
                        out.append(p)
            else:
                out.append(ln)
        t = "\n".join(out)
    t = re.sub(r"[^\S\n]{2,}", " ", t)
    t = re.sub(r"[ \t]+\n", "\n", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    return t.strip() + "\n"


# ---------------------------------------------------------------- الفرق

def diff(a, b):
    wa, wb = re.findall(r"\S+", a), re.findall(r"\S+", b)
    sm = difflib.SequenceMatcher(None, wa, wb)
    rows = []
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op == "equal":
            continue
        rows.append({"op": {"replace": "تعديل", "delete": "حذف", "insert": "إضافة"}[op],
                     "before": " ".join(wa[i1:i2]), "after": " ".join(wb[j1:j2])})
    return rows, round(sm.ratio() * 100)


# ---------------------------------------------------------------- الإخراج

def print_report(r, stats, as_json):
    if as_json:
        print(json.dumps({"stats": stats, "errors": r.blocking, "warnings": r.warnings,
                          "clean": not r.blocking}, ensure_ascii=False, indent=1))
        return
    print(f"الكلمات {stats['words']} · الجمل {stats['sentences']} · متوسط الجملة {stats['avg_sentence']} · الأسطر {stats['lines']}")
    if not r.items:
        print("نظيف: لا أخطاء ولا تنبيهات.")
        return
    for lvl, items in (("أخطاء مانعة", r.blocking), ("تنبيهات", r.warnings)):
        if not items:
            continue
        print(f"\n{lvl} ({len(items)}):")
        for it in items:
            loc = f"س{it['line']} " if "line" in it else ""
            at = f"  ⟵ {it['at']}" if "at" in it else ""
            print(f"  [{it['kind']}] {loc}{it['msg']}{at}")
    print("\nالنتيجة: " + ("نظيف للتسليم" if not r.blocking else "لا يُسلَّم قبل إصلاح الأخطاء المانعة"))


def main():
    ap = argparse.ArgumentParser(description="فاحص Arab Writer")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("check", "fix", "stats"):
        p = sub.add_parser(name)
        p.add_argument("file")
        p.add_argument("--words", type=int)
        p.add_argument("--lines", type=int)
        p.add_argument("--source")
        p.add_argument("--keep-en", action="store_true", help="لا تفرض سطراً مستقلاً للإنجليزية")
        p.add_argument("--strict-style", action="store_true", help="البصمات الآلية أخطاء مانعة")
        p.add_argument("--json", action="store_true")
        p.add_argument("-o", "--out")
    d = sub.add_parser("diff")
    d.add_argument("before")
    d.add_argument("after")
    d.add_argument("--json", action="store_true")
    a = ap.parse_args()

    if a.cmd == "diff":
        rows, sim = diff(read(a.before), read(a.after))
        if a.json:
            print(json.dumps({"similarity": sim, "changes": rows}, ensure_ascii=False, indent=1))
        else:
            print(f"التشابه {sim}% · التغييرات {len(rows)}")
            for x in rows:
                print(f"  {x['op']}: «{x['before']}» ← «{x['after']}»")
        return 0

    text = read(a.file)
    en = not a.keep_en
    if a.cmd == "stats":
        _, st = check(text, en_lines=False)
        print(json.dumps(st, ensure_ascii=False) if a.json else
              f"الكلمات {st['words']} · الجمل {st['sentences']} · متوسط الجملة {st['avg_sentence']} · الأسطر {st['lines']}")
        return 0
    if a.cmd == "fix":
        text = fix(text, en_lines=en)
        if a.out:
            with open(a.out, "w", encoding="utf-8") as f:
                f.write(text)
        else:
            sys.stdout.write(text)
            print("\n---")
    src = read(a.source) if a.source else None
    r, st = check(text, a.words, a.lines, src, en_lines=en, strict_style=a.strict_style)
    print_report(r, st, a.json)
    return 1 if r.blocking else 0


if __name__ == "__main__":
    sys.exit(main())
