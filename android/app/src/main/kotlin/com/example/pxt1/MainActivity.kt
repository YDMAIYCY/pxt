package com.example.pxt1

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(
            messenger,
            "pxt1/office_renderer",
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            if (call.method != "renderOffice") {
                result.notImplemented()
            } else {
                try {
                    result.success(OfficeDocumentRenderer.render(call.arguments))
                } catch (error: Throwable) {
                    result.error("OFFICE_RENDER_FAILED", error.message ?: "Office 文档导入失败", null)
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PDF_RENDERER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "renderPdf" -> renderPdf(call.arguments, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun renderPdf(arguments: Any?, result: MethodChannel.Result) {
        try {
            val args = arguments as? Map<*, *> ?: error("PDF 渲染参数异常")
            val pdfPath = args["pdfPath"] as? String ?: error("PDF 路径缺失")
            val outputDirectoryPath =
                args["outputDirectoryPath"] as? String ?: error("PDF 输出目录缺失")
            val outputPrefix = args["outputPrefix"] as? String ?: "pdf_page"
            val maxPages = (args["maxPages"] as? Number)?.toInt() ?: 80
            val maxLongestSide = (args["maxLongestSide"] as? Number)?.toInt() ?: 1600
            val maxRenderedPixels = (args["maxRenderedPixels"] as? Number)?.toInt() ?: 2_200_000

            val renderedPages = renderPdfPages(
                pdfFile = File(pdfPath),
                outputDirectory = File(outputDirectoryPath),
                outputPrefix = outputPrefix,
                maxPages = maxPages,
                maxLongestSide = maxLongestSide,
                maxRenderedPixels = maxRenderedPixels,
            )
            result.success(renderedPages)
        } catch (error: Throwable) {
            result.error("PDF_RENDER_FAILED", error.message ?: "PDF 渲染失败", null)
        }
    }

    private fun renderPdfPages(
        pdfFile: File,
        outputDirectory: File,
        outputPrefix: String,
        maxPages: Int,
        maxLongestSide: Int,
        maxRenderedPixels: Int,
    ): List<Map<String, Any>> {
        require(pdfFile.exists()) { "PDF 文件不存在" }
        if (!outputDirectory.exists()) {
            outputDirectory.mkdirs()
        }

        val renderedFiles = mutableListOf<File>()
        try {
            ParcelFileDescriptor.open(pdfFile, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                PdfRenderer(descriptor).use { renderer ->
                    val pageCount = renderer.pageCount
                    require(pageCount > 0) { "PDF 没有可导入的页面" }
                    require(pageCount <= maxPages) {
                        "PDF 页数过多（${pageCount} 页），请先拆分为 ${maxPages} 页以内再导入"
                    }

                    val renderedPages = mutableListOf<Map<String, Any>>()
                    for (index in 0 until pageCount) {
                        renderer.openPage(index).use { page ->
                            val size = resolveRenderSize(
                                pageWidth = page.width,
                                pageHeight = page.height,
                                maxLongestSide = maxLongestSide,
                                maxRenderedPixels = maxRenderedPixels,
                            )
                            val bitmap = Bitmap.createBitmap(
                                size.width,
                                size.height,
                                Bitmap.Config.ARGB_8888,
                            )
                            try {
                                bitmap.eraseColor(Color.WHITE)
                                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                val outputFile = File(outputDirectory, "${outputPrefix}_${index + 1}.png")
                                FileOutputStream(outputFile).use { stream ->
                                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                                }
                                renderedFiles.add(outputFile)
                                renderedPages.add(
                                    mapOf(
                                        "pageNumber" to index + 1,
                                        "savedPath" to outputFile.absolutePath,
                                    ),
                                )
                            } finally {
                                bitmap.recycle()
                            }
                        }
                    }
                    return renderedPages
                }
            }
        } catch (error: Throwable) {
            renderedFiles.forEach { file ->
                runCatching { if (file.exists()) file.delete() }
            }
            throw error
        }
    }

    private fun resolveRenderSize(
        pageWidth: Int,
        pageHeight: Int,
        maxLongestSide: Int,
        maxRenderedPixels: Int,
    ): RenderSize {
        require(pageWidth > 0 && pageHeight > 0) { "PDF 页面尺寸异常，无法导入" }

        val longestSide = max(pageWidth, pageHeight).toDouble()
        var scale = min(2.0, maxLongestSide.toDouble() / longestSide)
        val estimatedPixels = pageWidth * scale * pageHeight * scale
        if (estimatedPixels > maxRenderedPixels) {
            scale *= sqrt(maxRenderedPixels / estimatedPixels)
        }

        return RenderSize(
            width = max(1, (pageWidth * scale).roundToInt()),
            height = max(1, (pageHeight * scale).roundToInt()),
        )
    }

    private data class RenderSize(val width: Int, val height: Int)

    private companion object {
        const val PDF_RENDERER_CHANNEL = "pxt1/pdf_renderer"
    }
}
