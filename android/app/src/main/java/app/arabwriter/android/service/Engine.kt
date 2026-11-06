package app.arabwriter.android.service

import android.content.Context
import android.graphics.Bitmap
import android.util.Base64
import app.arabwriter.android.core.ArabicLinter
import app.arabwriter.android.core.DiffChange
import app.arabwriter.android.core.LintOptions
import app.arabwriter.android.core.LintReport
import app.arabwriter.android.core.TextDiff
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.UUID

// ---------- تعليمات المهارة ----------

object SkillPrompt {
    private val cache = HashMap<String, String>()
    private lateinit var appCtx: Context

    fun init(ctx: Context) { appCtx = ctx.applicationContext }

    private fun load(name: String): String = cache.getOrPut(name) {
        runCatching { appCtx.assets.open("skill/$name.md").bufferedReader().readText() }.getOrDefault("")
    }

    private const val APP_RULES = """
أنت محرّك تطبيق Arab Writer على الجوال. تعمل بالقواعد المرفقة كاملة.
لا تملك أدوات ولا سكربتات: الفحص الآلي يجري داخل التطبيق بعد ردك، فلا تذكره.
أرجع النص النهائي وحده. لا مقدمة، لا شرح، لا عناوين عن النص، لا علامات اقتباس حوله، لا كتل كود.
إن احتجت سؤالاً عن تفصيلة ناقصة (حسب قاعدة لا اختلاق)، ضعه بعد النص في سطر أخير يبدأ بـ «سؤال:».
"""

    private fun join(vararg names: String) = (listOf(APP_RULES) + names.map { load(it) })
        .filter { it.isNotBlank() }.joinToString("\n\n---\n\n")

    val writing get() = join("SKILL", "ai-markers-arabic", "structures", "voice", "arabic-proofreading",
        "arabic-dictionary", "platforms", "english-markers")
    val story get() = join("storytelling", "ai-markers-arabic", "structures", "voice", "arabic-proofreading")
    val summary get() = join("pdf-workflow", "ai-markers-arabic", "arabic-proofreading")
}

// ---------- الخيارات ----------

enum class WriteMode(val label: String, val hint: String) {
    REWRITE("صياغة", "يمسح بصمات الذكاء الاصطناعي ويعيد الصياغة بصوت بشري"),
    PROOFREAD("تدقيق", "يصحح الإملاء والنحو والترقيم ويبقي كلامك كما هو"),
    WRITE("كتابة", "اكتب فكرة خام ويطلع لك نص جاهز للنشر"),
}

enum class Register(val label: String) { KEEP("كما هو"), SAUDI("سعودي"), FUSHA("فصحى") }

enum class Platform(val label: String, val caption: String) {
    NONE("بدون", "نص عام"), X("إكس", "تغريدة قصيرة"), INSTAGRAM("إنستقرام", "كابشن"),
    LINKEDIN("لينكدإن", "منشور مهني"), WHATSAPP("واتساب", "رسالة"),
    OFFICIAL("خطاب رسمي", "فصحى رسمية"), SCRIPT("سكربت فيديو", "للتصوير"),
}

enum class StoryLength(val label: String, val range: String) {
    FLASH("ومضة", "80 إلى 120"), SHORT("قصة قصيرة", "250 إلى 400"), SCRIPT("لسكربت فيديو", "120 إلى 180"),
}

enum class TranslateDirection(val label: String) {
    AUTO("تلقائي"), TO_ARABIC("إلى العربي"), TO_ENGLISH("إلى الإنجليزي");

    fun resolved(text: String): TranslateDirection {
        if (this != AUTO) return this
        val ar = text.count { it in '؀'..'ۿ' }
        val en = text.count { it in 'A'..'Z' || it in 'a'..'z' }
        return if (ar >= en) TO_ENGLISH else TO_ARABIC
    }
}

data class WriteRequest(val text: String, val mode: WriteMode, val register: Register, val platform: Platform, val words: Int?)

data class WriteResult(
    val text: String,
    val question: String?,
    val report: LintReport,
    val changes: List<DiffChange> = emptyList(),
    val similarity: Int = 0,
    val usedAI: Boolean = true,
)

// ---------- خطة الفيديو ----------

data class VideoOptions(val seconds: Int, val style: String, val audio: String, val hero: String, val platform: String)

data class VideoPlan(
    val text: String,
    val model: String,
    val modelReason: String,
    val shots: List<Shot>,
    val segments: List<Segment>,
    val hook: String,
    val screenLines: List<Pair<String, String>>,
    val caption: String,
    val hashtags: List<String>,
    val id: String = UUID.randomUUID().toString(),
) {
    data class Shot(val seconds: Double, val action: String)
    data class Segment(val seconds: Double, val prompt: String)

    val totalSeconds get() = shots.sumOf { it.seconds }

    val packageText: String get() = buildString {
        append("النص\n$text\n\n")
        append("اللقطات\n")
        shots.forEachIndexed { i, s -> append("${i + 1}. ${fmt(s.seconds)} ث: ${s.action}\n") }
        append("\nالنموذج\n$model: $modelReason\n\n")
        append("البرومبتات\n")
        segments.forEachIndexed { i, s -> append("مقطع ${i + 1} (${fmt(s.seconds)} ث)\n${s.prompt}\n\n") }
        append("الكابشن\nالخطاف: $hook\n")
        screenLines.forEach { append("${it.first}: ${it.second}\n") }
        append("\n$caption\n${hashtags.joinToString(" ")}")
    }

    companion object {
        fun fmt(d: Double): String = if (d == Math.floor(d)) d.toLong().toString() else "%.1f".format(d)

        fun parse(raw: String): VideoPlan? {
            val a = raw.indexOf('{'); val b = raw.lastIndexOf('}')
            if (a < 0 || b <= a) return null
            val j = runCatching { JSONObject(raw.substring(a, b + 1)) }.getOrNull() ?: return null
            fun arr(k: String) = j.optJSONArray(k) ?: JSONArray()
            val shots = arr("shots").let { s -> (0 until s.length()).map { val o = s.getJSONObject(it); Shot(o.optDouble("seconds", 0.0), o.optString("action")) } }
            val segs = arr("segments").let { s -> (0 until s.length()).map { val o = s.getJSONObject(it); Segment(o.optDouble("seconds", 0.0), o.optString("prompt")) } }
            val lines = arr("screenLines").let { s -> (0 until s.length()).map { val o = s.getJSONObject(it); o.optString("at") to o.optString("text") } }
            val tags = arr("hashtags").let { s -> (0 until s.length()).map { s.optString(it) } }
            return VideoPlan(j.optString("text"), j.optString("model", "best_available"), j.optString("modelReason"),
                shots, segs, j.optString("hook"), lines, j.optString("caption"), tags)
        }
    }
}

// ---------- المحرّك ----------

object WritingEngine {
    fun splitQuestion(s: String): Pair<String, String?> {
        val lines = s.split('\n').toMutableList()
        while (lines.isNotEmpty() && lines.last().isBlank()) lines.removeAt(lines.lastIndex)
        val last = lines.lastOrNull()?.trim()
        if (last != null && last.startsWith("سؤال:")) {
            lines.removeAt(lines.lastIndex)
            return lines.joinToString("\n") to last.removePrefix("سؤال:").trim()
        }
        return s to null
    }

    fun instruction(r: WriteRequest, en: Boolean): String = buildString {
        appendLine(when (r.mode) {
            WriteMode.REWRITE -> "المهمة: أعد صياغة النص التالي بالمراحل الثلاث (امسح، دقّق). لا تضف معلومة غير موجودة."
            WriteMode.PROOFREAD -> "المهمة: دقّق النص التالي إملائياً ونحوياً وترقيمياً فقط. لا تغيّر الصياغة ولا الأسلوب ولا الترتيب."
            WriteMode.WRITE -> "المهمة: اكتب نصاً جاهزاً للنشر من الفكرة التالية. لا تخترع أرقاماً ولا إحصاءات ولا أسماء."
        })
        appendLine(when (r.register) {
            Register.KEEP -> "السجل: كما جاء في النص."
            Register.SAUDI -> "السجل: لهجة سعودية طبيعية."
            Register.FUSHA -> "السجل: فصحى سهلة."
        })
        if (r.platform != Platform.NONE) appendLine("المنصة: ${r.platform.label}. طبّق قالبها.")
        r.words?.let { appendLine("قفل الطول: $it كلمة بهامش 10%.") }
        appendLine(if (en) "كل كلمة إنجليزية في سطر مستقل وحدها." else "اترك الكلمات الإنجليزية في مكانها داخل السطر.")
        append("\nالنص:\n${r.text}")
    }

    suspend fun run(r: WriteRequest, onPartial: (suspend (String) -> Unit)? = null): WriteResult {
        val en = AppSettings.englishOnOwnLine
        val source = if (r.mode == WriteMode.WRITE) null else r.text
        val opts = LintOptions(wordsTarget = r.words, source = source, englishOnOwnLine = en)

        if (!AppSettings.hasKey) {
            val out = ArabicLinter.fix(r.text, en)
            val (ch, sim) = TextDiff.compare(r.text, out)
            return WriteResult(out, null, ArabicLinter.check(out, opts.copy(source = r.text)), ch, sim, usedAI = false)
        }

        val client = AppSettings.client()
        val system = SkillPrompt.writing
        val user = instruction(r, en)
        val raw = if (onPartial != null) client.stream(system, user) { onPartial(splitQuestion(it).first) }
                  else client.complete(system, user)
        var (draft, question) = splitQuestion(raw)
        draft = ArabicLinter.fix(draft, en)
        var report = ArabicLinter.check(draft, opts)

        if (AppSettings.autoRetry && !report.isClean) {
            val list = report.errors.take(20).joinToString("\n") { "- [${it.kind}] ${it.message}" }
            val ask = "هذا نصك بعد الفحص الآلي، وفيه أخطاء مانعة. أصلحها كلها وأرجع النص النهائي وحده.\nالأخطاء:\n$list\n\nالنص:\n$draft"
            val (d2, q2) = splitQuestion(client.complete(system, ask))
            val fixed = ArabicLinter.fix(d2, en)
            val r2 = ArabicLinter.check(fixed, opts)
            if (r2.errors.size <= report.errors.size) { draft = fixed; report = r2; question = q2 ?: question }
        }
        val (ch, sim) = TextDiff.compare(r.text, draft)
        return WriteResult(draft, question, report, ch, sim)
    }

    suspend fun story(title: String, length: StoryLength, register: Register, onPartial: (suspend (String) -> Unit)? = null): WriteResult {
        val en = AppSettings.englishOnOwnLine
        val client = AppSettings.client()
        val ask = """
            المهمة: اكتب قصة قصيرة من هذا العنوان بوضع السرد.
            الطول: ${length.range} كلمة.
            السجل: ${if (register == Register.KEEP) "حسب العنوان" else register.label}.
            ابدأ بسطر العنوان ثم سطر فارغ ثم القصة.

            العنوان: $title
        """.trimIndent()
        val raw = if (onPartial != null) client.stream(SkillPrompt.story, ask, onText = onPartial) else client.complete(SkillPrompt.story, ask)
        val (draft, q) = splitQuestion(raw)
        val out = ArabicLinter.fix(draft, en)
        return WriteResult(out, q, ArabicLinter.check(out, LintOptions(englishOnOwnLine = en)))
    }

    suspend fun translate(text: String, direction: TranslateDirection, register: Register, onPartial: (suspend (String) -> Unit)? = null): WriteResult {
        val en = AppSettings.englishOnOwnLine
        val client = AppSettings.client()
        val dir = direction.resolved(text)
        val ask = if (dir == TranslateDirection.TO_ARABIC) """
            المهمة: ترجم النص التالي إلى العربية كما يكتبه إنسان عربي، لا ترجمة حرفية.
            انقل المعنى والنبرة لا ترتيب الكلمات. طبّق المراحل كلها: لا بصمات آلية ولا تراكيب مترجمة (يلعب دوراً، يفتح الباب أمام).
            السجل: ${when (register) { Register.FUSHA -> "فصحى سهلة"; Register.SAUDI -> "لهجة سعودية طبيعية"; else -> "حسب طبيعة النص" }}
            لا تضف ولا تحذف معلومة. أسماء العلم والمنتجات تبقى بالإنجليزية.
            ${if (en) "كل كلمة إنجليزية في سطر مستقل وحدها." else ""}
            أرجع الترجمة وحدها.

            النص:
            $text
        """.trimIndent() else """
            Task: translate the following text into natural, human English, the way a native writer would put it. Not word for word.
            Carry the meaning and tone. Apply the English rules (no AI markers: delve, leverage, seamless, in today's fast-paced world, it's worth noting).
            Do not add or drop any fact, number or name. Return the translation only.

            Text:
            $text
        """.trimIndent()
        val raw = if (onPartial != null) client.stream(SkillPrompt.writing, ask, onText = onPartial) else client.complete(SkillPrompt.writing, ask)
        val draft = splitQuestion(raw).first
        return if (dir == TranslateDirection.TO_ARABIC) {
            val out = ArabicLinter.fix(draft, en)
            WriteResult(out, null, ArabicLinter.check(out, LintOptions(source = text, englishOnOwnLine = en)))
        } else WriteResult(draft, null, LintReport(stats = ArabicLinter.stats(draft)))
    }

    suspend fun video(text: String, o: VideoOptions, onPartial: (suspend (String) -> Unit)? = null): VideoPlan {
        val client = AppSettings.client()
        val ask = """
            المهمة: وضع الفيديو بأسلوب Commands Only. حوّل النص التالي إلى حزمة فيديو بقواعد المهارة كاملة.
            المدة: ${o.seconds} ثانية بالضبط. الأسلوب: ${o.style}. الصوت: ${o.audio}. البطل: ${o.hero}. المنصة: ${o.platform}، عمودي 9:16.
            الأقفال: مجموع ثواني اللقطات يساوي ${o.seconds} بالضبط. 8 و10 ثوانٍ لا تُقسَّم. لا نص عربي داخل الإطار. لا أسماء نماذج مخترعة (اكتب best_available إن لم تتأكد).
            نظّف النص بالمرحلتين قبل التقطيع.
            البرومبتات بالإنجليزية: قائمة لقطات (كاميرا، عدسة، ضوء، فعل، صوت) بلا كلمات مثل cinematic masterpiece أو 8k.

            أرجع JSON فقط بلا أي نص قبله أو بعده، بهذه المفاتيح:
            {"text": "النص النظيف", "model": "اسم النموذج", "modelReason": "سبب في سطر",
             "shots": [{"seconds": 3, "action": "وصف اللقطة بالعربي"}],
             "segments": [{"seconds": 10, "prompt": "English prompt"}],
             "hook": "سطر الخطاف", "screenLines": [{"at": "0:00", "text": "سطر الشاشة"}],
             "caption": "كابشن النشر", "hashtags": ["#وسم"]}

            النص:
            $text
        """.trimIndent()
        val raw = if (onPartial != null) client.stream(SkillPrompt.writing, ask, 6000, onPartial) else client.complete(SkillPrompt.writing, ask, 6000)
        return VideoPlan.parse(raw) ?: throw IllegalStateException("وصل رد غير مرتب. اضغط مرة ثانية.")
    }

    suspend fun summarize(text: String, words: Int): String {
        val client = AppSettings.client()
        val ask = """
            المهمة: لخّص المستند التالي بالعربية في حدود $words كلمة.
            ابدأ بسطر عنوان قصير، ثم فقرات متصلة. يجوز استعمال قائمة للأرقام والبنود فقط.
            كل رقم واسم في الملخص يجب أن يكون في المستند.

            المستند:
            ${text.take(120_000)}
        """.trimIndent()
        return ArabicLinter.fix(splitQuestion(client.complete(SkillPrompt.summary, ask)).first, AppSettings.englishOnOwnLine)
    }

    /** قراءة ضوئية لصفحات مصوّرة عبر Claude (يقرأ العربي بدقة عالية). */
    suspend fun ocr(pages: List<Bitmap>, onPage: suspend (Int, Int) -> Unit = { _, _ -> }): String {
        val client = AppSettings.client()
        val out = StringBuilder()
        pages.chunked(4).forEachIndexed { ci, chunk ->
            onPage(minOf((ci + 1) * 4, pages.size), pages.size)
            val content = JSONArray()
            chunk.forEach { bmp ->
                val bos = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, 82, bos)
                content.put(JSONObject().put("type", "image").put("source", JSONObject()
                    .put("type", "base64").put("media_type", "image/jpeg")
                    .put("data", Base64.encodeToString(bos.toByteArray(), Base64.NO_WRAP))))
            }
            content.put(JSONObject().put("type", "text").put("text",
                "انسخ النص الظاهر في الصور حرفياً كما هو، بنفس ترتيب الصفحات والأسطر. لا تلخّص ولا تصحح ولا تضف شيئاً. أرجع النص وحده."))
            out.append(client.complete("أنت قارئ ضوئي دقيق للعربية والإنجليزية.", content, 8000)).append("\n\n")
        }
        return out.toString().trim()
    }
}
