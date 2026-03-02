import UIKit
import Flutter
import GoogleMaps
import UserNotifications

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("Replace with your API key")
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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
