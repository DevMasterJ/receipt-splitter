package dev.webmasterj.receiptsplitter

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var tableWifi: TableWifi? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "receipt_splitter/table_wifi")
        tableWifi = TableWifi(this, channel).also { channel.setMethodCallHandler(it) }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == TableWifi.PERMISSION_REQUEST) {
            tableWifi?.onPermissionResult(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
        }
    }

    override fun onDestroy() {
        tableWifi?.dispose()
        super.onDestroy()
    }
}
