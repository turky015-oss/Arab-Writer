package app.arabwriter.android.service

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

// ---------- الإعدادات ----------

object AppSettings {
    private lateinit var prefs: SharedPreferences
    private var secure: SharedPreferences? = null

    var model by mutableStateOf("claude-sonnet-5-5"); private set
    var englishOnOwnLine by mutableStateOf(true); private set
    var autoRetry by mutableStateOf(true); private set
    var sounds by mutableStateOf(true); private set
    var hasKey by mutableStateOf(false); private set
    /** "local" = النموذج الداخلي، "claude" = Claude بالمفتاح */
    var engine by mutableStateOf("local"); private set

    /** فيه محرّك ذكي متاح (داخلي أو Claude). */
    val aiAvailable get() = LocalModel.isAvailable || hasKey
    /** الطلب القادم بيروح للنموذج الداخلي. */
    val usingLocal get() = LocalModel.isAvailable && !(engine == "claude" && hasKey)

    val models = listOf(
        "claude-sonnet-5-5" to "Sonnet 5.5 · متوازن",
        "claude-opus-5-5" to "Opus 5.5 · الأدق",
        "claude-haiku-5-5" to "Haiku 5.5 · الأسرع",
    )

    fun init(ctx: Context) {
        if (::prefs.isInitialized) return
        prefs = ctx.getSharedPreferences("settings", Context.MODE_PRIVATE)
        secure = runCatching {
            EncryptedSharedPreferences.create(
                "secure", MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC), ctx,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        }.getOrNull()
        model = prefs.getString("model", model) ?: model
        englishOnOwnLine = prefs.getBoolean("enLines", true)
        autoRetry = prefs.getBoolean("autoRetry", true)
        sounds = prefs.getBoolean("sounds", true)
        engine = prefs.getString("engine", "local") ?: "local"
        hasKey = !key().isNullOrBlank()
    }

    fun key(): String? = secure?.getString("apiKey", null)

    fun setKey(k: String) {
        secure?.edit()?.putString("apiKey", k.trim())?.apply()
        hasKey = k.isNotBlank()
    }

    fun removeKey() {
        secure?.edit()?.remove("apiKey")?.apply()
        hasKey = false
    }

    fun updateModel(m: String) { model = m; prefs.edit().putString("model", m).apply() }
    fun updateEnglish(v: Boolean) { englishOnOwnLine = v; prefs.edit().putBoolean("enLines", v).apply() }
    fun updateRetry(v: Boolean) { autoRetry = v; prefs.edit().putBoolean("autoRetry", v).apply() }
    fun updateSounds(v: Boolean) { sounds = v; prefs.edit().putBoolean("sounds", v).apply() }
    fun updateEngine(v: String) { engine = v; prefs.edit().putString("engine", v).apply() }

    fun claude(): ClaudeClient {
        val k = key()
        if (k.isNullOrBlank()) throw ClaudeException(0, "هذه الميزة تحتاج مفتاح Claude. أضفه من الإعدادات.")
        return ClaudeClient(k, model)
    }

    /** المحرّك المختار: الداخلي افتراضياً، وClaude إذا اختاره المستخدم وعنده مفتاح. */
    fun client(): TextEngine = if (usingLocal) LocalEngine() else claude()
}

// ---------- الاتصال ----------

class ClaudeException(val code: Int, msg: String) : Exception(msg)

class ClaudeClient(private val apiKey: String, private val model: String) : TextEngine {
    override val isLocal = false

    private fun friendly(code: Int, msg: String): ClaudeException = ClaudeException(code, when (code) {
        401 -> "المفتاح غير صحيح. راجعه من الإعدادات."
        429 -> "وصلت حد الاستخدام مؤقتاً. جرّب بعد قليل."
        503, 529 -> "خدمة Claude مزدحمة الحين. جرّب بعد دقيقة."
        0 -> "تعذّر الاتصال. تأكد من الإنترنت."
        else -> "تعذّر الاتصال ($code): $msg"
    })

    private fun body(system: String, content: Any, maxTokens: Int, stream: Boolean) = JSONObject().apply {
        put("model", model)
        put("max_tokens", maxTokens)
        put("stream", stream)
        put("system", JSONArray().put(JSONObject().put("type", "text").put("text", system)
            .put("cache_control", JSONObject().put("type", "ephemeral"))))
        put("messages", JSONArray().put(JSONObject().put("role", "user").put("content", content)))
    }.toString()

    private fun open(json: String): HttpURLConnection {
        val c = URL("https://api.anthropic.com/v1/messages").openConnection() as HttpURLConnection
        c.requestMethod = "POST"
        c.connectTimeout = 30_000
        c.readTimeout = 180_000
        c.doOutput = true
        c.setRequestProperty("content-type", "application/json")
        c.setRequestProperty("x-api-key", apiKey)
        c.setRequestProperty("anthropic-version", "2023-06-01")
        c.outputStream.use { it.write(json.toByteArray()) }
        return c
    }

    private fun errorOf(c: HttpURLConnection, code: Int): ClaudeException {
        val raw = runCatching { c.errorStream?.bufferedReader()?.readText() ?: "" }.getOrDefault("")
        val msg = runCatching { JSONObject(raw).getJSONObject("error").getString("message") }.getOrDefault(raw)
        return friendly(code, msg)
    }

    /** طلب كامل. content نص أو مصفوفة محتوى (للصور). */
    override suspend fun complete(system: String, content: Any, maxTokens: Int): String = withContext(Dispatchers.IO) {
        val c = try { open(body(system, content, maxTokens, false)) } catch (e: Exception) { throw friendly(0, e.message ?: "") }
        val code = c.responseCode
        if (code != 200) throw errorOf(c, code)
        val json = JSONObject(c.inputStream.bufferedReader().readText())
        val parts = json.optJSONArray("content") ?: JSONArray()
        val sb = StringBuilder()
        for (i in 0 until parts.length()) {
            val p = parts.getJSONObject(i)
            if (p.optString("type") == "text") sb.append(p.optString("text"))
        }
        val out = sb.toString().trim()
        if (out.isEmpty()) throw ClaudeException(0, "وصل رد فارغ. جرّب مرة ثانية.")
        out
    }

    /** بث حي: onText يستلم النص المتراكم. */
    override suspend fun stream(system: String, content: Any, maxTokens: Int, onText: suspend (String) -> Unit): String {
        val full = withContext(Dispatchers.IO) {
            val c = try { open(body(system, content, maxTokens, true)) } catch (e: Exception) { throw friendly(0, e.message ?: "") }
            val code = c.responseCode
            if (code != 200) throw errorOf(c, code)
            val sb = StringBuilder()
            var last = 0L
            BufferedReader(InputStreamReader(c.inputStream, Charsets.UTF_8)).useLines { lines ->
                for (line in lines) {
                    if (!line.startsWith("data:")) continue
                    val ev = runCatching { JSONObject(line.removePrefix("data:").trim()) }.getOrNull() ?: continue
                    when (ev.optString("type")) {
                        "content_block_delta" -> {
                            val t = ev.optJSONObject("delta")?.optString("text").orEmpty()
                            if (t.isNotEmpty()) {
                                sb.append(t)
                                val now = System.currentTimeMillis()
                                if (now - last > 40) {
                                    last = now
                                    val snap = sb.toString()
                                    withContext(Dispatchers.Main) { onText(snap) }
                                }
                            }
                        }
                        "error" -> throw ClaudeException(529, ev.optJSONObject("error")?.optString("message") ?: "خطأ أثناء البث")
                    }
                }
            }
            sb.toString()
        }
        onText(full)
        if (full.isBlank()) throw ClaudeException(0, "وصل رد فارغ. جرّب مرة ثانية.")
        return full.trim()
    }
}
