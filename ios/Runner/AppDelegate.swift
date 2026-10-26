import Flutter
import UIKit
import UserNotifications

/// APNs cihaz jetonu → Flutter ('bambumpos/apns' kanalı, 'jeton' yöntemi).
/// Firebase YOK: sunucu bu jetonla doğrudan APNs'e gönderir.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var jeton: String?
  private var bekleyenler: [FlutterResult] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let kayit = engineBridge.pluginRegistry.registrar(forPlugin: "BamBumApnsJeton") else { return }
    let kanal = FlutterMethodChannel(name: "bambumpos/apns", binaryMessenger: kayit.messenger())
    kanal.setMethodCallHandler { [weak self] cagri, sonuc in
      guard let self = self else { return }
      guard cagri.method == "jeton" else { sonuc(FlutterMethodNotImplemented); return }
      if let j = self.jeton { sonuc(j); return }
      self.bekleyenler.append(sonuc)
      DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
    }
  }

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let j = deviceToken.map { String(format: "%02x", $0) }.joined()
    jeton = j
    bekleyenler.forEach { $0(j) }
    bekleyenler.removeAll()
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    bekleyenler.forEach { $0(nil) }
    bekleyenler.removeAll()
  }
}
