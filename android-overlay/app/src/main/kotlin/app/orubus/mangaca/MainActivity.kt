package app.orubus.mangaca

import android.content.Context
import android.content.ContextWrapper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(newBase)
        AppContextHolder.init(newBase)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.orubus.mangaca/updater")
        Updater.attach(channel)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "installedVersion" -> result.success(Updater.installedInfo())
                "check" -> Updater.check(result)
                "start" -> {
                    @Suppress("UNCHECKED_CAST")
                    Updater.start(call.arguments() as? Map<String, Any?> ?: emptyMap())
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
