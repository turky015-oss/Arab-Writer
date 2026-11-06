package app.arabwriter.android.ui

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.quicksettings.TileService
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.Done
import androidx.compose.material.icons.rounded.Healing
import androidx.compose.material.icons.rounded.OpenInNew
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.arabwriter.android.core.ArabicLinter
import app.arabwriter.android.core.LintOptions
import app.arabwriter.android.core.LintReport
import app.arabwriter.android.service.AppSettings
import app.arabwriter.android.service.Platform
import app.arabwriter.android.service.Register
import app.arabwriter.android.service.WriteMode
import app.arabwriter.android.service.WriteRequest
import app.arabwriter.android.service.WritingEngine
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * نافذة الفحص السريع. تفتح من قائمة النص في أي تطبيق (ظلّل نصاً ← Arab Writer)،
 * أو من بلاطة الإعدادات السريعة.
 */
class QuickCheckActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val incoming = intent?.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        val readOnly = intent?.getBooleanExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, true) ?: true
        val canReplace = intent?.action == Intent.ACTION_PROCESS_TEXT && !readOnly
        setContent {
            ArabWriterTheme {
                QuickCheckSheet(incoming.orEmpty(), canReplace,
                    onReplace = { setResult(RESULT_OK, Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, it)); finish() },
                    onOpenApp = {
                        startActivity(Intent(this, MainActivity::class.java).putExtra("open_text", it).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        finish()
                    },
                    onDismiss = { finish() })
            }
        }
    }
}

@Composable
private fun QuickCheckSheet(initial: String, canReplace: Boolean, onReplace: (String) -> Unit, onOpenApp: (String) -> Unit, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf(initial) }
    var report by remember { mutableStateOf(LintReport()) }
    var working by remember { mutableStateOf(false) }

    LaunchedEffect(text) {
        delay(180)
        report = lintAsync(text, LintOptions(englishOnOwnLine = AppSettings.englishOnOwnLine))
    }

    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)).clickable(onClick = onDismiss), contentAlignment = Alignment.BottomCenter) {
        Column(
            Modifier.fillMaxWidth().padding(10.dp).navigationBarsPadding().glass(30.dp)
                .background(androidx.compose.material3.MaterialTheme.colorScheme.background.copy(alpha = 0.85f))
                .pointerInput(Unit) { detectTapGestures { } }.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconSquare(Icons.Rounded.Verified, AW.Green, 34.dp)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text("فحص سريع", fontWeight = FontWeight.Bold, fontSize = 17.sp)
                    Text("Arab Writer", fontSize = 11.sp, color = secondaryText)
                }
                SmallIcon(Icons.Rounded.OpenInNew, "افتح في البرنامج") { onOpenApp(text) }
            }
            Box(Modifier.fillMaxWidth().heightIn(min = 110.dp, max = 240.dp).glass(18.dp).verticalScroll(rememberScrollState()).padding(12.dp)) {
                ArabicEditor(text, { text = it }, "الصق نصاً أو اكتب هنا…", minHeight = 90.dp)
            }
            TileRow { m ->
                StatTile("${report.stats.words}", "كلمة", androidx.compose.material3.MaterialTheme.colorScheme.onBackground, m)
                StatTile("${report.errors.size}", "خطأ", if (report.errors.isEmpty()) AW.Green else AW.Pink, m)
                StatTile("${report.warnings.size}", "تنبيه", if (report.warnings.isEmpty()) AW.Green else AW.Orange, m)
            }
            if (text.isNotEmpty() && report.issues.isNotEmpty()) Column(Modifier.glass(16.dp).padding(10.dp)) {
                (report.errors + report.warnings).take(3).forEach { IssueRow(it) }
                if (report.issues.size > 3) Text("و${report.issues.size - 3} غيرها", fontSize = 12.sp, color = secondaryText)
            }
            TileRow { m ->
                ActionTile("لصق", Icons.Rounded.ContentPaste, AW.Blue, m) { pasteText(ctx)?.let { text = it } }
                ActionTile("صحّح", Icons.Rounded.Healing, AW.Green, m, enabled = text.isNotEmpty()) {
                    text = ArabicLinter.fix(text, AppSettings.englishOnOwnLine); Toasts.show("صُحّح الآمن")
                }
                ActionTile(if (working) "يصيغ…" else "صغ", Icons.Rounded.AutoAwesome, AW.Purple, m, enabled = text.isNotEmpty() && !working && AppSettings.hasKey) {
                    working = true
                    scope.launch {
                        try { text = WritingEngine.run(WriteRequest(text, WriteMode.REWRITE, Register.KEEP, Platform.NONE, null)) { text = it }.text }
                        catch (e: Exception) { Toasts.show(e.message ?: "تعذّرت الصياغة", true) }
                        working = false
                    }
                }
                if (canReplace) ActionTile("استبدل", Icons.Rounded.Done, AW.Indigo, m, enabled = text.isNotEmpty()) { onReplace(text) }
                else ActionTile("انسخ", Icons.Rounded.ContentCopy, AW.Indigo, m, enabled = text.isNotEmpty()) { copyText(ctx, text); Toasts.show("نُسخ") }
            }
        }
        ToastHost()
    }
}

/** بلاطة «فحص سريع» في الإعدادات السريعة. */
class QuickCheckTile : TileService() {
    @SuppressLint("StartActivityAndCollapseDeprecated")
    override fun onClick() {
        super.onClick()
        val i = Intent(this, QuickCheckActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        } else {
            @Suppress("DEPRECATION") startActivityAndCollapse(i)
        }
    }
}
