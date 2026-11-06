package app.arabwriter.android.service

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import app.arabwriter.android.core.ArabicLinter
import org.xmlpull.v1.XmlPullParser
import android.util.Xml
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

class ToolException(msg: String) : Exception(msg)

// ---------- الملفات ----------

object Files {
    fun name(ctx: Context, uri: Uri): String {
        ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0)?.let { return it }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "ملف"
    }

    fun ext(ctx: Context, uri: Uri) = name(ctx, uri).substringAfterLast('.', "").lowercase()

    fun base(ctx: Context, uri: Uri) = name(ctx, uri).substringBeforeLast('.')

    fun read(ctx: Context, uri: Uri): ByteArray =
        ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: throw ToolException("تعذّر فتح الملف «${name(ctx, uri)}».")

    fun write(ctx: Context, uri: Uri, bytes: ByteArray) {
        ctx.contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) } ?: throw ToolException("تعذّر حفظ الملف.")
    }

    /** يكتب ملفاً جديداً داخل مجلد اختاره المستخدم. */
    fun writeInTree(ctx: Context, tree: Uri, name: String, mime: String, bytes: ByteArray) {
        val dir = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val doc = DocumentsContract.createDocument(ctx.contentResolver, dir, mime, name) ?: throw ToolException("تعذّر إنشاء «$name».")
        write(ctx, doc, bytes)
    }

    fun unzip(bytes: ByteArray): LinkedHashMap<String, ByteArray> {
        val out = LinkedHashMap<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { z ->
            var e: ZipEntry? = z.nextEntry
            while (e != null) {
                if (!e.isDirectory) out[e.name] = z.readBytes()
                e = z.nextEntry
            }
        }
        if (out.isEmpty()) throw ToolException("الملف تالف أو ليس بالصيغة المتوقعة.")
        return out
    }

    fun zip(entries: Map<String, ByteArray>): ByteArray {
        val bos = ByteArrayOutputStream()
        ZipOutputStream(bos).use { z ->
            for ((n, b) in entries) { z.putNextEntry(ZipEntry(n)); z.write(b); z.closeEntry() }
        }
        return bos.toByteArray()
    }

    fun xml(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
    fun unxml(s: String) = s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")
}

// ---------- وورد ----------

/** مستند وورد يُعدَّل داخل نصوصه مباشرة، فيبقى التنسيق كما هو. */
class DocxDocument private constructor(private val parts: LinkedHashMap<String, ByteArray>) {
    private var xml: String = String(parts["word/document.xml"] ?: throw ToolException("هذا ليس ملف وورد."), Charsets.UTF_8)

    private val runRx = Regex("(<w:t(?:\\s[^>]*)?>)([^<]*)(</w:t>)")

    val paragraphs: List<String>
        get() = Regex("<w:p[ >].*?</w:p>|<w:p/>", RegexOption.DOT_MATCHES_ALL).findAll(xml).map { p ->
            runRx.findAll(p.value).joinToString("") { Files.unxml(it.groupValues[2]) }
        }.toList()

    val text get() = paragraphs.joinToString("\n")

    private fun mapRuns(f: (String) -> Pair<String, Int>): Int {
        var n = 0
        xml = runRx.replace(xml) { m ->
            val (t, c) = f(Files.unxml(m.groupValues[2]))
            n += c
            m.groupValues[1].let { open ->
                val o = if (t.startsWith(" ") || t.endsWith(" ")) open.replace("<w:t>", "<w:t xml:space=\"preserve\">") else open
                o + Files.xml(t) + m.groupValues[3]
            }
        }
        return n
    }

    /** تدقيق آمن داخل كل مقطع نصي. */
    fun safeFix(): Int = mapRuns { ArabicLinter.fixInline(it) }

    fun replaceAll(find: String, with: String): Int {
        if (find.isEmpty()) return 0
        return mapRuns { t ->
            val c = Regex(Regex.escape(find)).findAll(t).count()
            t.replace(find, with) to c
        }
    }

    /** يجعل كل الفقرات من اليمين لليسار. */
    fun forceRTL() {
        xml = xml.replace(Regex("<w:bidi\\s*/>"), "")
        xml = xml.replace(Regex("<w:pPr>"), "<w:pPr><w:bidi/>")
        xml = xml.replace(Regex("<w:p(\\s[^>]*)?>(?!<w:pPr>)")) { m -> m.value + "<w:pPr><w:bidi/></w:pPr>" }
    }

    fun bytes(): ByteArray {
        parts["word/document.xml"] = xml.toByteArray(Charsets.UTF_8)
        return Files.zip(parts)
    }

    companion object {
        fun open(bytes: ByteArray) = DocxDocument(Files.unzip(bytes))

        /** مستند عربي جديد من نص: السطر الأول عنوان إن طُلب. */
        fun build(body: String, title: String? = null): ByteArray {
            fun para(t: String, bold: Boolean, size: Int) = "<w:p><w:pPr><w:bidi/><w:jc w:val=\"right\"/><w:spacing w:after=\"160\"/></w:pPr>" +
                "<w:r><w:rPr><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\" w:cs=\"Arial\"/>${if (bold) "<w:b/><w:bCs/>" else ""}<w:rtl/>" +
                "<w:sz w:val=\"$size\"/><w:szCs w:val=\"$size\"/></w:rPr><w:t xml:space=\"preserve\">${Files.xml(t)}</w:t></w:r></w:p>"
            val ps = buildString {
                title?.takeIf { it.isNotBlank() }?.let { append(para(it, true, 36)) }
                body.split('\n').forEach { append(para(it, false, 28)) }
            }
            val doc = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
                "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>$ps" +
                "<w:sectPr><w:bidi/><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\"/></w:sectPr></w:body></w:document>"
            return Files.zip(linkedMapOf(
                "[Content_Types].xml" to ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
                    "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
                    "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>").toByteArray(),
                "_rels/.rels" to ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
                    "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>").toByteArray(),
                "word/document.xml" to doc.toByteArray(Charsets.UTF_8),
            ))
        }
    }
}

// ---------- إكسل ----------

data class Sheet(var name: String, var rows: MutableList<MutableList<String>>) {
    val columnCount get() = rows.maxOfOrNull { it.size } ?: 0
    fun normalize() {
        val n = maxOf(columnCount, 1)
        rows.forEach { r -> while (r.size < n) r.add("") }
    }
    fun copyDeep() = Sheet(name, rows.map { it.toMutableList() }.toMutableList())
}

object SheetIO {
    fun open(bytes: ByteArray, ext: String, name: String): List<Sheet> = when (ext) {
        "csv", "tsv", "txt" -> {
            var s = String(bytes, Charsets.UTF_8)
            if (s.startsWith("﻿")) s = s.substring(1)
            listOf(Sheet(name, parseCSV(s, if (ext == "tsv") '\t' else ',')).also { it.normalize() })
        }
        "xlsx", "xlsm" -> readXLSX(bytes)
        else -> throw ToolException("الصيغة غير مدعومة. افتح xlsx أو csv.")
    }

    fun parseCSV(text: String, sep: Char): MutableList<MutableList<String>> {
        val rows = mutableListOf<MutableList<String>>()
        var row = mutableListOf<String>()
        val f = StringBuilder()
        var q = false
        val t = text.replace("\r\n", "\n")
        var i = 0
        while (i < t.length) {
            val c = t[i]
            if (q) {
                if (c == '"') { if (i + 1 < t.length && t[i + 1] == '"') { f.append('"'); i++ } else q = false } else f.append(c)
            } else when (c) {
                '"' -> q = true
                sep -> { row.add(f.toString()); f.clear() }
                '\n' -> { row.add(f.toString()); f.clear(); rows.add(row); row = mutableListOf() }
                else -> f.append(c)
            }
            i++
        }
        if (f.isNotEmpty() || row.isNotEmpty()) { row.add(f.toString()); rows.add(row) }
        return rows
    }

    private fun parser(b: ByteArray): XmlPullParser = Xml.newPullParser().apply {
        setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
        setInput(ByteArrayInputStream(b), "UTF-8")
    }

    fun colIndex(ref: String): Int {
        var n = 0
        for (ch in ref.uppercase()) { if (ch !in 'A'..'Z') break; n = n * 26 + (ch - 'A' + 1) }
        return maxOf(n - 1, 0)
    }

    fun colName(i: Int): String {
        var n = i + 1; val sb = StringBuilder()
        while (n > 0) { val r = (n - 1) % 26; sb.insert(0, ('A' + r)); n = (n - 1) / 26 }
        return sb.toString()
    }

    private fun readXLSX(bytes: ByteArray): List<Sheet> {
        val parts = Files.unzip(bytes)
        val shared = ArrayList<String>()
        parts["xl/sharedStrings.xml"]?.let { b ->
            val p = parser(b); var inSi = false; var inT = false; var inRph = false; val cur = StringBuilder()
            while (p.next() != XmlPullParser.END_DOCUMENT) when (p.eventType) {
                XmlPullParser.START_TAG -> when (p.name) { "si" -> { inSi = true; cur.clear() }; "t" -> inT = true; "rPh" -> inRph = true }
                XmlPullParser.TEXT -> if (inSi && inT && !inRph) cur.append(p.text)
                XmlPullParser.END_TAG -> when (p.name) { "si" -> { shared.add(cur.toString()); inSi = false }; "t" -> inT = false; "rPh" -> inRph = false }
            }
        }
        val rels = HashMap<String, String>()
        parts["xl/_rels/workbook.xml.rels"]?.let { b ->
            val p = parser(b)
            while (p.next() != XmlPullParser.END_DOCUMENT) if (p.eventType == XmlPullParser.START_TAG && p.name == "Relationship")
                rels[p.getAttributeValue(null, "Id")] = p.getAttributeValue(null, "Target")
        }
        val order = ArrayList<Pair<String, String>>()
        parts["xl/workbook.xml"]?.let { b ->
            val p = parser(b)
            while (p.next() != XmlPullParser.END_DOCUMENT) if (p.eventType == XmlPullParser.START_TAG && p.name == "sheet") {
                val name = p.getAttributeValue(null, "name") ?: "ورقة"
                val rid = p.getAttributeValue(null, "r:id")
                rels[rid]?.let { t -> order.add(name to if (t.startsWith("/")) t.drop(1) else "xl/$t") }
            }
        }
        if (order.isEmpty()) parts.keys.filter { it.startsWith("xl/worksheets/sheet") && it.endsWith(".xml") }.sorted()
            .forEachIndexed { i, k -> order.add("ورقة ${i + 1}" to k) }

        val out = ArrayList<Sheet>()
        for ((name, path) in order) {
            val b = parts[path] ?: continue
            val cells = HashMap<Int, HashMap<Int, String>>()
            val p = parser(b)
            var row = 0; var col = 0; var next = 0; var type = ""; val buf = StringBuilder(); var cap = false
            while (p.next() != XmlPullParser.END_DOCUMENT) when (p.eventType) {
                XmlPullParser.START_TAG -> when (p.name) {
                    "row" -> { row = (p.getAttributeValue(null, "r")?.toIntOrNull() ?: (row + 2)) - 1; next = 0 }
                    "c" -> { col = p.getAttributeValue(null, "r")?.let { colIndex(it) } ?: next; next = col + 1
                             type = p.getAttributeValue(null, "t") ?: ""; buf.clear() }
                    "v", "t" -> cap = true
                }
                XmlPullParser.TEXT -> if (cap) buf.append(p.text)
                XmlPullParser.END_TAG -> when (p.name) {
                    "v", "t" -> cap = false
                    "c" -> {
                        var v = buf.toString()
                        if (type == "s") v = v.toIntOrNull()?.let { shared.getOrNull(it) } ?: v
                        else if (type == "b") v = if (v == "1") "TRUE" else "FALSE"
                        else if (type.isEmpty() || type == "n") v.toDoubleOrNull()?.let { v = fmt(it) }
                        if (v.isNotEmpty()) cells.getOrPut(row) { HashMap() }[col] = v
                    }
                }
            }
            val maxR = cells.keys.maxOrNull()
            val maxC = cells.values.flatMap { it.keys }.maxOrNull() ?: 0
            val rows = if (maxR == null) mutableListOf() else (0..maxR).map { r -> (0..maxC).map { c -> cells[r]?.get(c) ?: "" }.toMutableList() }.toMutableList()
            out.add(Sheet(name, rows).also { it.normalize() })
        }
        if (out.isEmpty()) throw ToolException("ما لقيت أوراقاً في الملف.")
        return out
    }

    fun csv(s: Sheet): ByteArray = ("﻿" + s.rows.joinToString("\n") { r ->
        r.joinToString(",") { v -> if (v.any { it == ',' || it == '"' || it == '\n' }) "\"" + v.replace("\"", "\"\"") + "\"" else v }
    }).toByteArray(Charsets.UTF_8)

    fun xlsx(sheets: List<Sheet>): ByteArray {
        val n = sheets.size
        val m = LinkedHashMap<String, ByteArray>()
        fun put(k: String, v: String) { m[k] = v.toByteArray(Charsets.UTF_8) }
        val head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
        put("[Content_Types].xml", head + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>" +
            (1..n).joinToString("") { "<Override PartName=\"/xl/worksheets/sheet$it.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" } + "</Types>")
        put("_rels/.rels", head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>")
        put("xl/workbook.xml", head + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><bookViews><workbookView/></bookViews><sheets>" +
            sheets.mapIndexed { i, s -> "<sheet name=\"${Files.xml(s.name.take(31))}\" sheetId=\"${i + 1}\" r:id=\"rId${i + 1}\"/>" }.joinToString("") + "</sheets></workbook>")
        put("xl/_rels/workbook.xml.rels", head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            (1..n).joinToString("") { "<Relationship Id=\"rId$it\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet$it.xml\"/>" } +
            "<Relationship Id=\"rId${n + 1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>")
        put("xl/styles.xml", head + "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"2\"><font><sz val=\"12\"/><name val=\"Arial\"/></font><font><b/><sz val=\"12\"/><name val=\"Arial\"/></font></fonts><fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills><borders count=\"1\"><border/></borders><cellStyleXfs count=\"1\"><xf/></cellStyleXfs><cellXfs count=\"2\"><xf fontId=\"0\"/><xf fontId=\"1\" applyFont=\"1\"/></cellXfs></styleSheet>")
        sheets.forEachIndexed { i, s ->
            val rows = StringBuilder()
            s.rows.forEachIndexed { r, row ->
                rows.append("<row r=\"${r + 1}\">")
                row.forEachIndexed { c, v ->
                    if (v.isEmpty()) return@forEachIndexed
                    val ref = colName(c) + (r + 1)
                    val style = if (r == 0) " s=\"1\"" else ""
                    val num = v.replace(",", "").toDoubleOrNull()
                    if (num != null && (!v.startsWith("0") || v == "0" || v.startsWith("0."))) rows.append("<c r=\"$ref\"$style><v>$num</v></c>")
                    else rows.append("<c r=\"$ref\" t=\"inlineStr\"$style><is><t xml:space=\"preserve\">${Files.xml(v)}</t></is></c>")
                }
                rows.append("</row>")
            }
            put("xl/worksheets/sheet${i + 1}.xml", head + "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetViews><sheetView rightToLeft=\"1\" workbookViewId=\"0\"/></sheetViews><sheetData>$rows</sheetData></worksheet>")
        }
        return Files.zip(m)
    }

    fun number(s: String): Double? {
        val latin = s.map { ch -> if (ch in '٠'..'٩') ('0' + (ch - '٠')) else if (ch == '٫') '.' else ch }.joinToString("")
        return latin.replace(",", "").replace("٬", "").trim().toDoubleOrNull()
    }

    fun fmt(d: Double): String = if (d == Math.floor(d) && Math.abs(d) < 1e15) d.toLong().toString()
        else java.math.BigDecimal(d).setScale(4, java.math.RoundingMode.HALF_UP).stripTrailingZeros().toPlainString()
}
