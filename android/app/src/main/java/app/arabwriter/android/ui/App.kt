package app.arabwriter.android.ui

import android.app.Application
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.AutoStories
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.PictureAsPdf
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.TableChart
import androidx.compose.material.icons.rounded.Translate
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.VpnKey
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.arabwriter.android.R
import app.arabwriter.android.service.AppSettings
import app.arabwriter.android.service.Files
import app.arabwriter.android.service.PdfTools
import app.arabwriter.android.service.SkillPrompt

// ---------- التطبيق ----------

class ArabWriterApp : Application() {
    override fun onCreate() {
        super.onCreate()
        CrashLog.install(this)
        AppSettings.init(this)
        SkillPrompt.init(this)
        PdfTools.init(this)
    }
}

/** يحفظ سبب أي إغلاق مفاجئ، ويعرضه في الرئيسية عند الفتح التالي. */
object CrashLog {
    private lateinit var file: java.io.File
    var last by mutableStateOf<String?>(null)

    fun install(app: Application) {
        file = java.io.File(app.filesDir, "last-crash.txt")
        last = runCatching { file.takeIf { it.exists() }?.readText() }.getOrNull()
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            runCatching {
                val sw = java.io.StringWriter()
                e.printStackTrace(java.io.PrintWriter(sw))
                file.writeText("Arab Writer ${app.packageManager.getPackageInfo(app.packageName, 0).versionName}\n" +
                    "Android ${android.os.Build.VERSION.RELEASE} · ${android.os.Build.MODEL}\n" +
                    "Thread: ${t.name}\n\n" + sw.toString().take(12000))
            }
            previous?.uncaughtException(t, e)
        }
    }

    fun clear() { runCatching { file.delete() }; last = null }
}

/** نص وصل من تطبيق آخر وينتظر قسم الكتابة. */
object Inbox {
    var text by mutableStateOf<String?>(null)
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        take(intent)
        setContent { ArabWriterTheme { AppRoot() } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        take(intent)
    }

    private fun take(i: Intent?) {
        val t = i?.getStringExtra(Intent.EXTRA_TEXT) ?: i?.getStringExtra("open_text")
        if (!t.isNullOrBlank()) Inbox.text = t
    }
}

enum class AppSection(val title: String, val subtitle: String, val icon: ImageVector, val tint: Color) {
    WRITER("الكتابة", "صياغة وتدقيق وكتابة", Icons.Rounded.AutoAwesome, AW.Blue),
    CHECKER("الفاحص", "فحص فوري بدون إنترنت", Icons.Rounded.Verified, AW.Green),
    TRANSLATE("الترجمة", "عربي وإنجليزي بصوت بشري", Icons.Rounded.Translate, AW.Teal),
    STORY("القصة", "قصة من عنوان", Icons.Rounded.AutoStories, AW.Purple),
    VIDEO("الفيديو", "سكربت ولقطات وبرومبتات", Icons.Rounded.Movie, AW.Orange),
    WORD("وورد", "تدقيق مع بقاء التنسيق", Icons.Rounded.Description, AW.Indigo),
    SHEET("إكسل", "ترتيب وحساب وتنظيف", Icons.Rounded.TableChart, AW.Excel),
    PDF("PDF", "دمج وتقسيم وتلخيص", Icons.Rounded.PictureAsPdf, AW.Pink);

    companion object {
        val text = listOf(WRITER, CHECKER, TRANSLATE, STORY, VIDEO)
        val files = listOf(WORD, SHEET, PDF)
    }
}

@Composable
fun AppRoot() {
    var section by rememberSaveable { mutableStateOf<AppSection?>(null) }
    var settings by rememberSaveable { mutableStateOf(false) }
    val view = LocalView.current

    LaunchedEffect(Inbox.text) { if (Inbox.text != null) { settings = false; section = AppSection.WRITER } }
    BackHandler(section != null || settings) { if (settings) settings = false else section = null }

    Box(Modifier.fillMaxSize()) {
        Backdrop(if (settings) AW.Gray else section?.tint ?: AW.Blue)
        AnimatedContent(
            targetState = if (settings) "settings" else section?.name ?: "home",
            transitionSpec = { (fadeIn(tween(260)) + scaleIn(tween(260), 0.98f)) togetherWith fadeOut(tween(180)) },
            label = "nav",
        ) { key ->
            Column(Modifier.fillMaxSize().statusBarsPadding()) {
                when (key) {
                    "home" -> Home(onOpen = { Feedback.tap(view); section = it }, onSettings = { settings = true })
                    "settings" -> { TopBar("الإعدادات", AW.Gray) { settings = false }; SettingsScreen() }
                    else -> {
                        val s = AppSection.valueOf(key)
                        TopBar(s.title, s.tint) { section = null }
                        when (s) {
                            AppSection.WRITER -> WriterScreen()
                            AppSection.CHECKER -> CheckerScreen()
                            AppSection.TRANSLATE -> TranslateScreen()
                            AppSection.STORY -> StoryScreen()
                            AppSection.VIDEO -> VideoScreen()
                            AppSection.WORD -> WordScreen()
                            AppSection.SHEET -> SheetScreen()
                            AppSection.PDF -> PdfScreen()
                        }
                    }
                }
            }
        }
        ToastHost()
    }
}

@Composable
fun TopBar(title: String, tint: Color, onBack: () -> Unit) {
    val view = LocalView.current
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(42.dp).glass(21.dp).clickable { Feedback.tap(view); onBack() }, contentAlignment = Alignment.Center) {
            Icon(Icons.AutoMirrored.Rounded.ArrowBack, "رجوع", Modifier.size(20.dp))
        }
        Spacer(Modifier.width(12.dp))
        Text(title, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = tint.takeIf { it != AW.Gray } ?: MaterialTheme.colorScheme.onBackground)
    }
}

// ---------- الرئيسية ----------

@Composable
private fun Home(onOpen: (AppSection) -> Unit, onSettings: () -> Unit) {
    var query by remember { mutableStateOf("") }
    val q = query.trim()
    fun match(s: AppSection) = q.isEmpty() || s.title.contains(q) || s.subtitle.contains(q) || s.name.contains(q, true)
    SectionScroll {
        Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Image(painterResource(R.drawable.app_logo), null, Modifier.size(58.dp).shadow(8.dp, RoundedCornerShape(14.dp)).clip(RoundedCornerShape(14.dp))
                .touchTilt(14.dp, AW.Orange, 16f))
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text("Arab Writer", fontSize = 26.sp, fontWeight = FontWeight.Bold)
                Text("محرّك كتابة ومستندات عربي", fontSize = 14.sp, color = secondaryText)
            }
            Box(Modifier.size(44.dp).glass(22.dp).clickable { onSettings() }, contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Settings, "الإعدادات", Modifier.size(22.dp))
            }
        }

        Row(Modifier.fillMaxWidth().glass(24.dp).padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Search, null, tint = secondaryText, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(10.dp))
            Box(Modifier.weight(1f)) {
                if (query.isEmpty()) Text("ابحث أو انتقل", color = tertiaryText)
                BasicTextField(query, { query = it }, Modifier.fillMaxWidth(), singleLine = true,
                    textStyle = TextStyle(color = MaterialTheme.colorScheme.onBackground, fontSize = 16.sp), cursorBrush = SolidColor(AW.Blue))
            }
        }

        KeyBadge(onSettings)
        CrashLog.last?.let { log -> CrashCard(log) }

        val textItems = AppSection.text.filter(::match)
        val fileItems = AppSection.files.filter(::match)
        if (textItems.isNotEmpty()) { SectionLabel("النص"); SectionGrid(textItems, onOpen) }
        if (fileItems.isNotEmpty()) { SectionLabel("الملفات"); SectionGrid(fileItems, onOpen) }
        if (textItems.isEmpty() && fileItems.isEmpty()) Text("ما فيه قسم بهذا الاسم", color = secondaryText)
    }
}

@Composable
private fun CrashCard(log: String) {
    val ctx = LocalContext.current
    GlassPanel(tint = AW.Pink) {
        SectionLabel("البرنامج انقفل آخر مرة")
        Spacer(Modifier.size(6.dp))
        Text("انسخ التقرير وأرسله للمطوّر حتى يُصلح السبب.", fontSize = 14.sp)
        Spacer(Modifier.size(6.dp))
        Text(log.lines().take(6).joinToString("\n"), fontSize = 11.sp, color = secondaryText, maxLines = 6)
        Spacer(Modifier.size(10.dp))
        TileRow { m ->
            ActionTile("انسخ التقرير", Icons.Rounded.ContentCopy, AW.Pink, m) { copyText(ctx, log); Toasts.show("نُسخ التقرير") }
            ActionTile("تجاهل", Icons.Rounded.Close, AW.Gray, m) { CrashLog.clear() }
        }
    }
}

@Composable
private fun SectionGrid(items: List<AppSection>, onOpen: (AppSection) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        items.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { s ->
                    Column(
                        Modifier.weight(1f).heightIn(min = 128.dp).touchTilt(22.dp, s.tint, 9f).glass(22.dp, s.tint)
                            .clickable { onOpen(s) }.padding(14.dp),
                        verticalArrangement = Arrangement.SpaceBetween,
                    ) {
                        IconSquare(s.icon, s.tint, 44.dp)
                        Spacer(Modifier.size(12.dp))
                        Text(s.title, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                        Text(s.subtitle, fontSize = 12.sp, color = secondaryText, maxLines = 2)
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun KeyBadge(onSettings: () -> Unit) {
    val on = AppSettings.hasKey
    val c = if (on) AW.Green else AW.Orange
    Row(Modifier.fillMaxWidth().glass(18.dp).clickable { onSettings() }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).shadow(6.dp, CircleShape, spotColor = c).clip(CircleShape).background(c))
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(if (on) "الذكاء مفعّل" else "وضع بدون إنترنت", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            Text(if (on) "Claude متصل بمفتاحك" else "أضف مفتاحك للمزايا الذكية", fontSize = 12.sp, color = secondaryText)
        }
        Icon(Icons.Rounded.VpnKey, null, tint = secondaryText, modifier = Modifier.size(18.dp))
    }
}

// ---------- الإعدادات ----------

@Composable
private fun SettingsScreen() {
    var key by remember { mutableStateOf("") }
    val uri = LocalUriHandler.current
    SectionScroll {
        GlassPanel {
            SectionLabel("مفتاح Claude", Icons.Rounded.VpnKey)
            Spacer(Modifier.size(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(9.dp).clip(CircleShape).background(if (AppSettings.hasKey) AW.Green else AW.Orange))
                Spacer(Modifier.width(8.dp))
                Text(if (AppSettings.hasKey) "المفتاح محفوظ ومشفّر على جهازك" else "لا يوجد مفتاح", Modifier.weight(1f))
                if (AppSettings.hasKey) Text("حذف", color = AW.Pink, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clickable { AppSettings.removeKey(); Toasts.show("حُذف المفتاح") }.padding(6.dp))
            }
            Spacer(Modifier.size(10.dp))
            Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.onBackground.copy(alpha = 0.06f)).padding(14.dp)) {
                if (key.isEmpty()) Text("الصق مفتاحك هنا", color = tertiaryText)
                BasicTextField(key, { key = it }, Modifier.fillMaxWidth(), singleLine = true, visualTransformation = PasswordVisualTransformation(),
                    textStyle = TextStyle(color = MaterialTheme.colorScheme.onBackground, fontSize = 15.sp), cursorBrush = SolidColor(AW.Blue))
            }
            Spacer(Modifier.size(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("احصل على مفتاح من Anthropic", color = AW.Blue, fontSize = 13.sp,
                    modifier = Modifier.weight(1f).clickable { uri.openUri("https://console.anthropic.com/settings/keys") })
                PrimaryButton("حفظ", Icons.Rounded.VpnKey, AW.Blue, key.isNotBlank()) {
                    AppSettings.setKey(key); key = ""; Toasts.show("حُفظ المفتاح")
                }
            }
            Spacer(Modifier.size(8.dp))
            Text("المفتاح يبقى مشفّراً على جوالك، ويُرسل مباشرة إلى Anthropic فقط. الفاحص وأدوات الملفات تشتغل بدونه.",
                fontSize = 12.sp, color = secondaryText)
        }

        GlassPanel {
            SectionLabel("النموذج")
            Spacer(Modifier.size(10.dp))
            AppSettings.models.forEach { (id, name) ->
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                    .background(if (AppSettings.model == id) AW.Blue.copy(alpha = 0.14f) else Color.Transparent)
                    .clickable { AppSettings.updateModel(id) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(name, Modifier.weight(1f), fontWeight = if (AppSettings.model == id) FontWeight.SemiBold else FontWeight.Normal)
                    if (AppSettings.model == id) Icon(Icons.Rounded.Verified, null, tint = AW.Blue, modifier = Modifier.size(18.dp))
                }
            }
        }

        GlassPanel {
            SectionLabel("الكتابة والواجهة")
            ToggleRow("ضع كل كلمة إنجليزية في سطر مستقل", AppSettings.englishOnOwnLine) { AppSettings.updateEnglish(it) }
            ToggleRow("جولة تصحيح ثانية تلقائية إن بقيت أخطاء", AppSettings.autoRetry) { AppSettings.updateRetry(it) }
            ToggleRow("أصوات اللمس", AppSettings.sounds) { AppSettings.updateSounds(it) }
        }

        GlassPanel {
            SectionLabel("صحّح من أي تطبيق")
            Spacer(Modifier.size(8.dp))
            Text("ظلّل أي نص في الواتساب أو المتصفح أو أي تطبيق، واختر «Arab Writer» من قائمة النص اللي تطلع. وتقدر تشارك أي نص للبرنامج من زر المشاركة.",
                fontSize = 14.sp, lineHeight = 21.sp)
            Spacer(Modifier.size(6.dp))
            Text("وللفحص السريع: أضف بلاطة «فحص سريع» من الإعدادات السريعة أعلى الشاشة.", fontSize = 13.sp, color = secondaryText)
        }
    }
}

@Composable
private fun ToggleRow(title: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), fontSize = 14.sp)
        Switch(value, onChange)
    }
}

// ---------- اختيار الملفات وحفظها ----------

object Mime {
    const val DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    const val XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    const val PDF = "application/pdf"
    const val TXT = "text/plain"
    const val CSV = "text/csv"
    const val PNG = "image/png"
}

private class CreateDoc : ActivityResultContract<Pair<String, String>, Uri?>() {
    override fun createIntent(context: Context, input: Pair<String, String>) = Intent(Intent.ACTION_CREATE_DOCUMENT)
        .addCategory(Intent.CATEGORY_OPENABLE).setType(input.second).putExtra(Intent.EXTRA_TITLE, input.first)
    override fun parseResult(resultCode: Int, intent: Intent?): Uri? = intent?.data
}

class FileSaver(private val holder: Array<Any?>, private val launch: (Pair<String, String>) -> Unit, private val launchTree: () -> Unit) {
    /** يحفظ ملفاً واحداً في مكان يختاره المستخدم. */
    fun save(name: String, mime: String, bytes: ByteArray) { holder[0] = bytes; launch(name to mime) }
    /** يحفظ عدة ملفات في مجلد يختاره المستخدم. */
    fun saveMany(items: List<Triple<String, String, ByteArray>>) { holder[1] = items; launchTree() }
}

@Composable
fun rememberSaver(): FileSaver {
    val ctx = LocalContext.current
    val holder = remember { arrayOfNulls<Any?>(2) }
    val one = rememberLauncherForActivityResult(CreateDoc()) { uri ->
        val b = holder[0] as? ByteArray
        holder[0] = null
        if (uri != null && b != null) runCatching { Files.write(ctx, uri, b) }
            .onSuccess { Toasts.show("حُفظ «${Files.name(ctx, uri)}»") }
            .onFailure { Toasts.show(it.message ?: "تعذّر الحفظ", true) }
    }
    val many = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { tree ->
        @Suppress("UNCHECKED_CAST") val items = holder[1] as? List<Triple<String, String, ByteArray>>
        holder[1] = null
        if (tree != null && items != null) runCatching { items.forEach { (n, m, b) -> Files.writeInTree(ctx, tree, n, m, b) } }
            .onSuccess { Toasts.show("حُفظ ${items.size} ملف") }
            .onFailure { Toasts.show(it.message ?: "تعذّر الحفظ", true) }
    }
    return remember(one, many) { FileSaver(holder, { one.launch(it) }, { many.launch(null) }) }
}

@Composable
fun rememberOpener(onFiles: (List<Uri>) -> Unit): (Array<String>) -> Unit {
    val l = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { if (it.isNotEmpty()) onFiles(it) }
    return { mimes -> l.launch(mimes) }
}
