package app.arabwriter.android.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Calculate
import androidx.compose.material.icons.rounded.CallMerge
import androidx.compose.material.icons.rounded.CallSplit
import androidx.compose.material.icons.rounded.CleaningServices
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Collections
import androidx.compose.material.icons.rounded.Compress
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.DocumentScanner
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.FileCopy
import androidx.compose.material.icons.rounded.FileDownload
import androidx.compose.material.icons.rounded.FindReplace
import androidx.compose.material.icons.rounded.FormatTextdirectionRToL
import androidx.compose.material.icons.rounded.Functions
import androidx.compose.material.icons.rounded.Healing
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Notes
import androidx.compose.material.icons.rounded.PictureAsPdf
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.RemoveCircleOutline
import androidx.compose.material.icons.rounded.Save
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Spellcheck
import androidx.compose.material.icons.rounded.SwapVert
import androidx.compose.material.icons.rounded.TableChart
import androidx.compose.material.icons.rounded.Tag
import androidx.compose.material.icons.rounded.TextSnippet
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material.icons.rounded.Summarize
import androidx.compose.material.icons.rounded.WaterDrop
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.arabwriter.android.core.ArabicLinter
import app.arabwriter.android.core.LintOptions
import app.arabwriter.android.core.LintReport
import app.arabwriter.android.service.AppSettings
import app.arabwriter.android.service.ArabicPdfWriter
import app.arabwriter.android.service.DocxDocument
import app.arabwriter.android.service.Files
import app.arabwriter.android.service.NumberStyle
import app.arabwriter.android.service.PdfTools
import app.arabwriter.android.service.Platform
import app.arabwriter.android.service.Register
import app.arabwriter.android.service.Sheet
import app.arabwriter.android.service.SheetIO
import app.arabwriter.android.service.WriteMode
import app.arabwriter.android.service.WriteRequest
import app.arabwriter.android.service.WritingEngine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ---------- واجهة البداية ----------

@Composable
fun FileHero(format: String, icon: ImageVector, tint: Color, headline: String, features: List<Feature>, dropTitle: String, dropSubtitle: String, onPick: () -> Unit) {
    HeroHeader(format, icon, tint, headline, "اختر الملف، وكل شيء يصير على جوالك.")
    FeatureGrid(features, tint)
    PickZone(dropTitle, dropSubtitle, tint, onPick)
}

@Composable
fun PickZone(title: String, subtitle: String, tint: Color, onPick: () -> Unit) {
    val view = androidx.compose.ui.platform.LocalView.current
    Column(
        Modifier.fillMaxWidth().heightIn(min = 170.dp).touchTilt(28.dp, tint, 3f).glass(28.dp, tint)
            .border(BorderStroke(1.5.dp, tint.copy(alpha = 0.35f)), RoundedCornerShape(28.dp))
            .clickable { Feedback.tap(view); onPick() }.padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Icon(Icons.Rounded.FileDownload, null, Modifier.size(42.dp), tint = tint)
        Spacer(Modifier.height(10.dp))
        Text(title, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
        Text(subtitle, fontSize = 13.sp, color = secondaryText)
    }
}

@Composable
fun FileBar(format: String, icon: ImageVector, tint: Color, name: String, detail: String, onClose: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        FormatBadge(format, icon, tint, 54.dp, Modifier.touchTilt(10.dp, tint, 14f))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(name, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, maxLines = 1)
            Text(detail, fontSize = 12.sp, color = secondaryText)
        }
        SmallIcon(Icons.Rounded.Close, "إغلاق", onClose)
    }
}

// ---------- وورد ----------

@Composable
fun WordScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val saver = rememberSaver()
    val tint = AW.Indigo
    var name by remember { mutableStateOf<String?>(null) }
    var doc by remember { mutableStateOf<DocxDocument?>(null) }
    var plain by remember { mutableStateOf<String?>(null) }
    var preview by remember { mutableStateOf("") }
    var report by remember { mutableStateOf<LintReport?>(null) }
    var find by remember { mutableStateOf("") }
    var repl by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }

    fun refresh() {
        preview = doc?.text ?: plain ?: ""
        report = ArabicLinter.check(preview, LintOptions(englishOnOwnLine = false))
    }

    val open = rememberOpener { uris ->
        val u = uris.first()
        runCatching {
            val b = Files.read(ctx, u)
            if (Files.ext(ctx, u) == "docx") { doc = DocxDocument.open(b); plain = null } else { plain = String(b, Charsets.UTF_8); doc = null }
            name = Files.name(ctx, u); refresh()
        }.onFailure { Toasts.show(it.message ?: "تعذّر فتح الملف", true) }
    }

    SectionScroll {
        val n = name
        if (n == null) FileHero("DOCX", Icons.Rounded.Description, tint, "دقّق ملف وورد بدون ما يخرب تنسيقه", listOf(
            Feature(Icons.Rounded.Verified, "تدقيق آمن", "إملاء وترقيم ومسافات، والخطوط والألوان باقية"),
            Feature(Icons.Rounded.AutoAwesome, "صياغة ذكية", "يمسح بصمات الذكاء الاصطناعي من المستند كله"),
            Feature(Icons.Rounded.FindReplace, "بحث واستبدال", "يغيّر كلمة في كل المستند بضغطة"),
            Feature(Icons.Rounded.FormatTextdirectionRToL, "اتجاه عربي", "يقلب الفقرات المعكوسة لليمين"),
            Feature(Icons.Rounded.PictureAsPdf, "تحويل إلى PDF", "بخط أميري وترتيب عربي صحيح"),
            Feature(Icons.Rounded.Notes, "تقرير الفحص", "عدد الأخطاء والتنبيهات وموضع كل واحد"),
        ), "اختر ملف وورد", "docx · txt") { open(arrayOf(Mime.DOCX, Mime.TXT, "text/*")) }
        else {
            FileBar("DOCX", Icons.Rounded.Description, tint, n, "${ArabicLinter.words(preview).size} كلمة · ${preview.split('\n').count { it.isNotBlank() }} فقرة") {
                name = null; doc = null; plain = null; report = null
            }
            TileRow { m ->
                ActionTile("تدقيق آمن", Icons.Rounded.Verified, AW.Green, m) {
                    val c = doc?.safeFix() ?: plain?.let { val (t, k) = ArabicLinter.fixInline(it); plain = t; k } ?: 0
                    refresh(); Toasts.show(if (c == 0) "ما فيه أخطاء آمنة للإصلاح" else "أُصلح $c موضع والتنسيق باقٍ")
                }
                ActionTile(if (working) "يصيغ…" else "صياغة ذكية", Icons.Rounded.AutoAwesome, AW.Purple, m, enabled = AppSettings.hasKey && !working) {
                    working = true
                    scope.launch {
                        try {
                            val r = WritingEngine.run(WriteRequest(preview, WriteMode.REWRITE, Register.KEEP, Platform.NONE, null))
                            doc = DocxDocument.open(DocxDocument.build(r.text)); plain = null; refresh()
                            Toasts.show("أعيدت الصياغة. احفظ بنسخة جديدة حتى يبقى الأصل")
                        } catch (e: Exception) { Toasts.show(e.message ?: "تعذّرت الصياغة", true) }
                        working = false
                    }
                }
                ActionTile("اتجاه عربي", Icons.Rounded.FormatTextdirectionRToL, AW.Blue, m, enabled = doc != null) {
                    doc?.forceRTL(); Toasts.show("كل الفقرات صارت من اليمين")
                }
            }
            TileRow { m ->
                val base = n.substringBeforeLast('.') + " - مدقق"
                ActionTile("حفظ وورد", Icons.Rounded.Description, tint, m) {
                    saver.save("$base.docx", Mime.DOCX, doc?.bytes() ?: DocxDocument.build(preview))
                }
                ActionTile("حفظ PDF", Icons.Rounded.PictureAsPdf, AW.Pink, m) { saver.save("$base.pdf", Mime.PDF, ArabicPdfWriter.make(preview)) }
                ActionTile("حفظ نص", Icons.Rounded.TextSnippet, AW.Gray, m) { saver.save("$base.txt", Mime.TXT, preview.toByteArray()) }
            }
            GlassPanel {
                SectionLabel("بحث واستبدال", Icons.Rounded.Search); Spacer(Modifier.height(8.dp))
                InputLine(find, { find = it }, "ابحث عن"); Spacer(Modifier.height(8.dp))
                InputLine(repl, { repl = it }, "استبدل بـ"); Spacer(Modifier.height(10.dp))
                ActionTile("استبدل الكل", Icons.Rounded.FindReplace, tint, Modifier.fillMaxWidth(), enabled = find.isNotEmpty()) {
                    val c = doc?.replaceAll(find, repl) ?: plain?.let { val k = Regex(Regex.escape(find)).findAll(it).count(); plain = it.replace(find, repl); k } ?: 0
                    refresh(); Toasts.show(if (c == 0) "ما لقيت «$find»" else "استُبدل $c موضع", c == 0)
                }
            }
            GlassPanel {
                SectionLabel("المستند", Icons.Rounded.Notes); Spacer(Modifier.height(8.dp))
                Box(Modifier.fillMaxWidth().heightIn(max = 380.dp).clip(RoundedCornerShape(14.dp))
                    .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.6f)).verticalScroll(rememberScrollState()).padding(12.dp)) {
                    SelectableText(preview, 15)
                }
            }
            report?.let { GlassPanel(tint = if (it.isClean) AW.Green else AW.Pink) { SectionLabel("الفحص", Icons.Rounded.Verified); Spacer(Modifier.height(8.dp)); ReportView(it) } }
        }
    }
}

@Composable
fun InputLine(value: String, onChange: (String) -> Unit, hint: String, password: Boolean = false, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.onBackground.copy(alpha = 0.06f)).padding(12.dp)) {
        if (value.isEmpty()) Text(hint, color = tertiaryText)
        BasicTextField(value, onChange, Modifier.fillMaxWidth(), singleLine = true,
            visualTransformation = if (password) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
            textStyle = TextStyle(color = MaterialTheme.colorScheme.onBackground, fontSize = 15.sp), cursorBrush = SolidColor(AW.Blue))
    }
}

// ---------- إكسل ----------

@Composable
fun SheetScreen() {
    val ctx = LocalContext.current
    val saver = rememberSaver()
    val tint = AW.Excel
    var name by remember { mutableStateOf<String?>(null) }
    var sheets by remember { mutableStateOf<List<Sheet>>(emptyList()) }
    var current by remember { mutableIntStateOf(0) }
    var column by remember { mutableIntStateOf(0) }
    var header by remember { mutableStateOf(true) }
    var operand by remember { mutableStateOf("2") }
    var calc by remember { mutableStateOf<String?>(null) }
    var version by remember { mutableIntStateOf(0) }

    val open = rememberOpener { uris ->
        val u = uris.first()
        runCatching { sheets = SheetIO.open(Files.read(ctx, u), Files.ext(ctx, u), Files.base(ctx, u)); name = Files.name(ctx, u); current = 0; column = 0; calc = null }
            .onFailure { Toasts.show(it.message ?: "تعذّر فتح الملف", true) }
    }

    SectionScroll {
        val n = name
        if (n == null || sheets.isEmpty()) FileHero("XLSX", Icons.Rounded.TableChart, tint, "رتّب جدولك واحسبه في ثواني", listOf(
            Feature(Icons.Rounded.Edit, "تعديل الخلايا", "اكتب في أي خلية مباشرة، وأضف صفوفاً"),
            Feature(Icons.Rounded.SwapVert, "ترتيب", "تصاعدي وتنازلي، أرقام ونصوص عربية"),
            Feature(Icons.Rounded.Functions, "حسابات سريعة", "مجموع ومتوسط وأكبر وأصغر وعدد"),
            Feature(Icons.Rounded.Calculate, "ضرب وقسمة", "طبّق رقماً على عمود كامل دفعة وحدة"),
            Feature(Icons.Rounded.CleaningServices, "تنظيف", "مسافات زائدة وصفوف فارغة ومكررة"),
            Feature(Icons.Rounded.Spellcheck, "تدقيق عربي", "يصحح إملاء النصوص داخل العمود"),
        ), "اختر ملف إكسل", "xlsx · csv") { open(arrayOf(Mime.XLSX, Mime.CSV, "text/comma-separated-values", "text/*")) }
        else {
            val sheet = sheets[current.coerceIn(0, sheets.lastIndex)]
            val cols = sheet.columnCount
            val headers = (0 until cols).map { i -> (if (header) sheet.rows.firstOrNull()?.getOrNull(i) else null)?.takeIf { it.isNotBlank() } ?: SheetIO.colName(i) }
            val dataRange = (if (header) minOf(1, sheet.rows.size) else 0) until sheet.rows.size
            fun commit(f: (Sheet) -> Unit) { f(sheet); version++ }
            fun nums() = dataRange.mapNotNull { r -> sheet.rows[r].getOrNull(column)?.let(SheetIO::number) }

            FileBar("XLSX", Icons.Rounded.TableChart, tint, n, "${sheet.rows.size} صف · $cols عمود") { name = null; sheets = emptyList() }
            if (sheets.size > 1) TileChoice(sheets.indices.toList(), current, tint, { sheets[it].name }, { Icons.Rounded.TableChart }) { current = it; column = 0 }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("الصف الأول عناوين", Modifier.weight(1f)); Switch(header, { header = it })
            }

            // الجدول
            GlassPanel(radius = 22.dp) {
                androidx.compose.runtime.key(version) {
                    Column(Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState())) {
                        Row(Modifier.horizontalScroll(rememberScrollState())) {
                            Column {
                                Row {
                                    Spacer(Modifier.width(34.dp))
                                    (0 until cols).forEach { c ->
                                        Text(SheetIO.colName(c), Modifier.width(120.dp).clickable { column = c }.padding(4.dp),
                                            color = if (c == column) tint else secondaryText, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
                                    }
                                }
                                sheet.rows.take(400).forEachIndexed { r, row ->
                                    Row(Modifier.background(if (r == 0 && header) tint.copy(alpha = 0.12f) else Color.Transparent)) {
                                        Text("${r + 1}", Modifier.width(34.dp).padding(top = 8.dp), fontSize = 10.sp, color = secondaryText)
                                        (0 until cols).forEach { c ->
                                            var v by remember(r, c, version) { mutableStateOf(row.getOrElse(c) { "" }) }
                                            BasicTextField(v, { nv -> v = nv; while (row.size <= c) row.add(""); row[c] = nv },
                                                Modifier.width(120.dp).height(34.dp)
                                                    .background(if (c == column) tint.copy(alpha = 0.07f) else Color.Transparent)
                                                    .border(0.5.dp, MaterialTheme.colorScheme.onBackground.copy(alpha = 0.12f)).padding(6.dp),
                                                singleLine = true,
                                                textStyle = TextStyle(color = MaterialTheme.colorScheme.onBackground, fontSize = 13.sp,
                                                    fontWeight = if (r == 0 && header) FontWeight.SemiBold else FontWeight.Normal))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if (sheet.rows.size > 400) Text("يظهر أول 400 صف، والعمليات تشمل الكل", fontSize = 11.sp, color = secondaryText)
                Spacer(Modifier.height(8.dp))
                TileRow { m ->
                    ActionTile("صف جديد", Icons.Rounded.Add, tint, m) { commit { it.rows.add(MutableList(maxOf(cols, 1)) { "" }) } }
                    ActionTile("عمود جديد", Icons.Rounded.Add, AW.Teal, m) { commit { s -> if (s.rows.isEmpty()) s.rows.add(mutableListOf("")) else s.rows.forEach { it.add("") } } }
                }
            }

            GlassPanel {
                SectionLabel("العمود: ${headers.getOrElse(column) { "" }}"); Spacer(Modifier.height(8.dp))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    headers.forEachIndexed { i, h ->
                        Text(h, Modifier.clip(RoundedCornerShape(12.dp)).background(if (i == column) tint else tint.copy(alpha = 0.12f))
                            .clickable { column = i }.padding(horizontal = 12.dp, vertical = 6.dp),
                            color = if (i == column) Color.White else MaterialTheme.colorScheme.onBackground, fontSize = 13.sp, maxLines = 1)
                    }
                }
                Spacer(Modifier.height(10.dp))
                TileRow { m ->
                    ActionTile("تصاعدي", Icons.Rounded.ArrowUpward, AW.Blue, m) { commit { sortSheet(it, column, header, true) }; Toasts.show("رُتّب حسب «${headers[column]}»") }
                    ActionTile("تنازلي", Icons.Rounded.ArrowDownward, AW.Indigo, m) { commit { sortSheet(it, column, header, false) }; Toasts.show("رُتّب حسب «${headers[column]}»") }
                }
            }

            GlassPanel(tint = tint) {
                SectionLabel("احسب", Icons.Rounded.Functions); Spacer(Modifier.height(8.dp))
                fun agg(label: String, f: (List<Double>) -> Double) {
                    val ns = nums()
                    if (ns.isEmpty()) Toasts.show("العمود «${headers[column]}» ما فيه أرقام", true) else calc = "$label: ${SheetIO.fmt(f(ns))}"
                }
                TileRow { m ->
                    ActionTile("مجموع", Icons.Rounded.Functions, tint, m) { agg("المجموع") { it.sum() } }
                    ActionTile("متوسط", Icons.Rounded.Calculate, AW.Teal, m) { agg("المتوسط") { it.average() } }
                    ActionTile("عدد", Icons.Rounded.Tag, AW.Blue, m) { agg("العدد") { it.size.toDouble() } }
                }
                Spacer(Modifier.height(8.dp))
                TileRow { m ->
                    ActionTile("أكبر", Icons.Rounded.ArrowUpward, AW.Orange, m) { agg("الأكبر") { it.max() } }
                    ActionTile("أصغر", Icons.Rounded.ArrowDownward, AW.Purple, m) { agg("الأصغر") { it.min() } }
                }
                calc?.let {
                    Spacer(Modifier.height(10.dp))
                    Text(it, Modifier.fillMaxWidth().glass(14.dp, tint).padding(12.dp), fontSize = 20.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    InputLine(operand, { operand = it }, "الرقم", modifier = Modifier.width(80.dp))
                    listOf("×", "÷", "+", "−").forEach { op ->
                        ActionTile(op, Icons.Rounded.Calculate, tint, Modifier.weight(1f)) {
                            val k = SheetIO.number(operand) ?: return@ActionTile Toasts.show("اكتب رقماً صحيحاً", true)
                            var c = 0
                            commit { s -> for (r in dataRange) { val v = s.rows[r].getOrNull(column)?.let(SheetIO::number) ?: continue
                                s.rows[r][column] = SheetIO.fmt(when (op) { "×" -> v * k; "÷" -> if (k == 0.0) v else v / k; "+" -> v + k; else -> v - k }); c++ } }
                            Toasts.show("عُدّلت $c خلية في «${headers[column]}»")
                        }
                    }
                }
            }

            GlassPanel {
                SectionLabel("نظّف", Icons.Rounded.CleaningServices); Spacer(Modifier.height(8.dp))
                TileRow { m ->
                    ActionTile("المسافات", Icons.Rounded.CleaningServices, AW.Teal, m) {
                        var c = 0
                        commit { s -> s.rows.forEach { row -> row.indices.forEach { i -> val t = row[i].trim().replace(Regex("\\s+"), " "); if (t != row[i]) { row[i] = t; c++ } } } }
                        Toasts.show("نُظّفت $c خلية")
                    }
                    ActionTile("الفارغة", Icons.Rounded.RemoveCircleOutline, AW.Orange, m) {
                        val before = sheet.rows.size
                        commit { s -> s.rows.removeAll { row -> row.all { it.isBlank() } } }
                        Toasts.show("حُذف ${before - sheet.rows.size} صف فارغ")
                    }
                }
                Spacer(Modifier.height(8.dp))
                TileRow { m ->
                    ActionTile("المكرر", Icons.Rounded.FileCopy, AW.Pink, m) {
                        val before = sheet.rows.size
                        commit { s ->
                            val head = if (header && s.rows.isNotEmpty()) listOf(s.rows[0]) else emptyList()
                            val seen = HashSet<List<String>>()
                            val rest = s.rows.drop(head.size).filter { seen.add(it.toList()) }
                            s.rows = (head + rest).toMutableList()
                        }
                        Toasts.show("حُذف ${before - sheet.rows.size} صف مكرر")
                    }
                    ActionTile("تدقيق عربي", Icons.Rounded.Spellcheck, AW.Green, m) {
                        var c = 0
                        commit { s -> for (r in dataRange) { val v = s.rows[r].getOrNull(column) ?: continue
                            val f = ArabicLinter.fix(v, false); if (f != v && v.isNotEmpty()) { s.rows[r][column] = f; c++ } } }
                        Toasts.show("دُقّقت $c خلية")
                    }
                }
            }

            TileRow { m ->
                val base = n.substringBeforeLast('.') + " - مرتب"
                ActionTile("حفظ إكسل", Icons.Rounded.TableChart, tint, m) { saver.save("$base.xlsx", Mime.XLSX, SheetIO.xlsx(sheets)) }
                ActionTile("حفظ CSV", Icons.Rounded.TextSnippet, AW.Gray, m) { saver.save("$base.csv", Mime.CSV, SheetIO.csv(sheet)) }
            }
        }
    }
}

private fun sortSheet(s: Sheet, c: Int, header: Boolean, asc: Boolean) {
    val head = if (header && s.rows.isNotEmpty()) listOf(s.rows[0]) else emptyList()
    val rest = s.rows.drop(head.size).sortedWith { a, b ->
        val x = a.getOrElse(c) { "" }; val y = b.getOrElse(c) { "" }
        val nx = SheetIO.number(x); val ny = SheetIO.number(y)
        val o = if (nx != null && ny != null) nx.compareTo(ny) else java.text.Collator.getInstance(java.util.Locale("ar")).compare(x, y)
        if (asc) o else -o
    }
    s.rows = (head + rest).toMutableList()
}

// ---------- PDF ----------

enum class PdfTool(val title: String, val icon: ImageVector, val tint: Color, val help: String) {
    MERGE("دمج", Icons.Rounded.CallMerge, AW.Blue, "يدمج الملفات بالترتيب الظاهر في القائمة."),
    SPLIT("تقسيم", Icons.Rounded.CallSplit, AW.Teal, "يحفظ كل صفحة كملف مستقل في مجلد تختاره."),
    EXTRACT("استخراج", Icons.Rounded.FileCopy, AW.Indigo, "يحفظ الصفحات المحددة في ملف جديد."),
    DELETE("حذف صفحات", Icons.Rounded.Delete, AW.Pink, "يحذف الصفحات المحددة ويحفظ نسخة جديدة."),
    REORDER("ترتيب", Icons.Rounded.SwapVert, AW.Orange, "اكتب الترتيب الجديد للصفحات كلها."),
    WATERMARK("علامة مائية", Icons.Rounded.WaterDrop, AW.Teal, "يكتب نصاً عربياً شفافاً بالمائل على كل صفحة."),
    NUMBER("ترقيم", Icons.Rounded.Tag, AW.Blue, "يضيف رقم الصفحة أسفل كل صفحة."),
    PROTECT("حماية", Icons.Rounded.Lock, Color(0xFFF2B31A), "يقفل الملف بكلمة مرور عند الفتح."),
    COMPRESS("ضغط", Icons.Rounded.Compress, AW.Green, "ضغط قوي: يعيد رسم الصفحات صوراً بحجم أصغر."),
    TO_IMAGES("إلى صور", Icons.Rounded.Image, AW.Purple, "يحفظ كل صفحة صورة PNG بدقة عالية."),
    FROM_IMAGES("صور إلى PDF", Icons.Rounded.Collections, AW.Pink, "يجمع الصور في ملف PDF واحد بالترتيب."),
    TEXT("استخراج النص", Icons.Rounded.TextSnippet, AW.Gray, "يطلع النص من الملف. لو كان ممسوحاً يقرؤه ضوئياً بالمفتاح."),
    OCR("قراءة ضوئية", Icons.Rounded.DocumentScanner, AW.Teal, "يقرأ النص العربي والإنجليزي من الصور والملفات الممسوحة بدقة عالية. يحتاج المفتاح."),
    SUMMARIZE("تلخيص ذكي", Icons.Rounded.Summarize, AW.Purple, "يلخّص الملف بالعربية ويخرج PDF عربي مرتب، مع شعارك إن أضفته.");

    val images get() = this == FROM_IMAGES || this == OCR
}

private data class PickedFile(val uri: Uri, val name: String, val bytes: ByteArray, val isPdf: Boolean, val pages: Int)

@Composable
fun PdfScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val saver = rememberSaver()
    val tint = AW.Pink
    var tool by remember { mutableStateOf(PdfTool.MERGE) }
    val files = remember { mutableStateListOf<PickedFile>() }
    var active by remember { mutableIntStateOf(0) }
    var thumb by remember { mutableStateOf<Bitmap?>(null) }
    var pages by remember { mutableStateOf("") }
    var stamp by remember { mutableStateOf("سري") }
    var password by remember { mutableStateOf("") }
    var numberStyle by remember { mutableStateOf(NumberStyle.ARABIC) }
    var summaryWords by remember { mutableIntStateOf(250) }
    var logo by remember { mutableStateOf<Bitmap?>(null) }
    var output by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf<String?>(null) }

    fun select(i: Int) {
        active = i
        val f = files.getOrNull(i) ?: run { thumb = null; return }
        thumb = if (f.isPdf) PdfTools.thumbnail(f.bytes) else BitmapFactory.decodeByteArray(f.bytes, 0, f.bytes.size)
    }

    val open = rememberOpener { uris ->
        uris.forEach { u ->
            runCatching {
                val b = Files.read(ctx, u); val isPdf = Files.ext(ctx, u) == "pdf" || ctx.contentResolver.getType(u) == Mime.PDF
                files.add(PickedFile(u, Files.name(ctx, u), b, isPdf, if (isPdf) PdfTools.pageCount(b) else 1))
            }.onFailure { Toasts.show(it.message ?: "تعذّر فتح الملف", true) }
        }
        if (thumb == null) select(0)
    }
    val pickLogo = rememberOpener { u -> runCatching { val b = Files.read(ctx, u.first()); logo = BitmapFactory.decodeByteArray(b, 0, b.size) } }

    fun src(): PickedFile? = files.getOrNull(active)?.takeIf { it.isPdf } ?: files.firstOrNull { it.isPdf }
    fun base(s: String) = ((files.getOrNull(active) ?: files.firstOrNull())?.name?.substringBeforeLast('.') ?: "ملف") + " - " + s

    suspend fun ocrOf(f: PickedFile): String {
        if (!AppSettings.hasKey) throw IllegalStateException("القراءة الضوئية تحتاج مفتاح Claude.")
        progress = "يجهّز الصفحات…"
        val bmps = if (f.isPdf) PdfTools.renderPages(f.bytes, 1.6f, 40) else listOfNotNull(BitmapFactory.decodeByteArray(f.bytes, 0, f.bytes.size))
        return WritingEngine.ocr(bmps) { d, t -> progress = "يقرأ الصفحة $d من $t…" }.also { progress = null }
    }

    fun run() {
        val pdfs = files.filter { it.isPdf }
        val s = src()
        if (!tool.images && s == null) { Toasts.show("أضف ملف PDF أولاً.", true); return }
        working = true; output = ""
        scope.launch {
            try {
                when (tool) {
                    PdfTool.MERGE -> saver.save(base("مدمج") + ".pdf", Mime.PDF, PdfTools.merge(pdfs.map { it.bytes }))
                    PdfTool.SPLIT -> {
                        val parts = PdfTools.split(s!!.bytes)
                        saver.saveMany(parts.mapIndexed { i, b -> Triple(base("صفحة ${i + 1}") + ".pdf", Mime.PDF, b) })
                    }
                    PdfTool.EXTRACT -> saver.save(base("مستخرج") + ".pdf", Mime.PDF, PdfTools.pick(s!!.bytes, PdfTools.parsePages(pages, s.pages)))
                    PdfTool.DELETE -> saver.save(base("بعد الحذف") + ".pdf", Mime.PDF, PdfTools.delete(s!!.bytes, PdfTools.parsePages(pages, s.pages)))
                    PdfTool.REORDER -> {
                        val order = PdfTools.parsePages(pages, s!!.pages)
                        if (order.toSet().size != s.pages) throw IllegalStateException("اكتب كل الصفحات (${s.pages}) مرة واحدة بالترتيب الجديد.")
                        saver.save(base("مرتب") + ".pdf", Mime.PDF, PdfTools.pick(s.bytes, order))
                    }
                    PdfTool.WATERMARK -> saver.save(base("علامة مائية") + ".pdf", Mime.PDF, PdfTools.watermark(s!!.bytes, stamp))
                    PdfTool.NUMBER -> saver.save(base("مرقم") + ".pdf", Mime.PDF, PdfTools.number(s!!.bytes, numberStyle))
                    PdfTool.PROTECT -> saver.save(base("محمي") + ".pdf", Mime.PDF, PdfTools.protect(s!!.bytes, password))
                    PdfTool.COMPRESS -> {
                        val out = PdfTools.compress(s!!.bytes)
                        Toasts.show("الحجم ${s.bytes.size / 1024} ← ${out.size / 1024} كيلوبايت")
                        saver.save(base("مضغوط") + ".pdf", Mime.PDF, out)
                    }
                    PdfTool.TO_IMAGES -> {
                        val imgs = PdfTools.pngs(PdfTools.renderPages(s!!.bytes, 2f))
                        saver.saveMany(imgs.mapIndexed { i, b -> Triple(base("${i + 1}") + ".png", Mime.PNG, b) })
                    }
                    PdfTool.FROM_IMAGES -> {
                        val imgs = files.filter { !it.isPdf }
                        if (imgs.isEmpty()) throw IllegalStateException("أضف صوراً أولاً.")
                        saver.save(base("صور") + ".pdf", Mime.PDF, PdfTools.fromImages(imgs.map { it.bytes }))
                    }
                    PdfTool.TEXT -> {
                        val t = PdfTools.text(s!!.bytes)
                        output = if (t.isBlank()) { if (AppSettings.hasKey) ocrOf(s) else "ما فيه نص قابل للنسخ. الملف غالباً صور ممسوحة، والقراءة الضوئية تحتاج المفتاح." } else t
                    }
                    PdfTool.OCR -> {
                        val f = files.getOrNull(active) ?: files.first()
                        output = ocrOf(f)
                        Toasts.show("قُرئ ${ArabicLinter.words(output).size} كلمة")
                    }
                    PdfTool.SUMMARIZE -> {
                        var t = PdfTools.text(s!!.bytes)
                        if (t.isBlank()) t = ocrOf(s)
                        if (t.isBlank()) throw IllegalStateException("ما فيه نص في الملف ألخّصه.")
                        progress = "يلخّص…"
                        val sum = WritingEngine.summarize(t, summaryWords)
                        output = sum
                        val lines = sum.split('\n')
                        val pdf = withContext(Dispatchers.Default) { ArabicPdfWriter.make(lines.drop(1).joinToString("\n").trim(), lines.firstOrNull(), logo) }
                        saver.save(base("ملخص") + ".pdf", Mime.PDF, pdf)
                    }
                }
            } catch (e: Exception) { Toasts.show(e.message ?: "تعذّر التنفيذ", true) }
            working = false; progress = null
        }
    }

    SectionScroll {
        HeroHeader("PDF", Icons.Rounded.PictureAsPdf, tint, "كل أدوات الـ PDF في مكان واحد", "اختر الأداة، أضف الملف، واضغط نفّذ.")
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            PdfTool.entries.chunked(4).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { t -> ActionTile(t.title, t.icon, t.tint, Modifier.weight(1f), selected = tool == t) { tool = t; output = "" } }
                    repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }

        GlassPanel(tint = tool.tint) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconSquare(tool.icon, tool.tint, 40.dp); Spacer(Modifier.width(10.dp))
                Text(tool.title, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.height(6.dp))
            Text(tool.help, fontSize = 14.sp, color = secondaryText)
            Spacer(Modifier.height(10.dp))
            when (tool) {
                PdfTool.EXTRACT, PdfTool.DELETE, PdfTool.REORDER -> InputLine(pages, { pages = it }, if (tool == PdfTool.REORDER) "مثال: 3، 1، 2" else "مثال: 1-3، 5")
                PdfTool.WATERMARK -> InputLine(stamp, { stamp = it }, "نص العلامة")
                PdfTool.NUMBER -> TileChoice(NumberStyle.entries, numberStyle, tool.tint, { it.label }, { Icons.Rounded.Tag }) { numberStyle = it }
                PdfTool.PROTECT -> InputLine(password, { password = it }, "كلمة المرور", password = true)
                PdfTool.SUMMARIZE -> {
                    Row(Modifier.glass(26.dp).padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("−", fontSize = 22.sp, modifier = Modifier.clickable { summaryWords = maxOf(80, summaryWords - 50) }.padding(horizontal = 10.dp))
                        Text("$summaryWords كلمة", fontWeight = FontWeight.SemiBold)
                        Text("+", fontSize = 22.sp, modifier = Modifier.clickable { summaryWords = minOf(1200, summaryWords + 50) }.padding(horizontal = 10.dp))
                    }
                    Spacer(Modifier.height(8.dp))
                    TileRow { m ->
                        ActionTile(if (logo == null) "إضافة شعار" else "تغيير الشعار", Icons.Rounded.Image, AW.Blue, m) { pickLogo(arrayOf("image/*")) }
                        if (logo != null) ActionTile("حذف الشعار", Icons.Rounded.Close, AW.Pink, m) { logo = null }
                    }
                    if (!AppSettings.hasKey) { Spacer(Modifier.height(6.dp)); Text("يحتاج مفتاح Claude", color = AW.Orange, fontSize = 12.sp) }
                }
                PdfTool.OCR -> if (!AppSettings.hasKey) Text("يحتاج مفتاح Claude", color = AW.Orange, fontSize = 12.sp)
                else -> {}
            }
            progress?.let { Spacer(Modifier.height(8.dp)); Text(it, color = secondaryText, fontSize = 13.sp) }
            Spacer(Modifier.height(10.dp))
            PrimaryButton(if (working) "يشتغل…" else "نفّذ", Icons.Rounded.PlayArrow, tool.tint,
                files.isNotEmpty() && !(tool == PdfTool.SUMMARIZE && !AppSettings.hasKey), working, Modifier.fillMaxWidth()) { run() }
        }

        if (files.isEmpty()) PickZone(if (tool.images) "اختر صوراً أو PDF" else "اختر ملفات PDF", "ملف واحد أو أكثر", tint) {
            open(if (tool.images) arrayOf("image/*", Mime.PDF) else arrayOf(Mime.PDF))
        } else {
            GlassPanel {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    SectionLabel("الملفات (${files.size})"); Spacer(Modifier.weight(1f))
                    SmallIcon(Icons.Rounded.Add, "إضافة") { open(if (tool.images) arrayOf("image/*", Mime.PDF) else arrayOf(Mime.PDF)) }
                    SmallIcon(Icons.Rounded.Close, "مسح") { files.clear(); thumb = null; output = "" }
                }
                files.forEachIndexed { i, f ->
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                        .background(if (i == active) tint.copy(alpha = 0.12f) else Color.Transparent)
                        .clickable { select(i) }.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (f.isPdf) Icons.Rounded.PictureAsPdf else Icons.Rounded.Image, null, tint = tint, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(8.dp))
                        Column(Modifier.weight(1f)) {
                            Text(f.name, maxLines = 1, fontSize = 14.sp)
                            if (f.isPdf) Text("${f.pages} صفحة", fontSize = 11.sp, color = secondaryText)
                        }
                        SmallIcon(Icons.Rounded.KeyboardArrowUp, "فوق") { if (i > 0) { val x = files.removeAt(i); files.add(i - 1, x) } }
                        SmallIcon(Icons.Rounded.KeyboardArrowDown, "تحت") { if (i < files.lastIndex) { val x = files.removeAt(i); files.add(i + 1, x) } }
                        SmallIcon(Icons.Rounded.RemoveCircleOutline, "حذف") { files.removeAt(i); select(0) }
                    }
                }
            }
            thumb?.let { b ->
                GlassPanel(radius = 22.dp) {
                    Image(b.asImageBitmap(), null, Modifier.fillMaxWidth().heightIn(max = 420.dp).clip(RoundedCornerShape(12.dp)), contentScale = ContentScale.Fit)
                }
            }
        }

        if (output.isNotEmpty()) GlassPanel {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionLabel("الناتج", Icons.Rounded.Notes); Spacer(Modifier.weight(1f))
                SmallIcon(Icons.Rounded.ContentCopy, "نسخ") { copyText(ctx, output); Toasts.show("نُسخ") }
                SmallIcon(Icons.Rounded.Save, "حفظ") { saver.save(base("نص") + ".txt", Mime.TXT, output.toByteArray()) }
            }
            SelectableText(output, 15)
        }
    }
}
