package pro.hexa.meal.meal_client

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "pro.hexa.meal.meal_client/meal_background_refresh").setMethodCallHandler { call, result ->
            if (call.method != "postpone") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val notBeforeMillis = (call.arguments as? Number)?.toLong()
            if (notBeforeMillis == null) {
                result.error("INVALID_TIME", "Next refresh time is required", null)
                return@setMethodCallHandler
            }
            BapUWidgetUpdateDispatcher.execute {
                try {
                    BapUMealBackgroundRefresh.postpone(applicationContext, notBeforeMillis)
                    runOnUiThread { result.success(null) }
                } catch (error: Exception) {
                    runOnUiThread { result.error("SCHEDULE_FAILED", error.message, null) }
                }
            }
        }
    }
}
