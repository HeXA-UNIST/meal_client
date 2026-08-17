package pro.hexa.meal.bapu_widget_bridge;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class BapUWidgetBridgePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private static final String CHANNEL = "pro.hexa.meal.meal_client/widget";
    private static final String DISPATCHER_CLASS =
            "pro.hexa.meal.meal_client.BapUWidgetUpdateDispatcher";

    private Context applicationContext;
    private MethodChannel channel;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        applicationContext = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        applicationContext = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (!"refresh".equals(call.method)) {
            result.notImplemented();
            return;
        }

        final Context context = applicationContext;
        if (context == null) {
            result.error("NO_CONTEXT", "Application context is not attached", null);
            return;
        }

        // 위젯 렌더는 캐시 파일 읽기 + JSON 파싱 + 뷰 measure를 포함해 무겁다. MethodChannel
        // 핸들러는 플랫폼(메인) 스레드에서 실행되므로, 백그라운드에서 렌더하고 결과만 메인으로
        // 되돌려 앱 UI 스레드를 막지 않는다. (provider/receiver 경로의 goAsync+Thread와 동일한 모델)
        final Handler mainHandler = new Handler(Looper.getMainLooper());
        new Thread(() -> {
            try {
                Class<?> dispatcherClass = Class.forName(DISPATCHER_CLASS);
                Field instanceField = dispatcherClass.getField("INSTANCE");
                Object dispatcher = instanceField.get(null);
                Method renderAllWidgets = dispatcherClass.getMethod("renderAllWidgets", Context.class);
                renderAllWidgets.invoke(dispatcher, context);
                mainHandler.post(() -> result.success(null));
            } catch (Exception e) {
                mainHandler.post(() -> result.error("RENDER_FAILED", e.getMessage(), null));
            }
        }).start();
    }

    public static void registerWith(@NonNull FlutterEngine flutterEngine) {
        if (!flutterEngine.getPlugins().has(BapUWidgetBridgePlugin.class)) {
            flutterEngine.getPlugins().add(new BapUWidgetBridgePlugin());
        }
    }
}
