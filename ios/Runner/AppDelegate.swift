import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let sharedStorageChannelName =
    "pro.hexa.meal.meal_client/widget_shared_storage"
  private static let appGroupInfoKey = "BAPU_APP_GROUP_IDENTIFIER"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      AppDelegate.registerSharedStorageChannel(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "bapu_meal_refresh",
      earliestBeginInSeconds: NSNumber(value: 2 * 60 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    Self.registerSharedStorageChannel(with: engineBridge.pluginRegistry)
  }

  private static func registerSharedStorageChannel(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "BapUSharedStorage") else {
      return
    }
    registerSharedStorageChannel(binaryMessenger: registrar.messenger())
  }

  private static func registerSharedStorageChannel(binaryMessenger: FlutterBinaryMessenger) {
    let sharedStorageChannel = FlutterMethodChannel(
      name: sharedStorageChannelName,
      binaryMessenger: binaryMessenger
    )
    sharedStorageChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "appGroupIdentifier":
        guard
          let group = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
          !group.isEmpty
        else {
          result(
            FlutterError(
              code: "APP_GROUP_UNAVAILABLE",
              message: "App Group identifier is missing",
              details: nil
            )
          )
          return
        }
        result(group)
      case "sharedWidgetCacheDir":
        sharedWidgetCacheDir(result: result)
      case "excludeFileFromBackup":
        guard let path = call.arguments as? String, !path.isEmpty else {
          result(
            FlutterError(
              code: "BACKUP_EXCLUSION_PATH_INVALID",
              message: "A cache file path is required",
              details: nil
            )
          )
          return
        }
        excludeFileFromBackup(path: path, result: result)
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

  private static func excludeFileFromBackup(path: String, result: FlutterResult) {
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true

    do {
      var fileURL = URL(fileURLWithPath: path)
      try fileURL.setResourceValues(resourceValues)
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "BACKUP_EXCLUSION_FAILED",
          message: "Could not exclude the widget cache file from backup",
          details: error.localizedDescription
        )
      )
    }
  }
}
