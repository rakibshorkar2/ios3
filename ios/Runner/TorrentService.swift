import Flutter
import Foundation

public final class TorrentService: NSObject, FlutterPlugin {
    private static let methodChannel = "com.dirxplore/torrent"
    private static let eventChannel = "com.dirxplore/torrent_events"

    private var eventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        debugPrint("[TorrentService] register() called — setting up MethodChannel/EventChannel")

        let method = FlutterMethodChannel(name: methodChannel, binaryMessenger: registrar.messenger())
        let events = FlutterEventChannel(name: eventChannel, binaryMessenger: registrar.messenger())

        let instance = TorrentService()
        registrar.addMethodCallDelegate(instance, channel: method)
        events.setStreamHandler(instance)

        debugPrint("[TorrentService] register() complete — channels ready, engine NOT initialized")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let manager = TorrentManager.shared
        let args = call.arguments as? [String: Any]

        switch call.method {
        case "initializeEngine":
            manager.initialize()
            result(nil)

        case "shutdownEngine":
            manager.shutdown()
            result(nil)

        case "addMagnet":
            guard let magnet = args?["magnet"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "magnet required", details: nil))
                return
            }
            let savePath = args?["savePath"] as? String ?? NSTemporaryDirectory()
            let id = manager.addMagnet(magnet, savePath: savePath)
            result(id)

        case "addTorrentFile":
            guard let path = args?["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "path required", details: nil))
                return
            }
            let savePath = args?["savePath"] as? String ?? NSTemporaryDirectory()
            let id = manager.addTorrentFile(path, savePath: savePath)
            result(id)

        case "pauseTorrent":
            guard let id = args?["id"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "id required", details: nil))
                return
            }
            manager.pauseTorrent(by: id)
            result(nil)

        case "resumeTorrent":
            guard let id = args?["id"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "id required", details: nil))
                return
            }
            manager.resumeTorrent(by: id)
            result(nil)

        case "removeTorrent":
            guard let id = args?["id"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "id required", details: nil))
                return
            }
            let deleteFiles = args?["deleteFiles"] as? Bool ?? false
            manager.removeTorrent(by: id, deleteFiles: deleteFiles)
            result(nil)

        case "getTorrentList":
            let list = manager.getTorrentList()
            result(list)

        case "getTorrentDetails":
            guard let id = args?["id"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "id required", details: nil))
                return
            }
            if let details = manager.getTorrentDetails(by: id) {
                result(details)
            } else {
                result(FlutterError(code: "NOT_FOUND", message: "Torrent not found", details: nil))
            }

#if DEBUG
        case "runDiagnostics":
            debugPrint("[TorrentService] Diagnostics requested, running integration test")
            manager.runIntegrationTest()
            result("Integration test started, check device logs")
#endif

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

extension TorrentService: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        TorrentManager.shared.setEventSink(events)
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        TorrentManager.shared.setEventSink(nil)
        return nil
    }
}
