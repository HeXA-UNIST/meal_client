import Flutter
import UIKit
import WidgetKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let widgetChannelName = "pro.hexa.meal.meal_client/widget"
  private static let sharedStorageChannelName =
    "pro.hexa.meal.meal_client/widget_shared_storage"
  private static let appGroupInfoKey = "BAPU_APP_GROUP_IDENTIFIER"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    GeneratedPluginRegistrant.register(with: self)
    Self.registerBapUWidgetChannels(with: self)
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      Self.registerBapUWidgetChannels(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "bapu_meal_refresh",
      frequency: NSNumber(value: 15 * 60) // 15 minutes (minimum)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    Self.registerBapUWidgetChannels(with: engineBridge.pluginRegistry)
  }

  private static func registerBapUWidgetChannels(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "BapUWidgetBridge") else {
      return
    }
    registerBapUWidgetChannels(binaryMessenger: registrar.messenger())
  }

  private static func registerBapUWidgetChannels(binaryMessenger: FlutterBinaryMessenger) {
    let widgetChannel = FlutterMethodChannel(
      name: widgetChannelName,
      binaryMessenger: binaryMessenger
    )
    widgetChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "refresh":
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let sharedStorageChannel = FlutterMethodChannel(
      name: sharedStorageChannelName,
      binaryMessenger: binaryMessenger
    )
    sharedStorageChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "sharedWidgetCacheDir":
        sharedWidgetCacheDir(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func sharedWidgetCacheDir(result: FlutterResult) {
    guard
      let appGroupIdentifier = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey)
        as? String,
      !appGroupIdentifier.isEmpty
    else {
      result(
        FlutterError(
          code: "APP_GROUP_IDENTIFIER_MISSING",
          message: "BAPU_APP_GROUP_IDENTIFIER is not configured",
          details: nil
        )
      )
      return
    }

    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      )
    else {
      result(
        FlutterError(
          code: "APP_GROUP_CONTAINER_UNAVAILABLE",
          message: "App Group container is not available",
          details: appGroupIdentifier
        )
      )
      return
    }

    result(containerURL.path)
  }
}
