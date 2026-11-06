package app.arabwriter.android.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Block
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.ChatBubble
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.CompareArrows
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.Create
import androidx.compose.material.icons.rounded.Draw
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Equalizer
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.rounded.Forum
import androidx.compose.material.icons.rounded.Healing
import androidx.compose.material.icons.rounded.HelpOutline
import androidx.compose.material.icons.rounded.LibraryBooks
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Memory
import androidx.compose.material.icons.rounded.Movie
import androidx.compose.material.icons.rounded.Notes
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.material.icons.rounded.Save
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.Sms
import androidx.compose.material.icons.rounded.Spellcheck
import androidx.compose.material.icons.rounded.Straighten
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.Timeline
import androidx.compose.material.icons.rounded.Translate
import androidx.compose.material.icons.rounded.TrendingUp
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.AutoStories
import androidx.compose.material.icons.rounded.Work
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.TextFields
import androidx.compose.material.icons.rounded.FormatTextdirectionRToL
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.arabwriter.android.core.ArabicLinter
import app.arabwriter.android.core.LintOptions
import app.arabwriter.android.core.LintReport
import app.arabwriter.android.service.AppSettings
import app.arabwriter.android.service.ArabicPdfWriter
import app.arabwriter.android.service.DocxDocument
import app.arabwriter.android.service.Platform
import app.arabwriter.android.service.Register
import app.arabwriter.android.service.StoryLength
import app.arabwriter.android.service.TranslateDirection
import app.arabwriter.android.service.VideoOptions
import app.arabwriter.android.service.VideoPlan
import app.arabwriter.android.service.WriteMode
import app.arabwriter.android.service.WriteRequest
import app.arabwriter.android.service.WriteResult
import app.arabwriter.android.service.WritingEngine
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// ---------- أدوات مشتركة ----------

/** الفحص في الخلفية حتى لا يتجمد البرنامج مع النصوص الطويلة. */
suspend fun lintAsync(text: String, opts: LintOptions): LintReport = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
    runCatching { ArabicLinter.check(text, opts) }.getOrElse { LintReport() }
}

fun copyText(ctx: Context, text: String) {
    (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Arab Writer", text))
}

fun pasteText(ctx: Context): String? =
    (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip?.takeIf { it.itemCount > 0 }
        ?.getItemAt(0)?.coerceToText(ctx)?.toString()

val WriteMode.icon get() = when (this) { WriteMode.REWRITE -> Icons.Rounded.AutoAwesome; WriteMode.PROOFREAD -> Icons.Rounded.Spellcheck; WriteMode.WRITE -> Icons.Rounded.Create }
val Register.icon get() = when (this) { Register.KEEP -> Icons.Rounded.Equalizer; Register.SAUDI -> Icons.Rounded.Forum; Register.FUSHA -> Icons.Rounded.LibraryBooks }
val StoryLength.icon get() = when (this) { StoryLength.FLASH -> Icons.Rounded.Bolt; StoryLength.SHORT -> Icons.Rounded.AutoStories; StoryLength.SCRIPT -> Icons.Rounded.Movie }

val Platform.icon: ImageVector get() = when (this) {
    Platform.NONE -> Icons.Rounded.Block; Platform.X -> Icons.Rounded.ChatBubble; Platform.INSTAGRAM -> Icons.Rounded.PhotoLibrary
    Platform.LINKEDIN -> Icons.Rounded.Work; Platform.WHATSAPP -> Icons.Rounded.Sms; Platform.OFFICIAL -> Icons.Rounded.Draw
    Platform.SCRIPT -> Icons.Rounded.Movie
}

val Platform.colors: List<Color> get() = when (this) {
    Platform.NONE -> listOf(Color(0xFF8C8C91), Color(0xFF66666B))
    Platform.X -> listOf(Color(0xFF2E2E2E), Color.Black)
    Platform.INSTAGRAM -> listOf(Color(0xFFFCB045), Color(0xFFFD1D78), Color(0xFF833AB4))
    Platform.LINKEDIN -> listOf(Color(0xFF0A66C2), Color(0xFF004C99))
    Platform.WHATSAPP -> listOf(Color(0xFF25D366), Color(0xFF128C7E))
    Platform.OFFICIAL -> listOf(Color(0xFF1F3366), Color(0xFFBF9940))
    Platform.SCRIPT -> listOf(AW.Orange, AW.Pink)
}

@Composable
fun PlatformTile(p: Platform, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val tint = p.colors[p.colors.size / 2]
    val view = androidx.compose.ui.platform.LocalView.current
    Column(
        modifier.heightIn(min = 96.dp).touchTilt(18.dp, tint, 9f).glass(18.dp, if (selected) tint else null)
            .then(if (selected) Modifier.background(tint.copy(alpha = 0.18f)) else Modifier)
            .clickable { Feedback.tap(view); safely(onClick) }.padding(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Box {
            Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(Brush.linearGradient(p.colors)), contentAlignment = Alignment.Center) {
                Icon(p.icon, null, Modifier.size(20.dp), tint = Color.White)
            }
            if (selected) Icon(Icons.Rounded.CheckCircle, null, Modifier.size(16.dp).align(Alignment.TopEnd)
                .background(Color.White, CircleShape), tint = tint)
        }
        Spacer(Modifier.size(6.dp))
        Text(p.label, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        Text(p.caption, fontSize = 10.sp, color = secondaryText, maxLines = 1)
    }
}

@Composable
fun SmallIcon(icon: ImageVector, label: String, onClick: () -> Unit) {
    Icon(icon, label, Modifier.size(34.dp).clip(CircleShape).clickable { safely(onClick) }.padding(8.dp), tint = secondaryText)
}

@Composable
fun <T> TileChoice(items: List<T>, selected: T, tint: Color, label: (T) -> String, icon: (T) -> ImageVector, onPick: (T) -> Unit) {
    TileRow { m -> items.forEach { ActionTile(label(it), icon(it), tint, m, selected = it == selected) { onPick(it) } } }
}

// ---------- الكتابة ----------

@Composable
fun WriterScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val saver = rememberSaver()
    var input by remember { mutableStateOf("") }
    var mode by remember { mutableStateOf(WriteMode.REWRITE) }
    var register by remember { mutableStateOf(Register.KEEP) }
    var platform by remember { mutableStateOf(Platform.NONE) }
    var lock by remember { mutableStateOf(false) }
    var words by remember { mutableIntStateOf(60) }
    var result by remember { mutableStateOf<WriteResult?>(null) }
    var live by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    var showDiff by remember { mutableStateOf(false) }

    LaunchedEffect(Inbox.text) {
        Inbox.text?.let { input = it; result = null; Inbox.text = null; Toasts.show("وصل النص، اختر المهمة واضغط نفّذ") }
    }

    fun run() {
        working = true; showDiff = false; live = ""
        scope.launch {
            try {
                result = WritingEngine.run(WriteRequest(input, mode, register, platform, if (lock) words else null)) { live = it }
                if (!AppSettings.hasKey) Toasts.show("أصلحتُ الآمن آلياً. أضف مفتاحك لإعادة الصياغة الكاملة")
            } catch (e: Exception) { Toasts.show(e.message ?: "تعذّر التنفيذ", true) }
            working = false; live = ""
        }
    }

    SectionScroll {
        HeroHeader("نص", Icons.Rounded.AutoAwesome, AW.Blue, "اكتب بصوت إنسان", mode.hint)

        GlassPanel {
            SectionLabel("المهمة", Icons.Rounded.Edit); Spacer(Modifier.height(10.dp))
            TileChoice(WriteMode.entries, mode, AW.Blue, { it.label }, { it.icon }) { mode = it }
        }
        GlassPanel {
            SectionLabel("السجل", Icons.Rounded.Forum); Spacer(Modifier.height(10.dp))
            TileChoice(Register.entries, register, AW.Teal, { it.label }, { it.icon }) { register = it }
        }
        GlassPanel {
            SectionLabel("المنصة", Icons.Rounded.PhotoLibrary); Spacer(Modifier.height(10.dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Platform.entries.chunked(4).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { p -> PlatformTile(p, platform == p, Modifier.weight(1f)) { platform = p } }
                        repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }

        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ActionTile("قفل الطول", Icons.Rounded.Straighten, AW.Orange, Modifier.width(100.dp), selected = lock) { lock = !lock }
            AnimatedVisibility(lock) {
                Row(Modifier.glass(26.dp).padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("−", fontSize = 22.sp, modifier = Modifier.clickable { words = maxOf(10, words - 10) }.padding(horizontal = 10.dp))
                    Text("$words كلمة", fontWeight = FontWeight.SemiBold)
                    Text("+", fontSize = 22.sp, modifier = Modifier.clickable { words = minOf(1000, words + 10) }.padding(horizontal = 10.dp))
                }
            }
        }

        GlassPanel {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionLabel(if (mode == WriteMode.WRITE) "الفكرة" else "النص الأصلي", Icons.Rounded.Notes)
                Spacer(Modifier.weight(1f))
                Text("${ArabicLinter.words(input).size} كلمة", fontSize = 12.sp, color = secondaryText)
                SmallIcon(Icons.Rounded.ContentPaste, "لصق") { pasteText(ctx)?.let { input = it } }
                SmallIcon(Icons.Rounded.Close, "مسح") { input = ""; result = null }
            }
            ArabicEditor(input, { input = it }, if (mode == WriteMode.WRITE) "اكتب فكرتك هنا… مثال: تطبيق جديد يرتب مواعيد الصيدلية" else "الصق النص هنا…")
        }

        PrimaryButton(if (working) "يشتغل…" else "نفّذ", Icons.Rounded.AutoAwesome, AW.Blue, input.isNotBlank(), working, Modifier.fillMaxWidth()) { run() }

        if (working && live.isNotEmpty()) GlassPanel(tint = AW.Blue) { LiveText(live, AW.Blue) }

        val r = result
        if (r != null && !working) {
            GlassPanel(tint = AW.Blue) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    SectionLabel("النتيجة", Icons.Rounded.AutoAwesome)
                    if (!r.usedAI) Text("  إصلاح آلي فقط", fontSize = 11.sp, color = AW.Orange, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.weight(1f))
                    SmallIcon(Icons.Rounded.CompareArrows, "التغييرات") { showDiff = !showDiff }
                    SmallIcon(Icons.Rounded.ContentCopy, "نسخ") { copyText(ctx, r.text); Toasts.show("نُسخ النص") }
                    SmallIcon(Icons.Rounded.Save, "حفظ") { saver.save("Arab Writer.docx", Mime.DOCX, DocxDocument.build(r.text)) }
                }
                Spacer(Modifier.height(8.dp))
                if (showDiff) DiffList(r) else SelectableText(r.text)
                r.question?.let {
                    Spacer(Modifier.height(10.dp))
                    Notice(it, AW.Orange, Icons.Rounded.HelpOutline)
                }
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ActionTile("PDF", Icons.Rounded.Save, AW.Pink, Modifier.weight(1f)) { saver.save("Arab Writer.pdf", Mime.PDF, ArabicPdfWriter.make(r.text)) }
                    ActionTile("نص", Icons.Rounded.Notes, AW.Gray, Modifier.weight(1f)) { saver.save("Arab Writer.txt", Mime.TXT, r.text.toByteArray()) }
                    ActionTile("انقل للأصل", Icons.Rounded.SwapHoriz, AW.Indigo, Modifier.weight(1f)) { input = r.text; result = null }
                }
            }
            GlassPanel { SectionLabel("تقرير الفحص", Icons.Rounded.Verified); Spacer(Modifier.height(10.dp)); ReportView(r.report) }
        } else if (!working) {
            FeatureGrid(listOf(
                Feature(Icons.Rounded.AutoAwesome, "يمسح البصمات", "«في عالم اليوم» و«يلعب دوراً» وأخواتها"),
                Feature(Icons.Rounded.Spellcheck, "يدقق اللغة", "الهمزات والتاء والترقيم والنحو الشائع"),
                Feature(Icons.Rounded.Shield, "لا يختلق", "أي رقم أو اسم جديد ينكشف ويتعلّم عليه"),
                Feature(Icons.Rounded.CompareArrows, "يوريك الفرق", "كل كلمة تغيّرت عن الأصل"),
            ), AW.Blue)
        }
    }
}

@Composable
fun SelectableText(text: String, size: Int = 16) {
    androidx.compose.foundation.text.selection.SelectionContainer {
        Text(text, fontSize = size.sp, lineHeight = (size * 1.65).sp, style = TextStyle(textDirection = TextDirection.Content))
    }
}

@Composable
private fun DiffList(r: WriteResult) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("التشابه مع الأصل ${r.similarity}% · ${r.changes.size} تغيير", fontSize = 12.sp, color = secondaryText)
        r.changes.forEach { c ->
            Row {
                Text(c.op.label, fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clip(CircleShape).background(AW.Blue.copy(alpha = 0.14f)).padding(horizontal = 8.dp, vertical = 2.dp))
                Spacer(Modifier.width(8.dp))
                Column {
                    if (c.before.isNotEmpty()) Text(c.before, color = AW.Pink, textDecoration = TextDecoration.LineThrough)
                    if (c.after.isNotEmpty()) Text(c.after, color = AW.Green)
                }
            }
        }
    }
}

// ---------- الفاحص ----------

@Composable
fun CheckerScreen() {
    val ctx = LocalContext.current
    var text by remember { mutableStateOf("") }
    var source by remember { mutableStateOf("") }
    var useSource by remember { mutableStateOf(false) }
    var lock by remember { mutableStateOf(false) }
    var words by remember { mutableIntStateOf(60) }
    var report by remember { mutableStateOf(LintReport()) }

    LaunchedEffect(text, source, useSource, lock, words) {
        delay(220)
        val opts = LintOptions(if (lock) words else null, null, if (useSource && source.isNotBlank()) source else null, AppSettings.englishOnOwnLine)
        report = lintAsync(text, opts)
    }

    SectionScroll {
        HeroHeader("فحص", Icons.Rounded.Verified, AW.Green, "افحص قبل ما تنشر", "يكشف البصمات والأخطاء لحظة الكتابة، بدون إنترنت")
        TileRow { m ->
            ActionTile("قارن بالأصل", Icons.Rounded.CompareArrows, AW.Indigo, m, selected = useSource) { useSource = !useSource }
            ActionTile("قفل الطول", Icons.Rounded.Straighten, AW.Orange, m, selected = lock) { lock = !lock }
            ActionTile("انسخ", Icons.Rounded.ContentCopy, AW.Blue, m, enabled = text.isNotEmpty()) { copyText(ctx, text); Toasts.show("نُسخ النص") }
            ActionTile("أصلح الآمن", Icons.Rounded.Healing, AW.Green, m, enabled = text.isNotEmpty()) {
                text = ArabicLinter.fix(text, AppSettings.englishOnOwnLine); Toasts.show("أُصلح الآمن: الإملاء والترقيم والمسافات")
            }
        }
        AnimatedVisibility(lock) {
            Row(Modifier.glass(26.dp).padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("−", fontSize = 22.sp, modifier = Modifier.clickable { words = maxOf(10, words - 10) }.padding(horizontal = 10.dp))
                Text("$words كلمة", fontWeight = FontWeight.SemiBold)
                Text("+", fontSize = 22.sp, modifier = Modifier.clickable { words = minOf(1000, words + 10) }.padding(horizontal = 10.dp))
            }
        }
        AnimatedVisibility(useSource) {
            GlassPanel {
                SectionLabel("الأصل", Icons.Rounded.Notes)
                ArabicEditor(source, { source = it }, "الصق النص الأصلي لكشف الأرقام والأسماء المضافة", minHeight = 100.dp)
            }
        }
        GlassPanel {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionLabel("النص", Icons.Rounded.Notes); Spacer(Modifier.weight(1f))
                SmallIcon(Icons.Rounded.ContentPaste, "لصق") { pasteText(ctx)?.let { text = it } }
                SmallIcon(Icons.Rounded.Close, "مسح") { text = "" }
            }
            ArabicEditor(text, { text = it }, "اكتب أو الصق النص، والفحص يجري وأنت تكتب…", minHeight = 200.dp)
        }
        GlassPanel(tint = if (text.isEmpty()) null else if (report.isClean) AW.Green else AW.Pink) {
            SectionLabel("التقرير", Icons.Rounded.Verified); Spacer(Modifier.height(10.dp))
            if (text.isEmpty()) FeatureGrid(listOf(
                Feature(Icons.Rounded.Memory, "بصمات آلية", "افتتاح وختام وحشو وترجمة حرفية"),
                Feature(Icons.Rounded.Spellcheck, "الإملاء", "أكثر من ٢٠٠ خطأ شائع"),
                Feature(Icons.Rounded.TextFields, "الترقيم", "الفواصل والمسافات وعلامة الاستفهام"),
                Feature(Icons.Rounded.FormatTextdirectionRToL, "الاتجاه", "الإنجليزي داخل السطر العربي"),
                Feature(Icons.Rounded.Timeline, "الإيقاع", "جمل متشابهة الطول وتقطيع درامي"),
                Feature(Icons.Rounded.Shield, "الاختلاق", "أرقام وأسماء ما هي في الأصل"),
            ), AW.Green) else ReportView(report)
        }
    }
}

// ---------- الترجمة ----------

@Composable
fun TranslateScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var input by remember { mutableStateOf("") }
    var dir by remember { mutableStateOf(TranslateDirection.AUTO) }
    var register by remember { mutableStateOf(Register.KEEP) }
    var result by remember { mutableStateOf<WriteResult?>(null) }
    var live by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    val resolved = dir.resolved(input)

    SectionScroll {
        HeroHeader("ترجمة", Icons.Rounded.Translate, AW.Teal, "ترجمة بصوت إنسان", "تنقل المعنى لا الكلمات، وتمر على نفس الفحص فتطلع طبيعية")
        GlassPanel {
            SectionLabel("الاتجاه", Icons.Rounded.SwapHoriz); Spacer(Modifier.height(10.dp))
            TileChoice(TranslateDirection.entries, dir, AW.Teal, { it.label }, { Icons.Rounded.Translate }) { dir = it }
        }
        AnimatedVisibility(resolved == TranslateDirection.TO_ARABIC) {
            GlassPanel {
                SectionLabel("العربي الناتج", Icons.Rounded.Forum); Spacer(Modifier.height(10.dp))
                TileChoice(Register.entries, register, AW.Blue, { if (it == Register.KEEP) "حسب النص" else it.label }, { it.icon }) { register = it }
            }
        }
        GlassPanel {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionLabel(if (resolved == TranslateDirection.TO_ARABIC) "English" else "العربي", Icons.Rounded.Notes)
                Spacer(Modifier.weight(1f))
                SmallIcon(Icons.Rounded.ContentPaste, "لصق") { pasteText(ctx)?.let { input = it } }
            }
            ArabicEditor(input, { input = it }, "الصق النص بأي لغة من الاثنتين…", minHeight = 150.dp)
        }
        if (!AppSettings.hasKey) Notice("الترجمة تحتاج مفتاح Claude. أضفه من الإعدادات")
        PrimaryButton(if (working) "يترجم…" else "ترجم", Icons.Rounded.Translate, AW.Teal, input.isNotBlank() && AppSettings.hasKey, working, Modifier.fillMaxWidth()) {
            working = true; live = ""
            scope.launch {
                try { result = WritingEngine.translate(input, dir, register) { live = it } }
                catch (e: Exception) { Toasts.show(e.message ?: "تعذّرت الترجمة", true) }
                working = false; live = ""
            }
        }
        if (working && live.isNotEmpty()) GlassPanel(tint = AW.Teal) { LiveText(live, AW.Teal) }
        val r = result
        if (r != null && !working) {
            GlassPanel(tint = AW.Teal) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    SectionLabel(if (resolved == TranslateDirection.TO_ARABIC) "العربي" else "English", Icons.Rounded.AutoAwesome)
                    Spacer(Modifier.weight(1f))
                    SmallIcon(Icons.Rounded.SwapHoriz, "بدّل") { input = r.text; result = null }
                    SmallIcon(Icons.Rounded.ContentCopy, "نسخ") { copyText(ctx, r.text); Toasts.show("نُسخت الترجمة") }
                }
                SelectableText(r.text)
            }
            if (r.report.issues.isNotEmpty() || resolved == TranslateDirection.TO_ARABIC)
                GlassPanel { SectionLabel("فحص الترجمة", Icons.Rounded.Verified); Spacer(Modifier.height(10.dp)); ReportView(r.report) }
        } else if (!working) FeatureGrid(listOf(
            Feature(Icons.Rounded.ChatBubble, "المعنى لا الحرف", "يعيد بناء الجملة كما يقولها صاحب اللغة"),
            Feature(Icons.Rounded.AutoAwesome, "بلا بصمات", "لا «يلعب دوراً» ولا «delve»"),
            Feature(Icons.Rounded.Lock, "أمين", "لا يضيف رقماً ولا يحذف اسماً"),
        ), AW.Teal, 1)
    }
}

// ---------- القصة ----------

@Composable
fun StoryScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val saver = rememberSaver()
    var title by remember { mutableStateOf("") }
    var length by remember { mutableStateOf(StoryLength.SHORT) }
    var register by remember { mutableStateOf(Register.KEEP) }
    var result by remember { mutableStateOf<WriteResult?>(null) }
    var live by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }

    SectionScroll {
        HeroHeader("قصة", Icons.Rounded.AutoStories, AW.Purple, "من عنوان إلى قصة", "قصة قصيرة تُقرأ في أقل من دقيقتين، بلا تمهيد ولا موعظة")
        GlassPanel {
            ArabicEditor(title, { title = it }, "العنوان أو الفكرة… مثال: آخر رحلة قطار من الأحساء", minHeight = 50.dp)
            Spacer(Modifier.height(12.dp))
            SectionLabel("الطول"); Spacer(Modifier.height(8.dp))
            TileChoice(StoryLength.entries, length, AW.Purple, { it.label }, { it.icon }) { length = it }
            Spacer(Modifier.height(12.dp))
            SectionLabel("اللغة"); Spacer(Modifier.height(8.dp))
            TileChoice(Register.entries, register, AW.Pink, { if (it == Register.KEEP) "حسب العنوان" else it.label }, { it.icon }) { register = it }
            Spacer(Modifier.height(8.dp))
            Text("${length.range} كلمة", fontSize = 12.sp, color = secondaryText)
        }
        if (!AppSettings.hasKey) Notice("القصة تحتاج مفتاح Claude. أضفه من الإعدادات")
        PrimaryButton(if (working) "يكتب…" else "اكتب القصة", Icons.Rounded.AutoAwesome, AW.Purple, title.isNotBlank() && AppSettings.hasKey, working, Modifier.fillMaxWidth()) {
            working = true; live = ""
            scope.launch {
                try { result = WritingEngine.story(title, length, register) { live = it } }
                catch (e: Exception) { Toasts.show(e.message ?: "تعذّرت الكتابة", true) }
                working = false; live = ""
            }
        }
        if (working && live.isNotEmpty()) GlassPanel(tint = AW.Purple) { LiveText(live, AW.Purple) }
        val r = result
        if (r != null && !working) GlassPanel(tint = AW.Purple) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionLabel("القصة", Icons.Rounded.AutoStories); Spacer(Modifier.weight(1f))
                Text("${r.report.stats.words} كلمة", fontSize = 12.sp, color = secondaryText)
                SmallIcon(Icons.Rounded.ContentCopy, "نسخ") { copyText(ctx, r.text); Toasts.show("نُسخت القصة") }
                SmallIcon(Icons.Rounded.Save, "PDF") {
                    val lines = r.text.split('\n')
                    saver.save("${title.ifBlank { "قصة" }}.pdf", Mime.PDF,
                        ArabicPdfWriter.make(lines.drop(1).joinToString("\n").trim(), lines.firstOrNull()))
                }
            }
            SelectableText(r.text, 18)
        } else if (!working) FeatureGrid(listOf(
            Feature(Icons.Rounded.DirectionsWalk, "يبدأ بفعل", "شخص يسوي شيئاً في مكان وزمن محدد"),
            Feature(Icons.Rounded.TrendingUp, "تصعيد", "شيء يقاوم البطل ويضيّق خياراته"),
            Feature(Icons.Rounded.SwapHoriz, "نقطة تحول", "قرار أو معلومة تقلب الموقف"),
            Feature(Icons.Rounded.Flag, "نهاية صامتة", "تغلق المشهد بلا شرح للمغزى"),
        ), AW.Purple)
    }
}

// ---------- الفيديو ----------

@Composable
fun VideoScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var input by remember { mutableStateOf("") }
    var seconds by remember { mutableIntStateOf(10) }
    var style by remember { mutableIntStateOf(0) }
    var audio by remember { mutableIntStateOf(0) }
    var hero by remember { mutableIntStateOf(0) }
    var plan by remember { mutableStateOf<VideoPlan?>(null) }
    var working by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf("") }

    val styles = listOf("3D Pixar" to "3D بكسار", "Cinematic realism" to "سينمائي", "Anime" to "أنمي", "Motion graphics" to "موشن")
    val audios = listOf("موسيقى ومؤثرات بلا حوار" to "موسيقى", "حوار عربي منطوق" to "حوار عربي", "تعليق صوتي" to "تعليق")
    val heroes = listOf(
        "بلا بطل محدد" to "بدون بطل",
        "الخيار أ: شاب سعودي 3D Pixar، ثوب أبيض، شماغ أحمر وعقال أسود، نظارة سوداء سميكة، لحية مهذبة، AirPods" to "بشماغ",
        "الخيار ب: شاب سعودي 3D Pixar، ثوب أبيض، بلا شماغ، نظارة سوداء سميكة، لحية مهذبة، AirPods" to "بدون شماغ",
    )
    val shotColors = listOf(AW.Orange, AW.Pink, AW.Purple, AW.Blue, AW.Teal, AW.Green, AW.Indigo)

    SectionScroll {
        HeroHeader("فيديو", Icons.Rounded.Movie, AW.Orange, "من النص إلى فيديو", "سكربت مقطّع بالثواني، وبرومبت جاهز لكل مقطع، وحزمة كابشن")
        GlassPanel {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionLabel("النص أو الفكرة", Icons.Rounded.Notes); Spacer(Modifier.weight(1f))
                SmallIcon(Icons.Rounded.ContentPaste, "لصق") { pasteText(ctx)?.let { input = it } }
            }
            ArabicEditor(input, { input = it }, "الصق السكربت أو اكتب الفكرة… مثال: شاب يحاول يطبخ كبسة أول مرة ويحترق الرز", minHeight = 120.dp)
        }
        GlassPanel {
            SectionLabel("المدة"); Spacer(Modifier.height(8.dp))
            TileChoice(listOf(8, 10, 15, 30), seconds, AW.Orange, { "$it ث" }, { Icons.Rounded.Timeline }) { seconds = it }
            Spacer(Modifier.height(12.dp)); SectionLabel("الأسلوب"); Spacer(Modifier.height(8.dp))
            TileChoice(styles.indices.toList(), style, AW.Purple, { styles[it].second }, { Icons.Rounded.AutoAwesome }) { style = it }
            Spacer(Modifier.height(12.dp)); SectionLabel("الصوت"); Spacer(Modifier.height(8.dp))
            TileChoice(audios.indices.toList(), audio, AW.Blue, { audios[it].second }, { Icons.Rounded.Forum }) { audio = it }
            Spacer(Modifier.height(12.dp)); SectionLabel("البطل"); Spacer(Modifier.height(8.dp))
            TileChoice(heroes.indices.toList(), hero, AW.Green, { heroes[it].second }, { Icons.Rounded.DirectionsWalk }) { hero = it }
        }
        if (!AppSettings.hasKey) Notice("الفيديو يحتاج مفتاح Claude. أضفه من الإعدادات")
        PrimaryButton(if (working) progress.ifEmpty { "يجهّز…" } else "جهّز الحزمة", Icons.Rounded.Movie, AW.Orange,
            input.isNotBlank() && AppSettings.hasKey, working, Modifier.fillMaxWidth()) {
            working = true; progress = ""
            scope.launch {
                try {
                    plan = WritingEngine.video(input, VideoOptions(seconds, styles[style].first, audios[audio].first, heroes[hero].first, "ريلز وشورتس")) { p ->
                        val n = p.split("\"action\"").size - 1
                        val m = p.split("\"prompt\"").size - 1
                        progress = if (m > 0) "يكتب البرومبت $m…" else if (n > 0) "يقطّع اللقطة $n…" else "ينظّف النص…"
                    }
                } catch (e: Exception) { Toasts.show(e.message ?: "تعذّر التجهيز", true) }
                working = false
            }
        }
        plan?.let { p ->
            val ok = Math.abs(p.totalSeconds - seconds) < 0.01
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("الحزمة", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.width(10.dp))
                Text(if (ok) "المدة مضبوطة $seconds ث" else "المجموع ${VideoPlan.fmt(p.totalSeconds)} ث من $seconds",
                    color = if (ok) AW.Green else AW.Orange, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.glass(14.dp).padding(horizontal = 10.dp, vertical = 4.dp))
                Spacer(Modifier.weight(1f))
                SmallIcon(Icons.Rounded.ContentCopy, "انسخ الحزمة") { copyText(ctx, p.packageText); Toasts.show("نُسخت الحزمة كاملة") }
            }
            GlassPanel {
                SectionLabel("الخط الزمني", Icons.Rounded.Timeline); Spacer(Modifier.height(10.dp))
                val total = p.totalSeconds.coerceAtLeast(1.0)
                Row(Modifier.fillMaxWidth().height(32.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    p.shots.forEachIndexed { i, s ->
                        Box(Modifier.weight((s.seconds / total).toFloat().coerceAtLeast(0.04f)).height(32.dp).clip(RoundedCornerShape(8.dp))
                            .background(shotColors[i % shotColors.size]), contentAlignment = Alignment.Center) {
                            Text("${i + 1}", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 12.sp)
                        }
                    }
                }
                Spacer(Modifier.height(10.dp))
                p.shots.forEachIndexed { i, s ->
                    Row(Modifier.padding(vertical = 4.dp)) {
                        Text("${VideoPlan.fmt(s.seconds)} ث", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                            modifier = Modifier.clip(CircleShape).background(shotColors[i % shotColors.size]).padding(horizontal = 8.dp, vertical = 2.dp))
                        Spacer(Modifier.width(8.dp)); Text(s.action, fontSize = 14.sp)
                    }
                }
            }
            GlassPanel { SectionLabel("النص النظيف", Icons.Rounded.Notes); Spacer(Modifier.height(6.dp)); SelectableText(p.text, 15) }
            GlassPanel(tint = AW.Purple) {
                SectionLabel("النموذج", Icons.Rounded.Memory); Spacer(Modifier.height(6.dp))
                Text(p.model, fontWeight = FontWeight.Bold, fontSize = 17.sp); Text(p.modelReason, color = secondaryText, fontSize = 14.sp)
            }
            p.segments.forEachIndexed { i, seg ->
                GlassPanel {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        SectionLabel("برومبت المقطع ${i + 1} · ${VideoPlan.fmt(seg.seconds)} ث"); Spacer(Modifier.weight(1f))
                        SmallIcon(Icons.Rounded.ContentCopy, "نسخ") { copyText(ctx, seg.prompt); Toasts.show("نُسخ برومبت المقطع ${i + 1}") }
                    }
                    androidx.compose.runtime.CompositionLocalProvider(androidx.compose.ui.platform.LocalLayoutDirection provides androidx.compose.ui.unit.LayoutDirection.Ltr) {
                        Text(seg.prompt, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace, fontSize = 13.sp,
                            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.onBackground.copy(alpha = 0.05f)).padding(12.dp))
                    }
                }
            }
            GlassPanel(tint = AW.Pink) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    SectionLabel("حزمة الكابشن"); Spacer(Modifier.weight(1f))
                    SmallIcon(Icons.Rounded.ContentCopy, "نسخ") { copyText(ctx, p.caption + "\n\n" + p.hashtags.joinToString(" ")); Toasts.show("نُسخ الكابشن") }
                }
                Text(p.hook, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                p.screenLines.forEach { (at, t) -> Row { Text(at, color = secondaryText, fontSize = 12.sp); Spacer(Modifier.width(8.dp)); Text(t, fontSize = 14.sp) } }
                Spacer(Modifier.height(8.dp)); SelectableText(p.caption, 14)
                Text(p.hashtags.joinToString(" "), color = AW.Blue, fontSize = 14.sp)
            }
        }
    }
}
