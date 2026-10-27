import Flutter
import UIKit
import UserNotifications

/// APNs cihaz jetonu → Flutter ('bambumpos/apns' kanalı, 'jeton' yöntemi).
/// Firebase YOK: sunucu bu jetonla doğrudan APNs'e gönderir.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var jeton: String?
  private var bekleyenler: [FlutterResult] = []
  private var kanal: FlutterMethodChannel?
  /// Uygulama APNs bildirimine dokunularak açıldıysa Flutter hazır olunca okunur.
  private var bekleyenUrl: String?

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
    self.kanal = kanal
    kanal.setMethodCallHandler { [weak self] cagri, sonuc in
      guard let self = self else { return }
      if cagri.method == "acilisUrl" {
        sonuc(self.bekleyenUrl)
        self.bekleyenUrl = nil
        return
      }
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

  /// Uygulama ÖNDEYKEN gelen APNs bildirimi de afiş + ses + rozet olarak görünsün.
  /// (Yerel bildirimler eklentinin kendi ayarıyla — super'e bırakılır.)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if notification.request.trigger is UNPushNotificationTrigger {
      completionHandler([.banner, .list, .sound, .badge])
      return
    }
    super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
  }

  /// APNs bildirimine dokunuldu → payload'daki `url` Flutter'a (ör. /vardiyam → Shift sekmesi).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.trigger is UNPushNotificationTrigger {
      let bilgi = response.notification.request.content.userInfo
      let url = (bilgi["url"] as? String) ?? ((bilgi["data"] as? [String: Any])?["url"] as? String)
      if let u = url, !u.isEmpty {
        // Flutter dinleyicisi henüz kurulmadıysa (soğuk açılış) saklanır;
        // Dart açılışta "acilisUrl" ile okur. Dinleyici yanıt verirse silinir.
        bekleyenUrl = u
        kanal?.invokeMethod("acildi", arguments: u) { [weak self] sonuc in
          if !(sonuc is FlutterError) && (sonuc as? NSObject) !== FlutterMethodNotImplemented {
            self?.bekleyenUrl = nil
          }
        }
      }
      completionHandler()
      return
    }
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    bekleyenler.forEach { $0(nil) }
    bekleyenler.removeAll()
  }
}
