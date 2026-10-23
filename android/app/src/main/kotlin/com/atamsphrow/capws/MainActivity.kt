package com.atamsphrow.capws

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var plugin: ShizukuPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        plugin = ShizukuPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.attach() }
    }

    override fun onDestroy() {
        plugin?.detach()
        plugin = null
        super.onDestroy()
    }
}
