package app.arabwriter.android.service

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.multipdf.PDFMergerUtility
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.common.PDRectangle
import com.tom_roush.pdfbox.pdmodel.encryption.AccessPermission
import com.tom_roush.pdfbox.pdmodel.encryption.StandardProtectionPolicy
import com.tom_roush.pdfbox.pdmodel.graphics.image.JPEGFactory
import com.tom_roush.pdfbox.pdmodel.graphics.image.LosslessFactory
import com.tom_roush.pdfbox.pdmodel.graphics.state.PDExtendedGraphicsState
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.util.Matrix
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.Normalizer
import java.text.NumberFormat
import java.util.Locale

enum class NumberStyle(val label: String) { ARABIC("١ ٢ ٣"), LATIN("1 2 3"), OF_TOTAL("١ من ١٠") }

object PdfTools {
    private var ready = false
    private lateinit var appCtx: Context

    fun init(ctx: Context) {
        appCtx = ctx.applicationContext
        if (!ready) { PDFBoxResourceLoader.init(appCtx); ready = true }
    }

    val amiri: Typeface by lazy { runCatching { Typeface.createFromAsset(appCtx.assets, "fonts/Amiri-Regular.ttf") }.getOrDefault(Typeface.DEFAULT) }
    val amiriBold: Typeface by lazy { runCatching { Typeface.createFromAsset(appCtx.assets, "fonts/Amiri-Bold.ttf") }.getOrDefault(Typeface.DEFAULT_BOLD) }

    private fun load(bytes: ByteArray): PDDocument = try {
        PDDocument.load(bytes)
    } catch (e: Exception) {
        throw ToolException(if (e.javaClass.simpleName.contains("Password")) "الملف محمي بكلمة مرور." else "تعذّر فتح ملف PDF.")
    }

    private fun save(doc: PDDocument): ByteArray = ByteArrayOutputStream().also { doc.save(it) }.toByteArray()

    fun pageCount(bytes: ByteArray): Int = runCatching { load(bytes).use { it.numberOfPages } }.getOrDefault(0)

    suspend fun merge(files: List<ByteArray>): ByteArray = withContext(Dispatchers.IO) {
        if (files.size < 2) throw ToolException("الدمج يحتاج ملفين أو أكثر.")
        val out = ByteArrayOutputStream()
        PDFMergerUtility().apply {
            files.forEach { addSource(ByteArrayInputStream(it)) }
            destinationStream = out
            mergeDocuments(MemoryUsageSetting.setupMainMemoryOnly())
        }
        out.toByteArray()
    }

    /** يحوّل «1-3، 5، 8-» إلى أرقام صفحات من الصفر. */
    fun parsePages(spec: String, count: Int): List<Int> {
        val s = spec.map { if (it in '٠'..'٩') '0' + (it - '٠') else it }.joinToString("")
            .replace('،', ',').replace(" ", "")
        val out = ArrayList<Int>()
        for (part in s.split(',').filter { it.isNotEmpty() }) {
            val bits = part.split('-')
            when {
                bits.size == 1 && bits[0].toIntOrNull() != null -> out.add(bits[0].toInt())
                bits.size == 2 -> {
                    val a = bits[0].toIntOrNull() ?: 1
                    val b = if (bits[1].isEmpty()) count else bits[1].toIntOrNull() ?: count
                    if (a > b) throw ToolException("النطاق «$part» غير صحيح.")
                    out.addAll(a..b)
                }
                else -> throw ToolException("لم أفهم «$part». اكتب مثل: 1-3، 5")
            }
        }
        if (out.isEmpty()) throw ToolException("اكتب أرقام الصفحات.")
        out.firstOrNull { it < 1 || it > count }?.let { throw ToolException("الصفحة $it غير موجودة. الملف فيه $count صفحة.") }
        return out.map { it - 1 }
    }

    suspend fun pick(bytes: ByteArray, pages: List<Int>): ByteArray = withContext(Dispatchers.IO) {
        load(bytes).use { src ->
            PDDocument().use { out ->
                pages.forEach { out.importPage(src.getPage(it)) }
                save(out)
            }
        }
    }

    suspend fun delete(bytes: ByteArray, pages: List<Int>): ByteArray = withContext(Dispatchers.IO) {
        load(bytes).use { d ->
            pages.toSortedSet().reversed().forEach { d.removePage(it) }
            if (d.numberOfPages == 0) throw ToolException("ما ينفع تحذف كل الصفحات.")
            save(d)
        }
    }

    suspend fun split(bytes: ByteArray): List<ByteArray> = withContext(Dispatchers.IO) {
        val n = load(bytes).use { it.numberOfPages }
        (0 until n).map { pick(bytes, listOf(it)) }
    }

    /** يرسم نصاً عربياً بمحرك أندرويد (تشكيل صحيح للحروف) في صورة شفافة. */
    private fun textBitmap(text: String, sizePx: Float, color: Int, bold: Boolean): Bitmap {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = sizePx; this.color = color; typeface = if (bold) amiriBold else amiri }
        val w = maxOf(1, paint.measureText(text).toInt() + 8)
        val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, w)
            .setAlignment(Layout.Alignment.ALIGN_CENTER).setTextDirection(TextDirectionHeuristics.RTL).build()
        val bmp = Bitmap.createBitmap(w, maxOf(1, layout.height), Bitmap.Config.ARGB_8888)
        layout.draw(Canvas(bmp))
        return bmp
    }

    suspend fun watermark(bytes: ByteArray, text: String): ByteArray = withContext(Dispatchers.IO) {
        if (text.isBlank()) throw ToolException("اكتب نص العلامة.")
        val bmp = textBitmap(text, 180f, Color.argb(255, 40, 40, 40), true)
        load(bytes).use { d ->
            val img = LosslessFactory.createFromImage(d, bmp)
            val gs = PDExtendedGraphicsState().apply { nonStrokingAlphaConstant = 0.14f; strokingAlphaConstant = 0.14f }
            for (page in d.pages) {
                val box = page.mediaBox
                val targetW = minOf(box.width, box.height) * 0.8f
                val scale = targetW / bmp.width
                val w = bmp.width * scale; val h = bmp.height * scale
                PDPageContentStream(d, page, PDPageContentStream.AppendMode.APPEND, true, true).use { cs ->
                    cs.setGraphicsStateParameters(gs)
                    val theta = Math.PI / 5
                    val m = Matrix.getRotateInstance(theta, box.width / 2, box.height / 2)
                    cs.transform(m)
                    cs.drawImage(img, -w / 2, -h / 2, w, h)
                }
            }
            save(d)
        }
    }

    suspend fun number(bytes: ByteArray, style: NumberStyle): ByteArray = withContext(Dispatchers.IO) {
        val ar = NumberFormat.getInstance(Locale("ar", "SA"))
        load(bytes).use { d ->
            val total = d.numberOfPages
            d.pages.forEachIndexed { i, page ->
                val n = i + 1
                val label = when (style) {
                    NumberStyle.ARABIC -> ar.format(n)
                    NumberStyle.LATIN -> "$n"
                    NumberStyle.OF_TOTAL -> "${ar.format(n)} من ${ar.format(total)}"
                }
                val bmp = textBitmap(label, 64f, Color.DKGRAY, false)
                val img = LosslessFactory.createFromImage(d, bmp)
                val box = page.mediaBox
                val h = 14f; val w = h * bmp.width / bmp.height
                PDPageContentStream(d, page, PDPageContentStream.AppendMode.APPEND, true, true).use { cs ->
                    cs.drawImage(img, box.lowerLeftX + (box.width - w) / 2, box.lowerLeftY + 20f, w, h)
                }
            }
            save(d)
        }
    }

    suspend fun protect(bytes: ByteArray, password: String): ByteArray = withContext(Dispatchers.IO) {
        if (password.length < 4) throw ToolException("كلمة المرور 4 خانات على الأقل.")
        load(bytes).use { d ->
            d.protect(StandardProtectionPolicy(password, password, AccessPermission()).apply { encryptionKeyLength = 128 })
            save(d)
        }
    }

    // ---- تحويلات عبر PdfRenderer ----

    private fun renderer(bytes: ByteArray): Pair<PdfRenderer, File> {
        val f = File.createTempFile("aw", ".pdf", appCtx.cacheDir)
        f.writeBytes(bytes)
        return try {
            PdfRenderer(ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY)) to f
        } catch (e: Exception) {
            f.delete(); throw ToolException("تعذّر قراءة صفحات الملف.")
        }
    }

    suspend fun renderPages(bytes: ByteArray, scale: Float = 2f, maxPages: Int = 200, onPage: (Int, Int) -> Unit = { _, _ -> }): List<Bitmap> =
        withContext(Dispatchers.IO) {
            val (r, f) = renderer(bytes)
            try {
                (0 until minOf(r.pageCount, maxPages)).map { i ->
                    onPage(i + 1, r.pageCount)
                    r.openPage(i).use { p ->
                        val bmp = Bitmap.createBitmap((p.width * scale).toInt(), (p.height * scale).toInt(), Bitmap.Config.ARGB_8888)
                        bmp.eraseColor(Color.WHITE)
                        p.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        bmp
                    }
                }
            } finally { r.close(); f.delete() }
        }

    fun thumbnail(bytes: ByteArray, index: Int = 0, width: Int = 900): Bitmap? = runCatching {
        val (r, f) = renderer(bytes)
        try {
            r.openPage(index.coerceIn(0, r.pageCount - 1)).use { p ->
                val h = width * p.height / p.width
                Bitmap.createBitmap(width, h, Bitmap.Config.ARGB_8888).also {
                    it.eraseColor(Color.WHITE); p.render(it, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                }
            }
        } finally { r.close(); f.delete() }
    }.getOrNull()

    /** ضغط قوي: يعيد رسم الصفحات صوراً بجودة أقل. */
    suspend fun compress(bytes: ByteArray): ByteArray = withContext(Dispatchers.IO) {
        val pages = renderPages(bytes, 1.4f)
        PDDocument().use { d ->
            pages.forEach { bmp ->
                val page = PDPage(PDRectangle(bmp.width / 1.4f, bmp.height / 1.4f))
                d.addPage(page)
                val img = JPEGFactory.createFromImage(d, bmp, 0.6f)
                PDPageContentStream(d, page).use { it.drawImage(img, 0f, 0f, page.mediaBox.width, page.mediaBox.height) }
            }
            save(d)
        }
    }

    fun pngs(pages: List<Bitmap>): List<ByteArray> = pages.map { b ->
        ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    suspend fun fromImages(images: List<ByteArray>): ByteArray = withContext(Dispatchers.IO) {
        if (images.isEmpty()) throw ToolException("أضف صوراً أولاً.")
        val doc = PdfDocument()
        images.forEachIndexed { i, b ->
            val bmp = BitmapFactory.decodeByteArray(b, 0, b.size) ?: throw ToolException("تعذّر قراءة الصورة ${i + 1}.")
            val page = doc.startPage(PdfDocument.PageInfo.Builder(bmp.width, bmp.height, i + 1).create())
            page.canvas.drawBitmap(bmp, 0f, 0f, null)
            doc.finishPage(page)
        }
        ByteArrayOutputStream().also { doc.writeTo(it); doc.close() }.toByteArray()
    }

    /** يستخرج النص ويحوّل أشكال الحروف المعروضة إلى حروفها الأصلية. */
    suspend fun text(bytes: ByteArray): String = withContext(Dispatchers.IO) {
        load(bytes).use { d ->
            val raw = PDFTextStripper().apply { sortByPosition = true }.getText(d)
            Normalizer.normalize(raw, Normalizer.Form.NFKC).trim()
        }
    }
}

// ---------- إخراج نص عربي إلى PDF ----------

object ArabicPdfWriter {
    /** يصف النص على صفحات A4 من اليمين لليسار، مع عنوان وشعار اختياري. */
    fun make(body: String, title: String? = null, logo: Bitmap? = null): ByteArray {
        val W = 595; val H = 842; val margin = 56f
        val doc = PdfDocument()
        val width = (W - margin * 2).toInt()
        val bodyPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 14f; color = Color.BLACK; typeface = PdfTools.amiri }
        val titlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 22f; color = Color.BLACK; typeface = PdfTools.amiriBold }
        fun layout(t: String, p: TextPaint) = StaticLayout.Builder.obtain(t, 0, t.length, p, width)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL).setTextDirection(TextDirectionHeuristics.RTL)
            .setLineSpacing(6f, 1f).build()

        val bodyLayout = layout(body, bodyPaint)
        var line = 0
        var pageNo = 0
        while (line < bodyLayout.lineCount || pageNo == 0) {
            pageNo++
            val page = doc.startPage(PdfDocument.PageInfo.Builder(W, H, pageNo).create())
            val c = page.canvas
            var top = margin
            if (pageNo == 1) {
                logo?.let {
                    val h = 48f; val w = h * it.width / it.height
                    c.drawBitmap(it, null, android.graphics.RectF(W - margin - w, top, W - margin, top + h), null)
                    top += h + 16f
                }
                title?.takeIf { it.isNotBlank() }?.let {
                    val tl = layout(it, titlePaint)
                    c.save(); c.translate(margin, top); tl.draw(c); c.restore()
                    top += tl.height + 18f
                }
            }
            val avail = H - margin - top
            val startLine = line
            val startY = if (line < bodyLayout.lineCount) bodyLayout.getLineTop(line) else 0
            while (line < bodyLayout.lineCount && bodyLayout.getLineBottom(line) - startY <= avail) line++
            if (line == startLine && line < bodyLayout.lineCount) line++
            if (startLine < bodyLayout.lineCount) {
                val endY = bodyLayout.getLineBottom(line - 1)
                c.save()
                c.translate(margin, top - startY)
                c.clipRect(0f, startY.toFloat(), width.toFloat(), endY.toFloat())
                bodyLayout.draw(c)
                c.restore()
            }
            doc.finishPage(page)
            if (body.isEmpty()) break
        }
        return ByteArrayOutputStream().also { doc.writeTo(it); doc.close() }.toByteArray()
    }
}

fun Uri.bytes(ctx: Context) = Files.read(ctx, this)
