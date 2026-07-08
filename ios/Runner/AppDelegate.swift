import Flutter
import UIKit
import UserNotifications
import TorrentBridge

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        debugPrint("[AppDelegate] didFinishLaunchingWithOptions — app launching")

        GeneratedPluginRegistrant.register(with: self)

        debugPrint("[AppDelegate] GeneratedPluginRegistrant done, registering DownloadPlugin...")
        if let registrar = self.registrar(forPlugin: "DownloadPlugin") {
            DownloadPlugin.register(with: registrar)
        }

        debugPrint("[AppDelegate] DownloadPlugin done, registering TorrentService...")
        if let registrar = self.registrar(forPlugin: "TorrentService") {
            TorrentService.register(with: registrar)
        }
        debugPrint("[AppDelegate] TorrentService registered (engine NOT initialized)")

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
}
