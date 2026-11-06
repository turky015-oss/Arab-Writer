package app.arabwriter.android.core

import java.util.UUID
import java.util.regex.Matcher
import java.util.regex.Pattern

// ---------- النتائج ----------

enum class IssueLevel(val label: String) { ERROR("خطأ"), WARNING("تنبيه") }

data class LintIssue(
    val level: IssueLevel,
    val kind: String,
    val message: String,
    val line: Int? = null,
    val excerpt: String? = null,
    val fix: String? = null,
    val id: String = UUID.randomUUID().toString(),
)

data class TextStats(val words: Int = 0, val sentences: Int = 0, val averageSentence: Double = 0.0, val lines: Int = 0)

data class LintReport(val issues: List<LintIssue> = emptyList(), val stats: TextStats = TextStats()) {
    val errors get() = issues.filter { it.level == IssueLevel.ERROR }
    val warnings get() = issues.filter { it.level == IssueLevel.WARNING }
    val isClean get() = errors.isEmpty()
}

data class LintOptions(
    val wordsTarget: Int? = null,
    val linesTarget: Int? = null,
    val source: String? = null,
    val englishOnOwnLine: Boolean = true,
)

// ---------- أدوات الأنماط ----------

internal object RX {
    private val cache = HashMap<String, Pattern>()

    @Synchronized
    fun p(pattern: String, flags: Int = 0): Pattern =
        cache.getOrPut("$flags|$pattern") { Pattern.compile(pattern, flags or Pattern.UNICODE_CHARACTER_CLASS) }

    fun find(pattern: String, s: String, flags: Int = 0): List<MatchResult> {
        val m = p(pattern, flags).matcher(s)
        val out = ArrayList<MatchResult>()
        while (m.find()) out.add(MatchResult(m.start(), m.end(), (0..m.groupCount()).map { m.group(it) ?: "" }))
        return out
    }

    fun test(pattern: String, s: String) = p(pattern).matcher(s).find()

    fun replace(pattern: String, s: String, tpl: String, flags: Int = 0): String = p(pattern, flags).matcher(s).replaceAll(tpl)

    fun count(pattern: String, s: String): Int {
        val m = p(pattern).matcher(s); var n = 0
        while (m.find()) n++
        return n
    }

    fun quote(s: String): String = Pattern.quote(s)
    fun tpl(s: String): String = Matcher.quoteReplacement(s)

    data class MatchResult(val start: Int, val end: Int, val groups: List<String>) {
        val value get() = groups[0]
    }
}

// ---------- الفاحص ----------

object ArabicLinter {
    private const val AR = Lexicon.AR
    private const val B = "(?<![${AR}\\w])"
    private const val E = "(?![${AR}\\w])"
    private const val PRE = "[وف]?(?:بال|كال|لل|ال|[بكل])?"
    const val EMOJI = "[\\x{1F300}-\\x{1FAFF}\\x{2600}-\\x{27BF}\\x{1F000}-\\x{1F2FF}\\x{2B00}-\\x{2BFF}\\x{FE0F}\\x{200D}✅❌✔✖]"
    private const val DASH = "[—–‒―]|--"
    private const val EN_CHUNK = "[A-Za-z][A-Za-z0-9.+#'&/-]*(?:\\s+[A-Za-z0-9.+#'&/-]+)*"

    fun stripDiacritics(s: String) = RX.replace("[\\u064B-\\u0652\\u0670\\u0640]", s, "")

    private fun fold(s: String) = s.replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا')

    fun words(s: String): List<String> = RX.find("[${AR}A-Za-z0-9\\u0660-\\u0669]+", s).map { it.value }

    fun sentences(s: String): List<String> {
        val marked = RX.replace("([.!؟?])\\s+", s, "$1\u0001")
        return marked.split('\u0001', '\n').map { it.trim() }.filter { words(it).isNotEmpty() }
    }

    private fun lineOf(text: String, loc: Int) = text.substring(0, minOf(loc, text.length)).count { it == '\n' } + 1

    private fun excerpt(text: String, start: Int, end: Int, pad: Int = 18): String {
        val a = maxOf(0, start - pad); val b = minOf(text.length, end + pad)
        return text.substring(a, b).replace("\n", " ⏎ ").trim()
    }

    fun stats(text: String): TextStats {
        val sents = sentences(text)
        val lens = sents.map { words(it).size }
        val avg = if (lens.isEmpty()) 0.0 else Math.round(lens.sum().toDouble() / lens.size * 10) / 10.0
        return TextStats(words(text).size, sents.size, avg, text.split('\n').count { it.isNotBlank() })
    }

    fun check(text: String, options: LintOptions = LintOptions()): LintReport {
        val issues = ArrayList<LintIssue>()
        val norm = stripDiacritics(text)
        val folded = fold(norm)

        fun add(level: IssueLevel, kind: String, msg: String, t: String? = null, m: RX.MatchResult? = null, fix: String? = null) {
            issues += if (t != null && m != null)
                LintIssue(level, kind, msg, lineOf(t, m.start), excerpt(t, m.start, m.end), fix)
            else LintIssue(level, kind, msg, fix = fix)
        }

        // 1. البصمات
        for ((kind, phrases) in Lexicon.markers) for (ph in phrases) {
            val f = fold(stripDiacritics(ph))
            val p = f.split(' ').joinToString("\\s+") { RX.quote(it) }
            for (m in RX.find("(?<![${AR}\\w])(?:[وفب])?$p", folded))
                add(IssueLevel.ERROR, "بصمة آلية: $kind", "«$ph»", norm, m, "احذفها أو ضع مكانها الحقيقة المحددة")
        }
        for (adv in Lexicon.softAdverbs) for (m in RX.find("$B$adv$E", folded))
            add(IssueLevel.WARNING, "ظرف حشو", "«$adv»", norm, m, "احذفه إلا إذا حمل معنى")

        // 2. الإملاء
        for ((wrong, right) in Lexicon.spelling) {
            val w = stripDiacritics(wrong).split(' ').joinToString("\\s+") { RX.quote(it) }
            for (m in RX.find("$B($PRE)($w)$E", norm)) {
                val pre = m.groups[1]
                add(IssueLevel.ERROR, "إملاء", "«${m.value}» ← «$pre$right»", norm, m, pre + right)
            }
        }

        // 3. النحو
        for ((pat, sug, why) in Lexicon.grammar) for (m in RX.find(pat, norm))
            add(IssueLevel.WARNING, "نحو", "«${m.value}»: $why" + (sug?.let { " ← «$it»" } ?: ""), norm, m)

        // 4. الترقيم والمسافات
        for (m in RX.find("(?<=[$AR])\\s*,\\s*(?=[$AR])", text)) add(IssueLevel.ERROR, "ترقيم", "فاصلة إنجليزية بين كلمات عربية ← «،»", text, m, "،")
        for (m in RX.find("(?<=[$AR])\\s*;\\s*", text)) add(IssueLevel.ERROR, "ترقيم", "فاصلة منقوطة إنجليزية ← «؛»", text, m, "؛")
        for (m in RX.find("(?<=[$AR])\\s*\\?", text)) add(IssueLevel.ERROR, "ترقيم", "علامة استفهام إنجليزية ← «؟»", text, m, "؟")
        for (m in RX.find("[ \\t]+([،؛؟.!:,])", text)) {
            if (m.groups[1] == ":" && RX.test("\\d\\s*$", text.substring(0, m.start))) continue
            add(IssueLevel.ERROR, "مسافات", "مسافة قبل علامة الترقيم", text, m)
        }
        for (m in RX.find("([،؛؟])(?=[${AR}A-Za-z0-9])", text)) add(IssueLevel.ERROR, "مسافات", "لا مسافة بعد علامة الترقيم", text, m)
        for (m in RX.find("${B}و\\s+(?=[$AR])", text)) add(IssueLevel.ERROR, "مسافات", "واو العطف منفصلة ← تلتصق بما بعدها", text, m)
        for (m in RX.find("[^\\S\\n]{2,}", text)) {
            if (m.start == 0 || text[m.start - 1] == '\n') continue
            add(IssueLevel.ERROR, "مسافات", "مسافة مزدوجة", text, m)
        }
        for (m in RX.find("([!؟?])\\1+|!؟|؟!", text)) add(IssueLevel.WARNING, "ترقيم", "علامات مكررة", text, m)

        // 5. التنسيق
        for (m in RX.find(EMOJI, text)) add(IssueLevel.ERROR, "تنسيق", "إيموجي", text, m)
        for (m in RX.find(DASH, text)) add(IssueLevel.ERROR, "تنسيق", "شرطة طويلة", text, m)
        for (m in RX.find("^\\s{0,3}#{1,6}\\s", text, Pattern.MULTILINE)) add(IssueLevel.WARNING, "تنسيق", "ترويسة ماركداون (مقبولة في المستندات فقط)", text, m)
        for (m in RX.find("\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__", text)) add(IssueLevel.WARNING, "تنسيق", "خط عريض", text, m)
        for (m in RX.find("^\\s*(إليك|اليك|هذا هو|هذه هي|فيما يلي|في ما يلي|تفضل|بالتأكيد|بكل سرور|حسنا|طبعا)[^\\n]{0,40}[:：]?\\s*$", norm, Pattern.MULTILINE))
            add(IssueLevel.ERROR, "تنسيق", "مقدمة عن النص بدل النص نفسه", norm, m)
        val bullets = RX.find("^\\s*([-*•●▪✓✅]|\\d+[.)])\\s+", text, Pattern.MULTILINE).size
        if (bullets >= 3 && sentences(text).size <= bullets + 2)
            add(IssueLevel.WARNING, "بنية", "$bullets نقاط: إن كان النص سرداً فحوّلها إلى جمل متصلة")

        // 6. الإنجليزية داخل السطر العربي
        if (options.englishOnOwnLine) {
            text.split('\n').forEachIndexed { i, ln ->
                if (!RX.test("[$AR]", ln) || !RX.test("[A-Za-z]", ln)) return@forEachIndexed
                val t = ln.trim()
                if (t.startsWith("http") || t.startsWith("#")) return@forEachIndexed
                val seen = LinkedHashSet<String>()
                RX.find(EN_CHUNK, ln).forEach { seen += it.value }
                if (seen.isNotEmpty()) issues += LintIssue(IssueLevel.ERROR, "اتجاه",
                    "كلمة إنجليزية داخل سطر عربي ← سطر مستقل: " + seen.joinToString("، "), line = i + 1)
            }
        }

        // 7. البنى
        for (m in RX.find("ليس[ت]?\\s[^.،؟\\n]{1,40}[،,]?\\s*(بل|وإنما|إنما)\\s", norm))
            add(IssueLevel.ERROR, "بصمة آلية: بنية", "«ليس … بل …»: قل الثاني مباشرة", norm, m)
        for (m in RX.find("([$AR]+)،\\s*([$AR]+)،\\s*و([$AR]+)", norm)) {
            if ((1..3).maxOf { m.groups[it].length } <= 8)
                add(IssueLevel.WARNING, "بصمة آلية: ثلاثية", "«${m.value}»: اثنتان أو حقيقة واحدة أصدق", norm, m)
        }
        for (m in RX.find("([$AR]{2,})\\s+و([$AR]{2,})\\s+و([$AR]{2,})", norm))
            add(IssueLevel.WARNING, "بصمة آلية: ثلاثية", "«${m.value}»", norm, m)
        for (m in RX.find("^[^\\n؟]{0,60}؟\\s*\\n?\\s*(لأن|الجواب|السبب)", norm, Pattern.MULTILINE))
            add(IssueLevel.ERROR, "بصمة آلية: بنية", "سؤال بلاغي يتبعه جوابه: احذف السؤال", norm, m)

        // 8. الإيقاع
        val lens = sentences(text).map { words(it).size }
        if (lens.size >= 4) {
            for (i in 0 until lens.size - 2) {
                val trio = lens.subList(i, i + 3)
                if (trio.max() - trio.min() <= 2 && trio.min() >= 4) {
                    add(IssueLevel.WARNING, "إيقاع", "ثلاث جمل متتالية بطول متقارب (${trio[0]}، ${trio[1]}، ${trio[2]} كلمة): نوّع")
                    break
                }
            }
            val short = lens.count { it <= 2 }
            if (short >= 3) add(IssueLevel.WARNING, "إيقاع", "$short جمل من كلمة أو كلمتين: تقطيع درامي، أعد الجمل لطولها")
        }

        // 9. الطول
        val st = stats(text)
        options.wordsTarget?.let { t ->
            val lo = (t * 0.9).toInt(); val hi = Math.round(t * 1.1).toInt()
            if (st.words < lo || st.words > hi) add(IssueLevel.ERROR, "طول", "${st.words} كلمة والمطلوب $t (المسموح $lo إلى $hi)")
        }
        options.linesTarget?.let { t -> if (st.lines != t) add(IssueLevel.ERROR, "طول", "${st.lines} سطر والمطلوب $t") }

        // 10. الاختلاق
        options.source?.let { source ->
            val src = stripDiacritics(source)
            val numPat = "\\d+(?:[.,،]\\d+)?"
            val srcNums = RX.find(numPat, src).map { it.value }.toSet()
            val seen = HashSet<String>()
            for (m in RX.find(numPat, norm)) if (m.value !in srcNums && seen.add(m.value))
                add(IssueLevel.ERROR, "اختلاق", "الرقم ${m.value} غير موجود في الأصل: احذفه أو اسأل عنه")
            val capPat = "\\b[A-Z][A-Za-z0-9]+\\b"
            val srcCaps = RX.find(capPat, src).map { it.value }.toSet()
            RX.find(capPat, norm).map { it.value }.toSet().minus(srcCaps).sorted()
                .forEach { add(IssueLevel.ERROR, "اختلاق", "الاسم $it غير موجود في الأصل") }
            val srcW = words(src).size
            if (st.words > maxOf(40, (srcW * 1.25).toInt()))
                add(IssueLevel.WARNING, "طول", "النص أطول من الأصل بأكثر من 25% (${st.words} مقابل $srcW)")
        }

        return LintReport(issues, st)
    }

    /** الإصلاح الآمن: الإملاء والترقيم والمسافات والإيموجي، ونقل الإنجليزي لسطر مستقل. */
    fun fix(text: String, englishOnOwnLine: Boolean = true): String {
        var t = text
        t = RX.replace(EMOJI, t, "")
        t = RX.replace("\\s*[—–‒―]\\s*|\\s+--\\s+", t, "، ")
        t = RX.replace("\\*\\*([^*\\n]+)\\*\\*", t, "$1")
        t = RX.replace("__([^_\\n]+)__", t, "$1")
        t = RX.replace("(?<=[$AR])\\s*,\\s*", t, "، ")
        t = RX.replace("(?<=[$AR])\\s*;\\s*", t, "؛ ")
        t = RX.replace("(?<=[$AR])\\s*\\?", t, "؟")
        t = RX.replace("[ \\t]+([،؛؟!.])", t, "$1")
        t = RX.replace("([،؛])(?=[${AR}A-Za-z0-9])", t, "$1 ")
        t = RX.replace("${B}و\\s+(?=[$AR])", t, "و")
        t = RX.replace("([!؟])\\1+", t, "$1")
        for ((wrong, right) in Lexicon.spelling.entries.sortedByDescending { it.key.length }) {
            val w = wrong.split(' ').joinToString("\\s+") { RX.quote(it) }
            t = RX.replace("$B($PRE)$w$E", t, "$1" + RX.tpl(right))
        }
        if (englishOnOwnLine) {
            val out = ArrayList<String>()
            for (ln in t.split('\n')) {
                if (RX.test("[$AR]", ln) && RX.test("[A-Za-z]", ln) && !ln.trim().startsWith("http")) {
                    var last = 0
                    for (m in RX.find(EN_CHUNK, ln)) {
                        val before = ln.substring(last, m.start).trim()
                        if (before.isNotEmpty()) out += before
                        out += m.value
                        last = m.end
                    }
                    val rest = ln.substring(last).trim()
                    if (rest.isNotEmpty()) out += rest
                } else out += ln
            }
            t = out.joinToString("\n")
        }
        t = RX.replace("[^\\S\\n]{2,}", t, " ")
        t = RX.replace("[ \\t]+\\n", t, "\n")
        t = RX.replace("\\n{3,}", t, "\n\n")
        return t.trim()
    }

    /** إصلاح داخل نص مقطّع (مثل سطور ملف وورد) بدون تغيير الأسطر. يرجع النص وعدد الإصلاحات. */
    fun fixInline(text: String): Pair<String, Int> {
        val rules = ArrayList<Pair<String, String>>()
        rules += EMOJI to ""
        rules += "(?<=[$AR])[ \\t]*,[ \\t]*" to "، "
        rules += "(?<=[$AR])[ \\t]*;[ \\t]*" to "؛ "
        rules += "(?<=[$AR])[ \\t]*\\?" to "؟"
        rules += "[ \\t]+([،؛؟!])" to "$1"
        rules += "([،؛])(?=[${AR}A-Za-z0-9])" to "$1 "
        rules += "${B}و[ \\t]+(?=[$AR])" to "و"
        rules += "([!؟])\\1+" to "$1"
        for ((wrong, right) in Lexicon.spelling.entries.sortedByDescending { it.key.length }) {
            val w = wrong.split(' ').joinToString("[ \\t]+") { RX.quote(it) }
            rules += "$B($PRE)$w$E" to "$1" + RX.tpl(right)
        }
        rules += "(?<=\\S)[ \\t]{2,}(?=\\S)" to " "
        var t = text; var n = 0
        for ((pat, tpl) in rules) {
            n += RX.count(pat, t)
            t = RX.replace(pat, t, tpl)
        }
        return t to n
    }
}

// ---------- الفرق بين نصين ----------

data class DiffChange(val op: Op, val before: String, val after: String, val id: String = UUID.randomUUID().toString()) {
    enum class Op(val label: String) { REPLACE("تعديل"), DELETE("حذف"), INSERT("إضافة") }
}

object TextDiff {
    fun compare(a: String, b: String): Pair<List<DiffChange>, Int> {
        val wa = a.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val wb = b.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val n = wa.size; val m = wb.size
        if (n == 0 && m == 0) return emptyList<DiffChange>() to 100
        val dp = Array(n + 1) { IntArray(m + 1) }
        for (i in n - 1 downTo 0) for (j in m - 1 downTo 0)
            dp[i][j] = if (wa[i] == wb[j]) dp[i + 1][j + 1] + 1 else maxOf(dp[i + 1][j], dp[i][j + 1])
        val changes = ArrayList<DiffChange>()
        var i = 0; var j = 0
        val del = ArrayList<String>(); val ins = ArrayList<String>()
        fun flush() {
            if (del.isEmpty() && ins.isEmpty()) return
            val op = if (del.isEmpty()) DiffChange.Op.INSERT else if (ins.isEmpty()) DiffChange.Op.DELETE else DiffChange.Op.REPLACE
            changes += DiffChange(op, del.joinToString(" "), ins.joinToString(" "))
            del.clear(); ins.clear()
        }
        while (i < n || j < m) {
            if (i < n && j < m && wa[i] == wb[j]) { flush(); i++; j++ }
            else if (j < m && (i == n || dp[i][j + 1] >= dp[i + 1][j])) { ins += wb[j]; j++ }
            else { del += wa[i]; i++ }
        }
        flush()
        return changes to Math.round(2.0 * dp[0][0] / (n + m) * 100).toInt()
    }
}
