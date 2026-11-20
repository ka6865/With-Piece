package kr.wooripiece.woori_piece

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kr.wooripiece/scan_cache")
            .setMethodCallHandler { call, result ->
                if (call.method == "directory") {
                    result.success(File(noBackupFilesDir, "scan_snapshots").path)
                } else {
                    result.notImplemented()
                }
            }
    }
}
