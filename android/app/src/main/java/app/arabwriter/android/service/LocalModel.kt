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
import kotlinx.coroutines.launch
import java.io.File

/** نموذج لغوي داخل الجوال (Qwen2.5-1.5B عبر MediaPipe). ينزل مرة وحدة، ثم يشتغل بلا إنترنت. */
object LocalModel {
    private const val URL_MODEL = "https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task"
    const val SIZE = 1_598_556_720L
    private lateinit var appCtx: Context
    private val lock = Mutex()
    private var llm: LlmInference? = null
    private val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + Dispatchers.IO)

    /** حالة التجهيز لعرضها في الواجهة، أو null إذا كان جاهزاً أو غير مستخدم. */
    var status by mutableStateOf<String?>(null)
    /** نسبة التنزيل من 0 إلى 1 أثناء التنزيل. */
    var progress by mutableStateOf<Float?>(null)
    var ready by mutableStateOf(false); private set

    fun init(ctx: Context) {
        appCtx = ctx.applicationContext
        ready = file.exists() && file.length() == SIZE
    }

    /** المحرّك الداخلي متاح دائماً، وينزل نموذجه عند أول حاجة. */
    val isAvailable: Boolean get() = true

    private val file get() = File(appCtx.filesDir, "model/qwen.task")

    /** يبدأ التنزيل في الخلفية (يكمل من حيث وقف). */
    fun startDownload() {
        if (ready || progress != null) return
        scope.launch { runCatching { prepare() }.onFailure { withContext(Dispatchers.Main) { status = null; progress = null } } }
    }

    /** ينزّل النموذج مرة وحدة، ويكمل التنزيل المنقطع. */
    suspend fun prepare() = withContext(Dispatchers.IO) {
        lock.withLock {
            val f = file
            if (f.exists() && f.length() == SIZE) { withContext(Dispatchers.Main) { ready = true }; return@withLock }
            f.parentFile?.mkdirs()
            val free = f.parentFile?.usableSpace ?: 0L
            val part = File(f.parentFile, "qwen.task.part")
            if (free < SIZE - part.length() + 200_000_000L)
                throw ToolException("المساحة ما تكفي لتنزيل النموذج الداخلي. يحتاج ١٫٧ قيقا فاضية.")
            try {
                var attempt = 0
                while (part.length() < SIZE) {
                    try {
                        download(part)
                    } catch (e: java.io.IOException) {
                        if (++attempt >= 5) throw ToolException("انقطع التنزيل. تأكد من الإنترنت وجرّب مرة ثانية، وبيكمل من حيث وقف.")
                        kotlinx.coroutines.delay(3000L * attempt)
                    }
                }
                if (part.length() != SIZE) { part.delete(); throw ToolException("الملف نزل ناقص. جرّب مرة ثانية.") }
                if (!part.renameTo(f)) throw ToolException("تعذّر حفظ النموذج.")
                withContext(Dispatchers.Main) { ready = true }
            } finally {
                withContext(Dispatchers.Main) { status = null; progress = null }
            }
        }
    }

    private suspend fun download(part: File) {
        val have = part.length()
        val c = java.net.URL(URL_MODEL).openConnection() as java.net.HttpURLConnection
        c.instanceFollowRedirects = true
        c.connectTimeout = 30_000
        c.readTimeout = 60_000
        if (have > 0) c.setRequestProperty("Range", "bytes=$have-")
        val code = c.responseCode
        if (code != 200 && code != 206) throw java.io.IOException("HTTP $code")
        val append = code == 206
        if (!append && have > 0) part.delete()
        var done = if (append) have else 0L
        var lastPct = -1
        c.inputStream.use { input ->
            java.io.FileOutputStream(part, append).use { out ->
                val buf = ByteArray(1 shl 20)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    done += n
                    val pct = (done * 100 / SIZE).toInt()
                    if (pct != lastPct) {
                        lastPct = pct
                        val mb = done / 1_000_000
                        withContext(Dispatchers.Main) {
                            progress = done.toFloat() / SIZE
                            status = "ينزّل النموذج الداخلي… $pct٪ ($mb من ${SIZE / 1_000_000} ميقا)"
                        }
                    }
                }
            }
        }
    }

    private suspend fun engine(): LlmInference {
        llm?.let { return it }
        if (!ready) withContext(Dispatchers.Main) { status = "يبدأ تنزيل النموذج الداخلي أول مرة…" }
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
