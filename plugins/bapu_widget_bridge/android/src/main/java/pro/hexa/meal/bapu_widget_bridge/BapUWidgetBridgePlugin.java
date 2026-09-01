package pro.hexa.meal.bapu_widget_bridge;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.NonNull;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.function.Consumer;

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

        // 실제 렌더는 app 모듈의 단일 executor가 맡는다. 여기서는 reflection으로 작업을 넣고
        // 완료 결과만 메인 스레드의 MethodChannel에 전달한다.
        final Handler mainHandler = new Handler(Looper.getMainLooper());
        try {
            Class<?> dispatcherClass = Class.forName(DISPATCHER_CLASS);
            Method enqueue = dispatcherClass.getMethod(
                    "enqueueRenderAllWidgets", Context.class, Consumer.class);
            Consumer<Throwable> completion = failure -> mainHandler.post(() -> {
                if (failure == null) {
                    result.success(null);
                } else {
                    result.error(
                            "RENDER_FAILED",
                            failure.getMessage(),
                            Log.getStackTraceString(failure));
                }
            });
            enqueue.invoke(null, context, completion);
        } catch (Exception error) {
            Throwable cause = unwrapReflectionFailure(error);
            mainHandler.post(() -> result.error(
                    "RENDER_FAILED",
                    cause.getMessage(),
                    Log.getStackTraceString(cause)));
        }
    }

    private static Throwable unwrapReflectionFailure(Throwable error) {
        if (error instanceof InvocationTargetException) {
            Throwable target = ((InvocationTargetException) error).getTargetException();
            if (target != null) return target;
        }
        return error;
    }

    public static void registerWith(@NonNull FlutterEngine flutterEngine) {
        if (!flutterEngine.getPlugins().has(BapUWidgetBridgePlugin.class)) {
            flutterEngine.getPlugins().add(new BapUWidgetBridgePlugin());
        }
    }
}
