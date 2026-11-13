package com.jortanviewer.jortan_viewer

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.jortanviewer/remote").setMethodCallHandler { call, result ->
            if (call.method != "open") { result.notImplemented(); return@setMethodCallHandler }
            val raw = call.argument<String>("url") ?: ""
            val uri = Uri.parse(raw)
            if (uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null || uri.query != null || uri.fragment != null || raw.length > 2048) {
                result.error("url_invalida", "Use o endereço HTTPS da ponte.", null)
            } else {
                startActivity(Intent(this, RemoteViewerActivity::class.java).putExtra("url", raw))
                result.success(null)
            }
        }
    }
}
