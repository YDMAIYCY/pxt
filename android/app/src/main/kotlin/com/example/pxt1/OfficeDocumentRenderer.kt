package com.example.pxt1

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.Xml
import org.apache.poi.EncryptedDocumentException
import org.apache.poi.ddf.EscherRecord
import org.apache.poi.ddf.EscherTextboxRecord
import org.apache.poi.hslf.record.Document
import org.apache.poi.hslf.record.EscherTextboxWrapper
import org.apache.poi.hslf.record.PPDrawing
import org.apache.poi.hslf.record.PersistPtrHolder
import org.apache.poi.hslf.record.PositionDependentRecord
import org.apache.poi.hslf.record.Record
import org.apache.poi.hslf.record.Slide
import org.apache.poi.hslf.record.TextBytesAtom
import org.apache.poi.hslf.record.TextCharsAtom
import org.apache.poi.hslf.record.UserEditAtom
import org.apache.poi.hslf.usermodel.HSLFSlideShowImpl
import org.apache.poi.hwpf.extractor.WordExtractor
import org.apache.poi.poifs.filesystem.POIFSFileSystem
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.io.FileOutputStream
import java.net.URI
import java.util.Locale
import java.util.zip.ZipFile

/** Text import for OCR, not an Office layout renderer. The caller's saved original is read-only. */
internal object OfficeDocumentRenderer {
    private const val PAGE_WIDTH = 1240
    private const val PAGE_HEIGHT = 1754
    private const val MARGIN = 72
    private const val MAX_TEXT_LENGTH = 2_000_000
    private const val WORD_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    private const val DRAWING_NS = "http://schemas.openxmlformats.org/drawingml/2006/main"
    private const val PRESENTATION_NS = "http://schemas.openxmlformats.org/presentationml/2006/main"
    private const val REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private const val PACKAGE_REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"

    fun render(arguments: Any?): List<Map<String, Any>> {
        val args = arguments as? Map<*, *> ?: error("Office 渲染参数异常")
        val document = File(args["documentPath"] as? String ?: error("Office 文档路径缺失"))
        val outputDirectory = File(
            args["outputDirectoryPath"] as? String ?: error("Office 输出目录缺失"),
        )
        val prefix = args["outputPrefix"] as? String ?: "office_page"
        val limit = args["maxPages"] ?: 80
        require(limit is Number && limit.toDouble() in 1.0..80.0 &&
            limit.toDouble() == limit.toInt().toDouble()) { "Office 页数上限必须是 1 至 80 的整数" }
        val maxPages = limit.toInt()
        require(prefix.isNotBlank() && prefix.length <= 120 &&
            prefix.none { it == '/' || it == '\\' || it.isISOControl() }) { "Office 输出文件名前缀无效" }
        require(document.isFile && document.canRead()) { "Office 文件不存在或无法读取" }
        require(document.length() > 0) { "Office 文件为空" }
        val sections = try {
            when (document.extension.lowercase(Locale.ROOT)) {
                "doc" -> listOf(readDoc(document))
                "ppt" -> readPpt(document)
                "docx", "pptx" -> readOoxml(document)
                else -> error("仅支持 .doc、.docx、.ppt、.pptx 文件")
            }
        } catch (error: EncryptedDocumentException) {
            throw IllegalArgumentException("Office 文档已加密，请解除密码保护后导入", error)
        } catch (error: Exception) {
            throw IllegalArgumentException("Office 文档读取失败（文件损坏、格式错误或不受支持）：${error.message}", error)
        }
        val textSections = sections.map(::normalizeText)
        require(textSections.any { it.isNotBlank() }) { "Office 文档没有可导入的文字（空文档或仅包含图片）" }
        require(textSections.sumOf { it.length.toLong() } <= MAX_TEXT_LENGTH) {
            "Office 文档文字过多，请拆分后导入"
        }
        require(outputDirectory.isDirectory || outputDirectory.mkdirs()) { "无法创建 Office 输出目录" }

        val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = 36f
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        }
        val createdFiles = mutableListOf<File>()
        val pages = mutableListOf<Map<String, Any>>()
        try {
            for (text in textSections) {
                if (text.isBlank()) continue
                val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, PAGE_WIDTH - 2 * MARGIN)
                    .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                    .setIncludePad(true)
                    .setLineSpacing(8f, 1.15f)
                    .build()
                var firstLine = 0
                while (firstLine < layout.lineCount) {
                    require(pages.size < maxPages) {
                        "Office 文字分页超过 ${maxPages} 页，请拆分后导入"
                    }
                    val top = layout.getLineTop(firstLine)
                    var endLine = firstLine + 1
                    while (endLine < layout.lineCount &&
                        layout.getLineBottom(endLine) - top <= PAGE_HEIGHT - 2 * MARGIN) {
                        endLine++
                    }
                    val pageNumber = pages.size + 1
                    val output = File(outputDirectory, "${prefix}_${pageNumber}.png")
                    // Reserve rather than overwrite: cleanup must never delete earlier imports or the original.
                    require(output.createNewFile()) { "Office 输出文件已存在：${output.name}" }
                    createdFiles.add(output)
                    val bitmap = Bitmap.createBitmap(PAGE_WIDTH, PAGE_HEIGHT, Bitmap.Config.ARGB_8888)
                    try {
                        bitmap.eraseColor(Color.WHITE)
                        val canvas = Canvas(bitmap)
                        canvas.clipRect(
                            MARGIN, MARGIN, PAGE_WIDTH - MARGIN,
                            MARGIN + layout.getLineBottom(endLine - 1) - top,
                        )
                        canvas.translate(MARGIN.toFloat(), (MARGIN - top).toFloat())
                        layout.draw(canvas)
                        FileOutputStream(output).use { stream ->
                            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) { "Office PNG 保存失败" }
                        }
                    } finally {
                        bitmap.recycle()
                    }
                    pages.add(mapOf("pageNumber" to pageNumber, "savedPath" to output.absolutePath))
                    firstLine = endLine
                }
            }
            return pages
        } catch (error: Throwable) {
            createdFiles.forEach { file ->
                if (!file.delete() && file.exists()) {
                    error.addSuppressed(IllegalStateException("无法清理 Office 临时页面：${file.absolutePath}"))
                }
            }
            throw error
        }
    }

    private fun readDoc(file: File): String = file.inputStream().use { input ->
        POIFSFileSystem(input).use { fs ->
            // Reject even documents using Office's default password, before POI auto-decrypts them.
            fs.root.createDocumentInputStream("WordDocument").use { word ->
                val header = ByteArray(12)
                word.readFully(header)
                require(header[11].toInt() and 1 == 0) { "Word 文档已加密，请解除密码保护后导入" }
            }
            WordExtractor(fs).use { extractor -> extractor.text }
        }
    }

    private fun readPpt(file: File): List<String> = file.inputStream().use { input ->
        // Use record APIs only. HSLFSlideShow/HSLFShape initialize desktop java.awt classes.
        HSLFSlideShowImpl(input).use { show ->
            require(show.documentEncryptionAtom == null) { "PowerPoint 文档已加密，请解除密码保护后导入" }
            val locations = mutableMapOf<Int, Int>()
            val recordsByOffset = mutableMapOf<Int, Record>()
            for (record in show.records) {
                if (record is PersistPtrHolder) locations.putAll(record.slideLocationsLookup)
                if (record is PositionDependentRecord) recordsByOffset[record.lastOnDiskOffset] = record
            }
            val documentId = show.records.filterIsInstance<UserEditAtom>().lastOrNull()?.docPersistRef
                ?: error("PowerPoint 缺少文档引用")
            val document = recordsByOffset[locations[documentId]] as? Document
                ?: error("PowerPoint 文档记录损坏")
            val slides = document.slideSlideListWithText?.slideAtomsSets ?: return emptyList()
            slides.map { slide ->
                val record = recordsByOffset[locations[slide.slidePersistAtom.refID]] as? Slide
                    ?: error("PowerPoint 幻灯片记录缺失")
                val outline = buildString { slide.slideRecords.forEach { appendPptText(it, this) } }
                // Outline text is referenced (not duplicated) by slide placeholders. Other shapes
                // store their own text in drawing textbox records, including groups and table cells.
                outline + buildString { appendPptText(record, this) }
            }
        }
    }

    private fun appendPptText(record: Record, text: StringBuilder) {
        when (record) {
            is TextCharsAtom -> text.append(record.text).append('\n')
            is TextBytesAtom -> text.append(record.text).append('\n')
            is PPDrawing -> record.escherRecords.forEach { appendEscherText(it, text) }
            else -> record.childRecords?.forEach { appendPptText(it, text) }
        }
        require(text.length <= MAX_TEXT_LENGTH) { "Office 文档文字过多，请拆分后导入" }
    }

    private fun appendEscherText(record: EscherRecord, text: StringBuilder) {
        if (record is EscherTextboxRecord) {
            appendPptText(EscherTextboxWrapper(record), text)
        } else {
            record.childRecords.forEach { appendEscherText(it, text) }
        }
    }

    private fun readOoxml(file: File): List<String> {
        file.inputStream().use { input ->
            // Password protected OOXML is wrapped in an OLE compound file, not a ZIP.
            if (input.read() == 0xD0 && input.read() == 0xCF) {
                error("Office 文档已加密或扩展名与格式不符，请解除密码保护后重试")
            }
        }
        return ZipFile(file).use { zip ->
            if (file.extension.equals("docx", ignoreCase = true)) {
                listOf(readXmlText(zip, "word/document.xml", WORD_NS, "document"))
            } else {
                val relationships = mutableMapOf<String, String>()
                parseXml(zip, "ppt/_rels/presentation.xml.rels", PACKAGE_REL_NS, "Relationships") { xml ->
                    if (xml.eventType == XmlPullParser.START_TAG && xml.name == "Relationship" &&
                        xml.namespace == PACKAGE_REL_NS &&
                        xml.getAttributeValue(null, "Type") in setOf(
                            "$REL_NS/slide", "http://purl.oclc.org/ooxml/officeDocument/relationships/slide",
                        )) {
                        require(xml.getAttributeValue(null, "TargetMode") != "External") { "不支持外部幻灯片" }
                        val id = xml.getAttributeValue(null, "Id") ?: error("幻灯片关系 ID 缺失")
                        val target = xml.getAttributeValue(null, "Target") ?: error("幻灯片路径缺失")
                        val uri = URI("/ppt/presentation.xml").resolve(target).normalize()
                        require(uri.scheme == null && uri.authority == null && uri.query == null &&
                            uri.fragment == null && uri.path.startsWith("/ppt/")) { "幻灯片路径无效" }
                        require(relationships.put(id, uri.path.removePrefix("/")) == null) { "幻灯片关系重复" }
                    }
                }
                val slidePaths = mutableListOf<String>()
                var inSlideList = false
                parseXml(zip, "ppt/presentation.xml", PRESENTATION_NS, "presentation") { xml ->
                    if (matchesNamespace(xml.namespace, PRESENTATION_NS)) {
                        if (xml.name == "sldIdLst") inSlideList = xml.eventType == XmlPullParser.START_TAG
                        if (inSlideList && xml.name == "sldId" && xml.eventType == XmlPullParser.START_TAG) {
                            val id = xml.getAttributeValue(REL_NS, "id")
                                ?: xml.getAttributeValue("http://purl.oclc.org/ooxml/officeDocument/relationships", "id")
                            slidePaths.add(relationships[id] ?: error("幻灯片关系缺失"))
                        }
                    }
                }
                // Presentation order can differ from slide1.xml, slide2.xml, ... filename order.
                slidePaths.map { readXmlText(zip, it, PRESENTATION_NS, "sld") }
            }
        }
    }

    private fun readXmlText(zip: ZipFile, path: String, rootNamespace: String, root: String): String {
        val text = StringBuilder()
        var inText = false
        var inBody = root != "document"
        parseXml(zip, path, rootNamespace, root) { xml ->
            val word = matchesNamespace(xml.namespace, WORD_NS)
            val drawing = matchesNamespace(xml.namespace, DRAWING_NS)
            when (xml.eventType) {
                XmlPullParser.START_TAG -> {
                    if (word && xml.name == "body") inBody = true
                    if (inBody && (word || drawing)) {
                        when (xml.name) {
                            "t" -> inText = true
                            "tab" -> text.append('\t')
                            "br", "cr" -> text.append('\n')
                        }
                    }
                }
                XmlPullParser.TEXT, XmlPullParser.CDSECT, XmlPullParser.ENTITY_REF -> {
                    if (inText) text.append(xml.text ?: "")
                }
                XmlPullParser.END_TAG -> {
                    if ((word || drawing) && xml.name == "t") inText = false
                    if (inBody && (word || drawing)) {
                        when (xml.name) {
                            "p", "tr" -> text.append('\n')
                            "tc" -> text.append('\t')
                        }
                    }
                    if (word && xml.name == "body") inBody = false
                }
            }
            require(text.length <= MAX_TEXT_LENGTH) { "Office 文档文字过多，请拆分后导入" }
        }
        return text.toString()
    }

    private fun parseXml(
        zip: ZipFile,
        path: String,
        namespace: String,
        root: String,
        consume: (XmlPullParser) -> Unit,
    ) {
        val entry = zip.getEntry(path) ?: error("Office 文档缺少 $path")
        require(entry.size in 1..32_000_000) { "Office XML 内容为空或过大：$path" }
        zip.getInputStream(entry).use { input ->
            val xml = Xml.newPullParser()
            xml.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, true)
            xml.setInput(input, null)
            var foundRoot = false
            while (xml.eventType != XmlPullParser.END_DOCUMENT) {
                require(xml.eventType != XmlPullParser.DOCDECL) { "Office XML 不允许 DTD" }
                if (xml.eventType == XmlPullParser.START_TAG && !foundRoot) {
                    require(xml.name == root && matchesNamespace(xml.namespace, namespace)) {
                        "Office XML 格式错误：$path"
                    }
                    foundRoot = true
                }
                consume(xml)
                xml.nextToken()
            }
            require(foundRoot) { "Office XML 为空：$path" }
        }
    }

    private fun matchesNamespace(actual: String?, expected: String): Boolean =
        actual == expected || actual == when (expected) {
            WORD_NS -> "http://purl.oclc.org/ooxml/wordprocessingml/main"
            DRAWING_NS -> "http://purl.oclc.org/ooxml/drawingml/main"
            PRESENTATION_NS -> "http://purl.oclc.org/ooxml/presentationml/main"
            else -> expected
        }

    private fun normalizeText(text: String): String = text
        .replace("\r\n", "\n").replace('\r', '\n')
        .replace('\u000b', '\n').replace('\u000c', '\n').replace('\u0007', '\t')
        .filter { !it.isISOControl() || it == '\n' || it == '\t' }
        .trim()
}
