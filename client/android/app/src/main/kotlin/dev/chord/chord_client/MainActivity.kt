package dev.chord.chord_client

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// v1.1: native file picker via SAF (no Flutter plugin, see AGENTS.md pitfall 8).
// Channel "chord/file" method "pickFile" returns {path, name} or null on cancel.
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingCacheFile: File? = null
    private val pickRequest = 42001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chord/file")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // v1.1.9+: 前端 storage 抽象在 Android 上需要可写私有目录
                    "storagePath" -> result.success(File(filesDir, "storage").absolutePath)
                    "pickFile" -> {
                        val imagesOnly = call.argument<Boolean>("imagesOnly") ?: false
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = if (imagesOnly) "image/*" else "*/*"
                        }
                        try {
                            startActivityForResult(
                                Intent.createChooser(intent, "选择文件"), pickRequest)
                        } catch (e: Exception) {
                            pendingResult = null
                            result.error("unavailable", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest) return
        val result = pendingResult
        pendingResult = null
        pendingCacheFile?.delete()
        pendingCacheFile = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result?.success(null)
            return
        }
        try {
            val name = queryName(uri) ?: "file"
            val cached = File(cacheDir, "pick_${System.currentTimeMillis()}_$name")
            contentResolver.openInputStream(uri)?.use { input ->
                cached.outputStream().use { input.copyTo(it) }
            } ?: throw IllegalStateException("无法读取所选内容")
            pendingCacheFile = cached
            result?.success(mapOf("path" to cached.absolutePath, "name" to name))
        } catch (e: Exception) {
            result?.error("read_failed", e.message, null)
        }
    }

    private fun queryName(uri: Uri): String? = try {
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, null, null, null, null)
            val idx = cursor?.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx != null && idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
        } finally {
            cursor?.close()
        }
    } catch (_: Exception) {
        null
    }
}
