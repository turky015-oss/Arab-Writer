package app.arabwriter.android.ui

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.SoundEffectConstants
import android.view.View
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Error
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.arabwriter.android.core.IssueLevel
import app.arabwriter.android.core.LintIssue
import app.arabwriter.android.core.LintReport
import app.arabwriter.android.service.AppSettings
import kotlinx.coroutines.delay
import kotlin.math.cos
import kotlin.math.sin

// ---------- الألوان ----------

object AW {
    val Blue = Color(0xFF0A84FF)
    val Purple = Color(0xFFBF5AF2)
    val Pink = Color(0xFFFF375F)
    val Orange = Color(0xFFFF9F0A)
    val Teal = Color(0xFF64D2FF)
    val Green = Color(0xFF30D158)
    val Indigo = Color(0xFF5E5CE6)
    val Excel = Color(0xFF21A355)
    val Gray = Color(0xFF8E8E93)
}

@Composable
fun ArabWriterTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val scheme: ColorScheme = if (dark) darkColorScheme(primary = AW.Blue, background = Color(0xFF0E0F13), surface = Color(0xFF16171C))
                              else lightColorScheme(primary = AW.Blue, background = Color(0xFFF4F5F9), surface = Color.White)
    MaterialTheme(colorScheme = scheme) {
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) { content() }
    }
}

val secondaryText @Composable get() = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f)
val tertiaryText @Composable get() = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.38f)

// ---------- الاهتزاز والصوت ----------

object Feedback {
    fun tap(v: View) {
        if (AppSettings.sounds) v.playSoundEffect(SoundEffectConstants.CLICK)
        v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
    }
    fun success(v: View) {
        v.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.LONG_PRESS)
    }
    fun error(v: View) {
        v.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS)
    }
}

/** ينفّذ الفعل، وأي خطأ يطلع رسالة بدل إغلاق البرنامج. */
fun safely(block: () -> Unit) {
    try { block() } catch (e: Throwable) {
        if (e is VirtualMachineError && e !is StackOverflowError) throw e
        Toasts.show(e.message?.takeIf { it.isNotBlank() } ?: "حدث خطأ غير متوقع", true)
    }
}

// ---------- الخلفية الحيّة ----------

@Composable
fun Backdrop(tint: Color, modifier: Modifier = Modifier) {
    val dark = isSystemInDarkTheme()
    val base = MaterialTheme.colorScheme.background
    val t by rememberInfiniteTransition(label = "bg").animateFloat(
        0f, (2 * Math.PI).toFloat(), infiniteRepeatable(tween(60_000, easing = LinearEasing)), label = "phase")
    val tintAnim by animateColorAsState(tint, tween(700), label = "tint")
    val o = if (dark) 0.42f else 0.30f
    Canvas(modifier.fillMaxSize()) {
        drawRect(base)
        val blobs = listOf(
            Triple(Offset(0.85f + 0.06f * sin(t), 0.08f + 0.05f * cos(t)), tintAnim, 0.75f),
            Triple(Offset(0.1f + 0.05f * cos(t * 1.3f), 0.25f), AW.Purple, 0.6f),
            Triple(Offset(0.5f + 0.1f * sin(t * 0.7f), 0.55f + 0.06f * cos(t)), AW.Teal, 0.55f),
            Triple(Offset(0.95f, 0.85f + 0.05f * sin(t * 1.1f)), AW.Pink, 0.5f),
            Triple(Offset(0.05f + 0.05f * sin(t), 0.95f), AW.Orange, 0.45f),
        )
        for ((c, col, r) in blobs) {
            val center = Offset(size.width * c.x, size.height * c.y)
            val rad = size.maxDimension * r
            drawCircle(Brush.radialGradient(listOf(col.copy(alpha = o), col.copy(alpha = 0f)), center, rad), rad, center)
        }
    }
}

// ---------- الزجاج ----------

@Composable
fun Modifier.glass(radius: Dp = 26.dp, tint: Color? = null, selected: Boolean = false): Modifier {
    val dark = isSystemInDarkTheme()
    val shape = RoundedCornerShape(radius)
    val fill = when {
        selected && tint != null -> Brush.verticalGradient(listOf(tint.copy(alpha = 0.95f), tint.copy(alpha = 0.8f)))
        dark -> Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.11f), Color.White.copy(alpha = 0.05f)))
        else -> Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.78f), Color.White.copy(alpha = 0.55f)))
    }
    val edge = Brush.linearGradient(listOf(Color.White.copy(alpha = if (dark) 0.35f else 0.95f), Color.White.copy(alpha = 0.08f),
        Color.White.copy(alpha = if (dark) 0.18f else 0.5f)))
    return this
        .shadow(if (selected) 10.dp else 6.dp, shape, ambientColor = (tint ?: Color.Black).copy(alpha = 0.15f),
            spotColor = (tint ?: Color.Black).copy(alpha = 0.18f))
        .clip(shape)
        .background(fill)
        .then(if (tint != null && !selected) Modifier.background(tint.copy(alpha = 0.07f)) else Modifier)
        .border(1.dp, edge, shape)
}

/** يميل العنصر نحو مكان اللمس ويضيء تحته، مثل تفاعل الماوس في نسخة الماك. */
@Composable
fun Modifier.touchTilt(radius: Dp = 20.dp, glow: Color = Color.White, tilt: Float = 8f): Modifier = composedTilt(radius, glow, tilt)

@Composable
private fun Modifier.composedTilt(radius: Dp, glow: Color, tilt: Float): Modifier {
    var size by remember { mutableStateOf(IntSize.Zero) }
    var point by remember { mutableStateOf<Offset?>(null) }
    val active = point != null
    val p = point ?: Offset(size.width / 2f, size.height / 2f)
    val nx = if (size.width > 0) p.x / size.width - 0.5f else 0f
    val ny = if (size.height > 0) p.y / size.height - 0.5f else 0f
    val spec = spring<Float>(dampingRatio = 0.7f, stiffness = Spring.StiffnessMediumLow)
    val rx by animateFloatAsState(if (active) ny * tilt else 0f, spec, label = "rx")
    val ry by animateFloatAsState(if (active) -nx * tilt else 0f, spec, label = "ry")
    val sc by animateFloatAsState(if (active) 0.97f else 1f, spec, label = "sc")
    val glowA by animateFloatAsState(if (active) 0.35f else 0f, tween(180), label = "g")
    return this
        .onSizeChanged { size = it }
        .graphicsLayer { rotationX = rx; rotationY = ry; scaleX = sc; scaleY = sc; cameraDistance = 14f * density }
        .drawWithContent {
            drawContent()
            if (glowA > 0f) drawRect(Brush.radialGradient(listOf(glow.copy(alpha = glowA), Color.Transparent),
                Offset(p.x, p.y), this.size.maxDimension * 0.7f))
        }
        .pointerInput(Unit) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                point = down.position
                while (true) {
                    val e = awaitPointerEvent(PointerEventPass.Initial)
                    val c = e.changes.firstOrNull() ?: break
                    if (!c.pressed) break
                    point = c.position
                }
                point = null
            }
        }
}

@Composable
fun GlassPanel(modifier: Modifier = Modifier, radius: Dp = 26.dp, tint: Color? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().glass(radius, tint).padding(16.dp), content = content)
}

// ---------- مكوّنات ----------

@Composable
fun SectionLabel(text: String, icon: ImageVector? = null) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        icon?.let { Icon(it, null, Modifier.size(16.dp), tint = secondaryText) }
        Text(text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = secondaryText)
    }
}

@Composable
fun IconSquare(icon: ImageVector, tint: Color, size: Dp = 40.dp, filled: Boolean = true) {
    Box(
        Modifier.size(size).shadow(if (filled) 4.dp else 0.dp, RoundedCornerShape(size * 0.3f), spotColor = tint)
            .clip(RoundedCornerShape(size * 0.3f))
            .background(if (filled) Brush.verticalGradient(listOf(tint, tint.copy(alpha = 0.78f))) else SolidColor(tint.copy(alpha = 0.15f))),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, Modifier.size(size * 0.5f), tint = if (filled) Color.White else tint) }
}

/** شارة مستند بصيغته، بزاوية مطوية. */
@Composable
fun FormatBadge(label: String, icon: ImageVector, tint: Color, size: Dp = 92.dp, modifier: Modifier = Modifier) {
    Box(modifier.size(size * 0.82f, size), contentAlignment = Alignment.BottomCenter) {
        val shape = RoundedCornerShape(size * 0.16f)
        Box(
            Modifier.fillMaxSize().shadow(10.dp, shape).clip(shape)
                .background(Brush.verticalGradient(listOf(Color.White, Color(0xFFEBEBF0))))
                .drawWithContent {
                    drawContent()
                    val s = this.size.width * 0.27f
                    val path = Path().apply { moveTo(this@drawWithContent.size.width - s, 0f); lineTo(this@drawWithContent.size.width, s); lineTo(this@drawWithContent.size.width - s, s); close() }
                    drawPath(path, Color(0xFFD0D0D6))
                },
            contentAlignment = Alignment.Center,
        ) { Icon(icon, null, Modifier.size(size * 0.34f).offset(y = -size * 0.1f), tint = tint) }
        Text(
            label, Modifier.padding(bottom = size * 0.12f).clip(RoundedCornerShape(size * 0.06f)).background(tint)
                .padding(horizontal = size * 0.08f, vertical = size * 0.02f),
            color = Color.White, fontSize = (size.value * 0.13f).sp, fontWeight = FontWeight.Black, maxLines = 1,
        )
    }
}

@Composable
fun HeroHeader(badge: String, icon: ImageVector, tint: Color, headline: String, subline: String) {
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val rot by animateFloatAsState(if (shown) -6f else -16f, spring(0.6f, Spring.StiffnessLow), label = "r")
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        FormatBadge(badge, icon, tint, 84.dp, Modifier.rotate(rot).touchTilt(16.dp, tint, 14f))
        Spacer(Modifier.width(18.dp))
        Column(Modifier.weight(1f)) {
            Text(headline, fontSize = 24.sp, fontWeight = FontWeight.Bold, lineHeight = 30.sp)
            Spacer(Modifier.size(4.dp))
            Text(subline, fontSize = 14.sp, color = secondaryText, lineHeight = 20.sp)
        }
    }
}

@Composable
fun ActionTile(
    title: String, icon: ImageVector, tint: Color, modifier: Modifier = Modifier,
    selected: Boolean = false, enabled: Boolean = true, subtitle: String? = null, onClick: () -> Unit,
) {
    val view = LocalView.current
    Column(
        modifier.heightIn(min = 76.dp).alpha(if (enabled) 1f else 0.45f)
            .touchTilt(18.dp, if (selected) Color.White else tint, 9f)
            .glass(18.dp, tint, selected)
            .clickable(enabled = enabled, interactionSource = remember { MutableInteractionSource() }, indication = null) {
                Feedback.tap(view); safely(onClick)
            }
            .padding(horizontal = 6.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Box(
            Modifier.size(34.dp).clip(RoundedCornerShape(10.dp))
                .background(if (selected) Color.White.copy(alpha = 0.22f) else tint.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, null, Modifier.size(19.dp), tint = if (selected) Color.White else tint) }
        Spacer(Modifier.size(6.dp))
        Text(title, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis,
            color = if (selected) Color.White else MaterialTheme.colorScheme.onBackground, textAlign = TextAlign.Center)
        subtitle?.let {
            Text(it, fontSize = 10.sp, maxLines = 1, color = if (selected) Color.White.copy(alpha = 0.8f) else secondaryText)
        }
    }
}

data class Feature(val icon: ImageVector, val title: String, val caption: String)

@Composable
fun FeatureTile(f: Feature, tint: Color, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().touchTilt(18.dp, tint, 5f).glass(18.dp).padding(14.dp), verticalAlignment = Alignment.Top) {
        IconSquare(f.icon, tint, 38.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(f.title, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
            Text(f.caption, fontSize = 12.sp, color = secondaryText, lineHeight = 17.sp)
        }
    }
}

@Composable
fun FeatureGrid(features: List<Feature>, tint: Color, columns: Int = 2) {
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        features.chunked(columns).forEachIndexed { ri, row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEachIndexed { ci, f ->
                    val i = ri * columns + ci
                    AnimatedVisibility(shown, Modifier.weight(1f),
                        enter = fadeIn(tween(350, 60 * i)) + slideInVertically(tween(350, 60 * i, FastOutSlowInEasing)) { it / 3 }) {
                        FeatureTile(f, tint)
                    }
                }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** صف مربعات بعرض متساوٍ. */
@Composable
fun TileRow(content: @Composable (Modifier) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) { content(Modifier.weight(1f)) }
}

@Composable
fun ArabicEditor(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, minHeight: Dp = 180.dp, readOnly: Boolean = false) {
    val color = MaterialTheme.colorScheme.onBackground
    Box(modifier.fillMaxWidth().heightIn(min = minHeight)) {
        if (value.isEmpty()) Text(placeholder, color = tertiaryText, fontSize = 16.sp, lineHeight = 26.sp)
        BasicTextField(
            value, onChange, Modifier.fillMaxWidth().heightIn(min = minHeight), readOnly = readOnly,
            textStyle = TextStyle(color = color, fontSize = 16.sp, lineHeight = 26.sp, textDirection = TextDirection.Content),
            cursorBrush = SolidColor(AW.Blue),
        )
    }
}

@Composable
fun PrimaryButton(text: String, icon: ImageVector, tint: Color, enabled: Boolean, working: Boolean = false, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val view = LocalView.current
    val pulse by rememberInfiniteTransition(label = "p").animateFloat(1f, 1.04f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "s")
    Row(
        modifier.heightIn(min = 54.dp).scale(if (working) pulse else 1f).alpha(if (enabled || working) 1f else 0.45f)
            .touchTilt(28.dp, Color.White, 6f)
            .shadow(12.dp, RoundedCornerShape(28.dp), spotColor = tint)
            .clip(RoundedCornerShape(28.dp))
            .background(Brush.verticalGradient(listOf(tint, tint.copy(alpha = 0.82f))))
            .border(1.dp, Color.White.copy(alpha = 0.4f), RoundedCornerShape(28.dp))
            .clickable(enabled = enabled && !working) { Feedback.tap(view); safely(onClick) }
            .padding(horizontal = 26.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
    ) {
        if (working) androidx.compose.material3.CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
        else Icon(icon, null, Modifier.size(20.dp), tint = Color.White)
        Spacer(Modifier.width(10.dp))
        Text(text, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
    }
}

@Composable
fun Notice(text: String, tint: Color = AW.Orange, icon: ImageVector = Icons.Rounded.Warning) {
    Row(Modifier.fillMaxWidth().glass(16.dp, tint).padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(10.dp))
        Text(text, fontSize = 14.sp)
    }
}

// ---------- التقرير ----------

@Composable
fun StatTile(value: String, label: String, color: Color, modifier: Modifier = Modifier) {
    Column(modifier.glass(16.dp).padding(vertical = 10.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = color)
        Text(label, fontSize = 11.sp, color = secondaryText)
    }
}

@Composable
fun IssueRow(i: LintIssue) {
    val c = if (i.level == IssueLevel.ERROR) AW.Pink else AW.Orange
    Row(Modifier.fillMaxWidth().padding(vertical = 5.dp)) {
        Icon(if (i.level == IssueLevel.ERROR) Icons.Rounded.Cancel else Icons.Rounded.Warning, null, Modifier.size(16.dp).offset(y = 2.dp), tint = c)
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(i.kind, fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clip(CircleShape).background(c.copy(alpha = 0.15f)).padding(horizontal = 8.dp, vertical = 2.dp))
                i.line?.let { Text("  سطر $it", fontSize = 11.sp, color = secondaryText) }
            }
            Text(i.message, fontSize = 14.sp)
            i.excerpt?.let { Text(it, fontSize = 12.sp, color = secondaryText, maxLines = 2) }
        }
    }
}

@Composable
fun ReportView(r: LintReport) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        TileRow { m ->
            StatTile("${r.stats.words}", "كلمة", MaterialTheme.colorScheme.onBackground, m)
            StatTile("${r.stats.sentences}", "جملة", MaterialTheme.colorScheme.onBackground, m)
            StatTile("${r.errors.size}", "خطأ", if (r.errors.isEmpty()) AW.Green else AW.Pink, m)
            StatTile("${r.warnings.size}", "تنبيه", if (r.warnings.isEmpty()) AW.Green else AW.Orange, m)
        }
        if (r.issues.isEmpty()) Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Verified, null, tint = AW.Green)
            Spacer(Modifier.width(6.dp))
            Text("نظيف وجاهز للنشر", color = AW.Green, fontWeight = FontWeight.SemiBold)
        } else (r.errors + r.warnings).forEach { IssueRow(it) }
    }
}

@Composable
fun LiveText(text: String, tint: Color) {
    val blink by rememberInfiniteTransition(label = "c").animateFloat(1f, 0.1f, infiniteRepeatable(tween(500), RepeatMode.Reverse), label = "b")
    Column {
        Text("يكتب الحين…", color = tint, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.alpha(0.5f + blink / 2))
        Spacer(Modifier.size(6.dp))
        Text(text + " ▍", fontSize = 16.sp, lineHeight = 26.sp, style = TextStyle(textDirection = TextDirection.Content))
    }
}

// ---------- الرسائل ----------

data class Toast(val text: String, val isError: Boolean = false, val stamp: Long = System.nanoTime())

object Toasts {
    var current by mutableStateOf<Toast?>(null)
    fun show(text: String, error: Boolean = false) { current = Toast(text, error) }
}

@Composable
fun BoxScope.ToastHost() {
    val view = LocalView.current
    val t = Toasts.current
    LaunchedEffect(t?.stamp) {
        if (t != null) {
            if (t.isError) Feedback.error(view) else Feedback.success(view)
            delay(if (t.isError) 5000 else 3000)
            if (Toasts.current?.stamp == t.stamp) Toasts.current = null
        }
    }
    AnimatedVisibility(t != null, Modifier.align(Alignment.BottomCenter).padding(bottom = 28.dp, start = 16.dp, end = 16.dp),
        enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()) {
        val shown = t ?: return@AnimatedVisibility
        val c = if (shown.isError) AW.Pink else AW.Green
        Row(Modifier.glass(30.dp, c).padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(if (shown.isError) Icons.Rounded.Error else Icons.Rounded.CheckCircle, null, tint = c, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(shown.text, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        }
    }
}

/** صفحة قسم قابلة للتمرير بحواف مريحة. */
@Composable
fun SectionScroll(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 120.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp), content = content,
    )
}

