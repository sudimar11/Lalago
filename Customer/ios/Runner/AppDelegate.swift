import Flutter
import Network
import UIKit
import Security
import GoogleMaps
import FirebaseCore
import UserNotifications

private let kConnectivityLastCheck = "connectivity_last_check"
private let kConnectivityWasOnline = "connectivity_was_online"

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let debugLogPath =
    "/Users/sudimard/Desktop/customer/.cursor/debug.log"
  private var mapsKeyLength = 0
  private var isMapsKeyEmpty = true
  private var didProvideMapsKey = false
  private var mapsKeyValue = ""

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    let info = Bundle.main.infoDictionary ?? [:]
    let mapsKey = info["GMSApiKey"] as? String ?? ""
    mapsKeyValue = mapsKey
    mapsKeyLength = mapsKey.count
    isMapsKeyEmpty = mapsKey.isEmpty
    // #region agent log
    appendRuntimeDebugLog(
      hypothesisId: "H10",
      location: "AppDelegate.didFinishLaunching:bundleInfo",
      message: "Bundle and device info",
      data: [
        "bundleId": Bundle.main.bundleIdentifier ?? "",
        "isSimulator": {
#if targetEnvironment(simulator)
          return true
#else
          return false
#endif
        }(),
        "systemName": UIDevice.current.systemName,
        "systemVersion": UIDevice.current.systemVersion,
        "model": UIDevice.current.model,
      ]
    )
    // #endregion
    // #region agent log
    appendRuntimeDebugLog(
      hypothesisId: "H6",
      location: "AppDelegate.didFinishLaunching:mapsKey",
      message: "Loaded GMSApiKey from Info.plist",
      data: [
        "isEmpty": mapsKey.isEmpty,
        "length": mapsKey.count,
      ]
    )
    // #endregion
    if !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
      didProvideMapsKey = true
      // #region agent log
      appendRuntimeDebugLog(
        hypothesisId: "H6",
        location: "AppDelegate.didFinishLaunching:provideAPIKey",
        message: "GMSServices.provideAPIKey called",
        data: [
          "called": true,
        ]
      )
      // #endregion
    } else {
      // #region agent log
      appendRuntimeDebugLog(
        hypothesisId: "H6",
        location: "AppDelegate.didFinishLaunching:missingAPIKey",
        message: "GMSApiKey missing from Info.plist",
        data: [
          "called": false,
        ]
      )
      // #endregion
    }
    let mapsStatusPayload: [String: Any] = [
      "length": mapsKey.count,
      "isEmpty": mapsKey.isEmpty,
      "didProvide": didProvideMapsKey,
    ]
    if let jsonData = try? JSONSerialization.data(
      withJSONObject: mapsStatusPayload,
      options: []
    ),
      let jsonString = String(data: jsonData, encoding: .utf8)
    {
      UserDefaults.standard.set(jsonString, forKey: "debug.mapsKeyStatus")
    }
    GeneratedPluginRegistrant.register(with: self)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      let acceptAction = UNNotificationAction(
        identifier: "accept_order",
        title: "Accept",
        options: [.foreground]
      )
      let declineAction = UNNotificationAction(
        identifier: "decline_order",
        title: "Decline",
        options: [.destructive]
      )
      let orderCategory = UNNotificationCategory(
        identifier: "order_notification",
        actions: [acceptAction, declineAction],
        intentIdentifiers: [],
        options: []
      )
      let remindAction = UNNotificationAction(
        identifier: "remind_later",
        title: "Remind Later",
        options: []
      )
      let reminderCategory = UNNotificationCategory(
        identifier: "reminder_notification",
        actions: [remindAction],
        intentIdentifiers: [],
        options: []
      )
      UNUserNotificationCenter.current().setNotificationCategories(
        [orderCategory, reminderCategory]
      )
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "cursor.debug/keychain",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "no_self", message: nil, details: nil))
          return
        }
        if call.method == "check" {
          result(self.keychainStatus())
        } else if call.method == "entitlements" {
          result(self.entitlementsStatus())
        } else if call.method == "mapsKeyStatus" {
          // #region agent log
          self.appendRuntimeDebugLog(
            hypothesisId: "H7",
            location: "AppDelegate.methodChannel:mapsKeyStatus",
            message: "mapsKeyStatus requested by Dart",
            data: [
              "length": self.mapsKeyLength,
              "isEmpty": self.isMapsKeyEmpty,
              "didProvide": self.didProvideMapsKey,
            ]
          )
          // #endregion
          result([
            "length": self.mapsKeyLength,
            "isEmpty": self.isMapsKeyEmpty,
            "didProvide": self.didProvideMapsKey,
          ])
        } else if call.method == "mapsApiKey" {
          result(self.mapsKeyValue)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      let connChannel = FlutterMethodChannel(
        name: "connection_tester/status",
        binaryMessenger: controller.binaryMessenger
      )
      connChannel.setMethodCallHandler { _, result in
        let ts = UserDefaults.standard.double(forKey: kConnectivityLastCheck)
        let online = UserDefaults.standard.bool(forKey: kConnectivityWasOnline)
        result([
          "timestampMs": Int(ts * 1000),
          "wasOnline": online,
        ])
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "connection_tester")
    var didComplete = false
    let complete: (UIBackgroundFetchResult) -> Void = { result in
      queue.async {
        guard !didComplete else { return }
        didComplete = true
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: kConnectivityLastCheck)
        UserDefaults.standard.set(result == .newData, forKey: kConnectivityWasOnline)
        monitor.cancel()
        DispatchQueue.main.async { completionHandler(result) }
      }
    }
    monitor.pathUpdateHandler = { path in
      complete(path.status == .satisfied ? .newData : .noData)
    }
    monitor.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 8) {
      complete(.noData)
    }
  }

  private func keychainStatus() -> [String: Any] {
#if targetEnvironment(simulator)
    NSLog("[SIM_KEYCHAIN_BYPASS] keychainStatus bypass on simulator")
    return [
      "status": 0,
      "message": "simulator bypass",
    ]
#else
    // #region agent log
    appendRuntimeDebugLog(
      hypothesisId: "H1",
      location: "AppDelegate.keychainStatus:entry",
      message: "keychain check started",
      data: [
        "start": true,
      ]
    )
    // #endregion
    let service = "cursor-debug-keychain"
    let account = "keychain-test"
    let data = "ping".data(using: .utf8) ?? Data()
    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: data,
    ]
    SecItemDelete(addQuery as CFDictionary)
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    let addMessage = SecCopyErrorMessageString(addStatus, nil) as String? ?? "unknown"
    SecItemDelete(addQuery as CFDictionary)
    // #region agent log
    appendRuntimeDebugLog(
      hypothesisId: "H1",
      location: "AppDelegate.keychainStatus:result",
      message: "keychain add result",
      data: [
        "status": addStatus,
        "message": addMessage,
      ]
    )
    // #endregion
    return [
      "status": addStatus,
      "message": addMessage,
    ]
#endif
  }

  private func entitlementsStatus() -> [String: Any] {
    // #region agent log
    appendRuntimeDebugLog(
      hypothesisId: "H2",
      location: "AppDelegate.entitlementsStatus:entry",
      message: "entitlements check started",
      data: [
        "start": true,
      ]
    )
    // #endregion
    // NOTE: SecTask/SecCode APIs are unavailable on iOS.
    let data: [String: Any] = [
      "error": "unsupported",
      "message": "Entitlement inspection is unavailable on iOS",
    ]
    // #region agent log
    appendRuntimeDebugLog(
      hypothesisId: "H2",
      location: "AppDelegate.entitlementsStatus:result",
      message: "entitlements check finished",
      data: [
        "hasTaskKeychainGroups": false,
        "hasSignatureEntitlements": false,
      ]
    )
    // #endregion
    return data
  }

  private func appendRuntimeDebugLog(
    hypothesisId: String,
    location: String,
    message: String,
    data: [String: Any]
  ) {
    let payload: [String: Any] = [
      "sessionId": "debug-session",
      "runId": "pre-fix",
      "hypothesisId": hypothesisId,
      "location": location,
      "message": message,
      "data": data,
      "timestamp": Int(Date().timeIntervalSince1970 * 1000),
    ]
    guard JSONSerialization.isValidJSONObject(payload) else {
      return
    }
    guard let jsonData = try? JSONSerialization.data(
      withJSONObject: payload,
      options: []
    ) else {
      return
    }
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: debugLogPath) {
      fileManager.createFile(
        atPath: debugLogPath,
        contents: nil,
        attributes: nil
      )
    }
    guard let handle = FileHandle(forWritingAtPath: debugLogPath) else {
      return
    }
    handle.seekToEndOfFile()
    handle.write(jsonData)
    if let newline = "\n".data(using: .utf8) {
      handle.write(newline)
    }
    handle.closeFile()
  }
}
