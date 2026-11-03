#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ar_lint.py — الفاحص الآلي لـ Arab Writer.

يفحص النص العربي فحصاً حتمياً قبل التسليم: بصمات الذكاء الاصطناعي، الأخطاء
الإملائية الشائعة، الترقيم والمسافات، زوائد التنسيق، الكلمة الإنجليزية داخل
السطر العربي، رتابة الإيقاع، والطول المطلوب. ويصلح الآمن منها تلقائياً.

الاستعمال:
    python3 ar_lint.py check  text.txt                 تقرير
    python3 ar_lint.py check  text.txt --words 60      مع قفل الطول (±10%)
    python3 ar_lint.py check  text.txt --lines 3       قفل عدد الأسطر
    python3 ar_lint.py check  text.txt --source src.txt  كشف المعلومات المضافة
    python3 ar_lint.py fix    text.txt -o out.txt      إصلاح آمن ثم تقرير
    python3 ar_lint.py diff   before.txt after.txt     ماذا تغيّر
    python3 ar_lint.py stats  text.txt                 عدّاد الكلمات والجمل
    أي أمر يقبل - بدل اسم الملف للقراءة من الإدخال القياسي، و --json للمخرج الآلي.

رمز الخروج: 0 نظيف، 1 فيه أخطاء مانعة، 2 خطأ في الاستعمال.
"""
import argparse
import difflib
import json
import re
import statistics
import sys
import unicodedata

# ---------------------------------------------------------------- أدوات عامة

AR = "؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿"
DIAC = re.compile("[ً-ْٰـ]")  # التشكيل والتطويل
WORD_RE = re.compile(rf"[{AR}A-Za-z0-9٠-٩]+")
B = rf"(?<![{AR}\w])"    # بداية كلمة
E = rf"(?![{AR}\w])"     # نهاية كلمة


def strip_diac(s):
    return DIAC.sub("", s)


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
    line = text.count("\n", 0, idx) + 1
    return line


def snippet(text, a, b, pad=18):
    s = text[max(0, a - pad):min(len(text), b + pad)].replace("\n", " ⏎ ")
    return s.strip()


# ---------------------------------------------------------------- القوائم

# بصمات آلية: (عبارة، فئة، اقتراح). العبارة تُطابق بعد إزالة التشكيل.
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
        "تغير قواعد اللعبة", "يعيد تشكيل", "تعيد تشكيل", "يعيد تعريف", "تعيد تعريف",
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

# أخطاء إملائية مؤكدة: (الخطأ، الصواب). المطابقة بحدود الكلمة وبعد إزالة التشكيل.
# لا تُضاف هنا كلمة لها قراءة صحيحة أخرى (مثل "علي" اسم علم، "ان" في العامية).
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
    "مبادىء": "مبادئ", "قارىء": "قارئ", "شاطىء": "شاطئ", "بناءا": "بناءً",
    "سماءا": "سماءً", "جزءا": "جزءاً", "خطئا": "خطأً",
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
}

# السوابق التي تلتصق بالكلمة: و ف ب ك ل وال التعريف وما يتركب منها
PRE = r"[وف]?(?:بال|كال|لل|ال|[بكل])?"

# أخطاء نحوية شائعة نمطية (تحذير مع اقتراح، لا إصلاح آلي)
GRAMMAR = [
    (r"أعلن الشركة", "أعلنت الشركة", "تأنيث الفعل مع الفاعل المؤنث"),
    (r"(قال|أعلن|أطلق|كشف|أكد) (الوزارة|الهيئة|الشركة|المنصة|الجامعة)", None,
     "الفعل يؤنث مع الفاعل المؤنث"),
    (r"هؤلاء ال(أجهزة|كتب|سيارات|تطبيقات|ميزات|أدوات|ملفات)", "هذه ال…",
     "هؤلاء للعاقل، هذه لجمع غير العاقل"),
    (r"ثلاثة (ميزات|سنوات|نساء|ساعات|دقائق|طرق|أدوات|مرات)", "ثلاث …", "العدد يخالف المعدود"),
    (r"(أربعة|خمسة|ستة|سبعة|ثمانية|تسعة) (ميزات|سنوات|نساء|ساعات|دقائق|طرق|أدوات|مرات)",
     None, "العدد يخالف المعدود: المعدود مؤنث فالعدد مذكر الصيغة"),
    (r"(ثلاث|أربع|خمس|ست|سبع|ثماني|تسع) (رجال|أيام|مهندسين|مستخدمين|أشهر|ملفات|تطبيقات)",
     None, "العدد يخالف المعدود: المعدود مذكر فالعدد بالتاء"),
    (r"لم (يكتبون|يذهبون|يعرفون|يفهمون|يستخدمون)", None, "الأفعال الخمسة تُجزم بحذف النون"),
    (r"لن (يكتبون|يذهبون|يعرفون|يفهمون|يستخدمون)", None, "الأفعال الخمسة تُنصب بحذف النون"),
    (r"المدير المدرسة|الوزارة الصحة|المدير الشركة", None, "لا تدخل ال على المضاف"),
    (r"عشرون (أيام|ساعات|دقائق|سنوات)", None, "المعدود بعد العقود مفرد منصوب"),
    (r"يؤثر على", "يؤثر في", "حرف الجر الصحيح"),
    (r"بحاجة ل(?=[{AR}])".replace("{AR}", AR), "بحاجة إلى", "حرف الجر الصحيح"),
    (r"يتكون على", "يتكون من", "حرف الجر الصحيح"),
]

EMOJI_RE = re.compile(
    "[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0001F000-\U0001F2FF"
    "\U00002B00-\U00002BFF\U0000FE0F\U0000200D✅❌✔✖]"
)
DASH_RE = re.compile(r"[—–‒―]|--")
MD_HEAD = re.compile(r"^\s{0,3}#{1,6}\s", re.M)
MD_BOLD = re.compile(r"\*\*[^*\n]+\*\*|__[^_\n]+__")
MD_ITAL = re.compile(r"(?<![*\w])\*[^*\n]+\*(?!\*)")
BULLET = re.compile(r"^\s*([-*•●▪✓✅]|\d+[.)])\s+", re.M)
PREAMBLE = re.compile(
    r"^\s*(إليك|اليك|هذا هو|هذه هي|فيما يلي|في ما يلي|تفضل|بالتأكيد|بكل سرور|حسنا|طبعا)[^\n]{0,40}[:：]?\s*$",
    re.M,
)
EN_IN_AR_LINE = re.compile(rf"[{AR}][^\n]*?\b([A-Za-z][A-Za-z0-9.+#'&-]*(?:\s+[A-Za-z0-9.+#'&-]+)*)\b|"
                           rf"\b([A-Za-z][A-Za-z0-9.+#'&-]*(?:\s+[A-Za-z0-9.+#'&-]+)*)\b[^\n]*?[{AR}]")


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


def find_phrase(norm, phrase):
    p = re.escape(strip_diac(phrase)).replace(r"\ ", r"\s+")
    # الواو والفاء والباء الملتصقة تُقبل قبل العبارة
    return re.finditer(rf"(?<![{AR}\w])(?:[وفب])?{p}", norm)


def check(text, words_target=None, lines_target=None, source=None, en_lines=True):
    r = Report()
    norm = strip_diac(text)
    # نسخة موحّدة الألف لمطابقة البصمات (أ إ آ → ا) مع بقاء المواضع ثابتة الطول
    folded = norm.translate(str.maketrans("أإآ", "ااا"))

    # 1. البصمات الآلية
    for kind, phrases in MARKERS.items():
        for ph in phrases:
            fph = strip_diac(ph).translate(str.maketrans("أإآ", "ااا"))
            for m in find_phrase(folded, fph):
                r.add("خطأ", "بصمة آلية: " + kind, f"«{ph}»", norm, m.start(), m.end(),
                      "احذفها أو ضع مكانها الحقيقة المحددة")

    for adv in SOFT_ADVERBS:
        for m in re.finditer(rf"{B}{adv}{E}", folded):
            r.add("تنبيه", "ظرف حشو", f"«{adv}»", norm, m.start(), m.end(),
                  "احذفه إلا إذا حمل معنى")

    # 2. الإملاء
    for wrong, right in SPELL.items():
        w = re.escape(strip_diac(wrong)).replace(r"\ ", r"\s+")
        for m in re.finditer(rf"{B}({PRE})({w}){E}", norm):
            r.add("خطأ", "إملاء", f"«{m.group(0)}» ← «{m.group(1)}{right}»", norm,
                  m.start(), m.end(), f"{m.group(1)}{right}")

    # 3. النحو النمطي
    for pat, sug, why in GRAMMAR:
        for m in re.finditer(pat, norm):
            r.add("تنبيه", "نحو", f"«{m.group(0)}»: {why}" + (f" ← «{sug}»" if sug else ""),
                  norm, m.start(), m.end())

    # 4. الترقيم والمسافات
    for m in re.finditer(rf"(?<=[{AR}])\s*,\s*(?=[{AR}])", text):
        r.add("خطأ", "ترقيم", "فاصلة إنجليزية بين كلمات عربية ← «،»", text, m.start(), m.end(), "،")
    for m in re.finditer(rf"(?<=[{AR}])\s*;\s*", text):
        r.add("خطأ", "ترقيم", "فاصلة منقوطة إنجليزية ← «؛»", text, m.start(), m.end(), "؛")
    for m in re.finditer(rf"(?<=[{AR}])\s*\?", text):
        r.add("خطأ", "ترقيم", "علامة استفهام إنجليزية ← «؟»", text, m.start(), m.end(), "؟")
    for m in re.finditer(r"[ \t]+([،؛؟.!:,])", text):
        if m.group(1) == ":" and re.search(r"\d\s*$", text[:m.start()]):
            continue
        r.add("خطأ", "مسافات", "مسافة قبل علامة الترقيم", text, m.start(), m.end())
    for m in re.finditer(rf"([،؛؟])(?=[{AR}A-Za-z0-9])", text):
        r.add("خطأ", "مسافات", "لا مسافة بعد علامة الترقيم", text, m.start(), m.end())
    for m in re.finditer(rf"{B}و\s+(?=[{AR}])", text):
        r.add("خطأ", "مسافات", "واو العطف منفصلة ← تلتصق بما بعدها", text, m.start(), m.end())
    for m in re.finditer(r"[^\S\n]{2,}", text):
        if text[:m.start()].endswith("\n") or m.start() == 0:
            continue
        r.add("خطأ", "مسافات", "مسافة مزدوجة", text, m.start(), m.end())
    for m in re.finditer(r"([!؟?])\1+|!؟|؟!", text):
        r.add("تنبيه", "ترقيم", "علامات مكررة", text, m.start(), m.end())

    # 5. زوائد التنسيق
    for m in EMOJI_RE.finditer(text):
        r.add("خطأ", "تنسيق", "إيموجي", text, m.start(), m.end())
    for m in DASH_RE.finditer(text):
        r.add("خطأ", "تنسيق", "شرطة طويلة", text, m.start(), m.end())
    for m in MD_HEAD.finditer(text):
        r.add("تنبيه", "تنسيق", "ترويسة ماركداون (مقبولة في المستندات فقط)", text, m.start(), m.end())
    for m in MD_BOLD.finditer(text):
        r.add("تنبيه", "تنسيق", "خط عريض", text, m.start(), m.end())
    for m in PREAMBLE.finditer(norm):
        r.add("خطأ", "تنسيق", "مقدمة عن النص بدل النص نفسه", norm, m.start(), m.end())
    bullets = BULLET.findall(text)
    if len(bullets) >= 3 and len(sentences(text)) <= len(bullets) + 2:
        r.add("تنبيه", "بنية", f"{len(bullets)} نقاط: إن كان النص سرداً فحوّلها إلى جمل متصلة")

    # 6. الإنجليزية داخل السطر العربي (تفضيل المستخدم: سطر مستقل)
    if en_lines:
        for ln_no, ln in enumerate(text.split("\n"), 1):
            if re.search(f"[{AR}]", ln) and re.search(r"[A-Za-z]", ln):
                ens = re.findall(r"[A-Za-z][A-Za-z0-9.+#'&/-]*(?:\s+[A-Za-z0-9.+#'&/-]+)*", ln)
                if ens and not ln.lstrip().startswith(("http", "#")):
                    r.add("خطأ", "اتجاه", "كلمة إنجليزية داخل سطر عربي ← سطر مستقل: "
                          + "، ".join(dict.fromkeys(ens)))
                    r.items[-1]["line"] = ln_no

    # 7. البنى
    for m in re.finditer(rf"ليس[ت]?\s[^.،؟\n]{{1,40}}[،,]?\s*(بل|وإنما|إنما)\s", norm):
        r.add("خطأ", "بصمة آلية: بنية", "«ليس … بل …»: قل الثاني مباشرة", norm, m.start(), m.end())
    for m in re.finditer(rf"([{AR}]+)،\s*([{AR}]+)،\s*و([{AR}]+)", norm):
        a, b2, c = m.groups()
        if max(len(a), len(b2), len(c)) <= 8:
            r.add("تنبيه", "بصمة آلية: ثلاثية", f"«{m.group(0)}»: اثنتان أو حقيقة واحدة أصدق",
                  norm, m.start(), m.end())
    for m in re.finditer(rf"([{AR}]{{2,}})\s+و([{AR}]{{2,}})\s+و([{AR}]{{2,}})", norm):
        r.add("تنبيه", "بصمة آلية: ثلاثية", f"«{m.group(0)}»", norm, m.start(), m.end())
    for m in re.finditer(rf"^[^\n؟]{{0,60}}؟\s*\n?\s*(لأن|الجواب|السبب)", norm, re.M):
        r.add("خطأ", "بصمة آلية: بنية", "سؤال بلاغي يتبعه جوابه: احذف السؤال", norm, m.start(), m.end())

    # 8. الإيقاع
    sents = sentences(text)
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
    nw = len(words(text))
    if words_target:
        lo, hi = int(words_target * 0.9), int(round(words_target * 1.1))
        if not lo <= nw <= hi:
            r.add("خطأ", "طول", f"{nw} كلمة والمطلوب {words_target} (المسموح {lo} إلى {hi})")
    if lines_target:
        nl = len([l for l in text.split("\n") if l.strip()])
        if nl != lines_target:
            r.add("خطأ", "طول", f"{nl} سطر والمطلوب {lines_target}")

    # 10. المعلومات المضافة مقارنة بالأصل
    if source is not None:
        src = strip_diac(source)
        nums_src = set(re.findall(r"\d+(?:[.,،]\d+)?", src))
        for n in dict.fromkeys(re.findall(r"\d+(?:[.,،]\d+)?", norm)):
            if n not in nums_src:
                r.add("خطأ", "اختلاق", f"الرقم {n} غير موجود في الأصل: احذفه أو اسأل عنه")
        src_words = set(w for w in words(src))
        caps = set(re.findall(r"\b[A-Z][A-Za-z0-9]+\b", norm)) - set(re.findall(r"\b[A-Z][A-Za-z0-9]+\b", src))
        for c in caps:
            r.add("خطأ", "اختلاق", f"الاسم {c} غير موجود في الأصل")
        if nw > max(40, int(len(words(src)) * 1.25)):
            r.add("تنبيه", "طول", f"النص أطول من الأصل بأكثر من 25% ({nw} مقابل {len(words(src))})")

    return r, {"words": nw, "sentences": len(sents), "avg_sentence": round(statistics.mean(lens), 1) if lens else 0,
               "lines": len([l for l in text.split("\n") if l.strip()])}


# ---------------------------------------------------------------- الإصلاح الآمن

def fix(text, en_lines=True):
    t = text
    t = EMOJI_RE.sub("", t)
    t = re.sub(r"\s*[—–‒―]\s*|\s+--\s+", "، ", t)
    t = MD_BOLD.sub(lambda m: m.group(0)[2:-2], t)
    t = re.sub(rf"(?<=[{AR}])\s*,\s*", "، ", t)
    t = re.sub(rf"(?<=[{AR}])\s*;\s*", "؛ ", t)
    t = re.sub(rf"(?<=[{AR}])\s*\?", "؟", t)
    t = re.sub(r"[ \t]+([،؛؟!.])", r"\1", t)
    t = re.sub(rf"([،؛])(?=[{AR}A-Za-z0-9])", r"\1 ", t)
    t = re.sub(rf"{B}و\s+(?=[{AR}])", "و", t)
    t = re.sub(r"([!؟])\1+", r"\1", t)
    for wrong, right in sorted(SPELL.items(), key=lambda kv: -len(kv[0])):
        w = re.escape(wrong).replace(r"\ ", r"\s+")
        t = re.sub(rf"{B}({PRE}){w}{E}", lambda m: m.group(1) + right, t)
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
    r, st = check(text, a.words, a.lines, src, en_lines=en)
    print_report(r, st, a.json)
    return 1 if r.blocking else 0


if __name__ == "__main__":
    sys.exit(main())
