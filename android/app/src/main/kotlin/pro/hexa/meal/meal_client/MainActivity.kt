package pro.hexa.meal.meal_client

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "refresh") {
                    BapUWidgetUpdateWorker.enqueueOneTime(this)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    companion object {
        private const val CHANNEL = "pro.hexa.meal.meal_client/widget"
    }
}
