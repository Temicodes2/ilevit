import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let reminderChannel = FlutterMethodChannel(
      name: "com.ilevit/daily_note_reminder",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    reminderChannel.setMethodCallHandler { call, result in
      let notificationCenter = UNUserNotificationCenter.current()
      switch call.method {
      case "requestPermission":
        notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
          DispatchQueue.main.async {
            if let error {
              result(FlutterError(
                code: "notification_permission",
                message: error.localizedDescription,
                details: nil
              ))
            } else {
              result(granted)
            }
          }
        }
      case "scheduleDaily":
        guard
          let arguments = call.arguments as? [String: Int],
          let hour = arguments["hour"],
          let minute = arguments["minute"],
          (0...23).contains(hour),
          (0...59).contains(minute)
        else {
          result(FlutterError(
            code: "invalid_time",
            message: "A valid reminder time is required.",
            details: nil
          ))
          return
        }
        let content = UNMutableNotificationContent()
        content.title = "A little note, a stronger streak"
        content.body = "Take a moment to capture one idea today."
        content.sound = .default
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(
          dateMatching: dateComponents,
          repeats: true
        )
        let request = UNNotificationRequest(
          identifier: "daily_note_reminder",
          content: content,
          trigger: trigger
        )
        notificationCenter.add(request) { error in
          DispatchQueue.main.async {
            if let error {
              result(FlutterError(
                code: "schedule_failed",
                message: error.localizedDescription,
                details: nil
              ))
            } else {
              result(nil)
            }
          }
        }
      case "cancelDaily":
        notificationCenter.removePendingNotificationRequests(
          withIdentifiers: ["daily_note_reminder"]
        )
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
