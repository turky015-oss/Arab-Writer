package app.arabwriter.android.service

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

/** نموذج لغوي داخل الجوال (Qwen2.5-1.5B عبر MediaPipe)، بلا إنترنت. */
object LocalModel {
    private const val ASSET = "model/qwen.task"
    private lateinit var appCtx: Context
    private val lock = Mutex()
    private var llm: LlmInference? = null

    /** حالة التجهيز لعرضها في الواجهة، أو null إذا كان جاهزاً أو غير مستخدم. */
    var status by mutableStateOf<String?>(null)

    fun init(ctx: Context) { appCtx = ctx.applicationContext }

    val isAvailable: Boolean by lazy {
        runCatching { appCtx.assets.list("model")?.contains("qwen.task") == true }.getOrDefault(false)
    }

    private val file get() = File(appCtx.filesDir, "model/qwen.task")

    private fun assetLength(): Long = runCatching { appCtx.assets.openFd(ASSET).use { it.length } }.getOrDefault(-1L)

    /** ينسخ النموذج من ملف التثبيت إلى ذاكرة الجوال مرة وحدة (مكتبة التشغيل تحتاج مساراً عادياً). */
    suspend fun prepare() = withContext(Dispatchers.IO) {
        if (!isAvailable) return@withContext
        lock.withLock {
            val f = file
            val total = assetLength()
            if (f.exists() && (total <= 0 || f.length() == total)) return@withLock
            f.parentFile?.mkdirs()
            val tmp = File(f.parentFile, "qwen.task.part")
            try {
                appCtx.assets.open(ASSET).use { input ->
                    tmp.outputStream().use { out ->
                        val buf = ByteArray(1 shl 20)
                        var done = 0L
                        var lastPct = -1
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            out.write(buf, 0, n)
                            done += n
                            if (total > 0) {
                                val pct = (done * 100 / total).toInt()
                                if (pct != lastPct) { lastPct = pct; withContext(Dispatchers.Main) { status = "يجهّز النموذج الداخلي أول مرة… $pct٪" } }
                            }
                        }
                    }
                }
                if (!tmp.renameTo(f)) throw ToolException("تعذّر تجهيز النموذج الداخلي.")
            } catch (e: Exception) {
                tmp.delete()
                throw ToolException(if (e.message?.contains("ENOSPC") == true) "المساحة ما تكفي لتجهيز النموذج الداخلي (يحتاج ٢ قيقا تقريباً)." else e.message ?: "تعذّر تجهيز النموذج.")
            } finally {
                withContext(Dispatchers.Main) { status = null }
            }
        }
    }

    private suspend fun engine(): LlmInference {
        llm?.let { return it }
        prepare()
        return lock.withLock {
            llm ?: withContext(Dispatchers.IO) {
                withContext(Dispatchers.Main) { status = "يشغّل النموذج الداخلي…" }
                try {
                    LlmInference.createFromOptions(appCtx, LlmInference.LlmInferenceOptions.builder()
                        .setModelPath(file.absolutePath)
                        .setMaxTokens(4096)
                        .build())
                } catch (e: Exception) {
                    throw ToolException("تعذّر تشغيل النموذج الداخلي: ${e.message}")
                } finally {
                    withContext(Dispatchers.Main) { status = null }
                }
            }.also { llm = it }
        }
    }

    suspend fun generate(system: String, user: String): String {
        val e = engine()
        val prompt = "<|im_start|>system\n$system<|im_end|>\n<|im_start|>user\n$user<|im_end|>\n<|im_start|>assistant\n"
        withContext(Dispatchers.Main) { status = "يكتب داخلياً على جوالك…" }
        return try {
            withContext(Dispatchers.IO) { e.generateResponse(prompt) }
                .substringBefore("<|im_end|>").substringBefore("<|im_start|>").trim()
                .also { if (it.isEmpty()) throw ToolException("النموذج الداخلي رجّع رداً فارغاً. جرّب مرة ثانية.") }
        } catch (ex: ToolException) { throw ex
        } catch (ex: Exception) {
            throw ToolException(if (ex.message?.contains("token", true) == true) "النص طويل على النموذج الداخلي. قسّمه أو استخدم Claude." else "تعذّر التوليد داخلياً: ${ex.message}")
        } finally {
            withContext(Dispatchers.Main) { status = null }
        }
    }
}

// ---------- محرّك موحّد ----------

interface TextEngine {
    val isLocal: Boolean
    suspend fun complete(system: String, content: Any, maxTokens: Int = 4096): String
    suspend fun stream(system: String, content: Any, maxTokens: Int = 4096, onText: suspend (String) -> Unit): String
}

class LocalEngine : TextEngine {
    override val isLocal = true
    /** النموذج الداخلي سياقه 4096 رمزاً، فنقصّ الإدخال الطويل. */
    private val inputLimit = 4500

    override suspend fun complete(system: String, content: Any, maxTokens: Int): String {
        val text = content as? String ?: throw ToolException("هذه الميزة تحتاج Claude.")
        return LocalModel.generate(system, text.take(inputLimit))
    }

    override suspend fun stream(system: String, content: Any, maxTokens: Int, onText: suspend (String) -> Unit): String =
        complete(system, content, maxTokens).also { onText(it) }
}

/** النموذج الداخلي صغير، فيأخذ زبدة قواعد المهارة بدل ملفاتها كاملة. */
object LocalPrompt {
    const val BASE = """أنت محرر عربي محترف داخل تطبيق Arab Writer. اكتب كما يكتب إنسان عربي متمكن، لا كما يكتب الذكاء الاصطناعي.
قواعد صارمة:
- أرجع النص النهائي وحده، بلا مقدمة ولا شرح ولا عنوان عن النص ولا علامات اقتباس حوله.
- لا تضف أي معلومة أو رقم أو اسم أو إحصائية غير موجودة في النص الأصلي.
- احذف العبارات الآلية مثل: في عالم اليوم، في ظل التطور، لا شك أن، من المعروف أن، تجدر الإشارة، الجدير بالذكر، يلعب دوراً، يفتح آفاقاً، نقلة نوعية، يغير قواعد اللعبة، بشكل كبير، بشكل فعال، في الختام، ختاماً، لا تتردد في.
- لا تبنِ الجمل على «ليس فقط… بل»، ولا تسرد ثلاثيات متتالية، ولا تبدأ بسؤال ثم تجيب عليه.
- لا إيموجي، لا شرطة طويلة، لا خط عريض، ولا نقاط إلا إذا كانت في الأصل.
- نوّع طول الجمل، واستعمل أفعالاً مباشرة وكلمات عادية.
- اكتب الهمزات والتاء المربوطة والألف المقصورة صحيحة، واستعمل «،» و«؛» و«؟» العربية."""

    const val STORY = BASE + """

أنت الآن تكتب قصة قصيرة: ابدأ بشخص يفعل شيئاً في مكان وزمن محددين، اجعل شيئاً يقاومه، ثم نقطة تحول، ثم نهاية تغلق المشهد بلا موعظة ولا شرح للمغزى. حوار قليل وطبيعي."""

    const val SUMMARY = BASE + """

أنت الآن تلخّص مستنداً: عنوان قصير في السطر الأول ثم فقرات متصلة. كل رقم واسم في الملخص يجب أن يكون في المستند."""

    val platforms = mapOf(
        Platform.X to "قالب إكس: أقل من 280 حرفاً، سطر أول يشد، بلا وسوم كثيرة.",
        Platform.INSTAGRAM to "قالب إنستقرام: سطر أول قوي، فقرات قصيرة، وسطر أخير يدعو للتفاعل بلا مبالغة.",
        Platform.LINKEDIN to "قالب لينكدإن: نبرة مهنية، تجربة أو فكرة محددة، فقرات قصيرة.",
        Platform.WHATSAPP to "قالب واتساب: رسالة قصيرة مباشرة كما يكتبها شخص لشخص.",
        Platform.OFFICIAL to "قالب خطاب رسمي: فصحى رسمية، تحية، موضوع، طلب واضح، ختام رسمي.",
        Platform.SCRIPT to "قالب سكربت فيديو: جمل قصيرة تُقال بصوت، أول جملة تشد خلال ثانيتين.",
    )
}
