import Foundation
import Flutter
import os

enum TorrentState: Int {
    case metadata = 0
    case downloading = 1
    case paused = 2
    case seeding = 3
    case completed = 4
    case error = 5
    case checking = 6
}

final class TorrentManager {
    static let shared = TorrentManager()

    private var cppWrapper: TorrentCppWrapper?
    private var torrents: [String: [String: Any]] = [:]
    private let queue = DispatchQueue(label: "com.dirxplore.torrent.manager", qos: .utility)
    private var eventSinkLock = os_unfair_lock()
    private var _eventSink: FlutterEventSink?
    private var isInitialized = false

    private init() {
        debugPrint("[TorrentManager] Singleton created — engine NOT initialized, no native code loaded")
    }

    func setEventSink(_ sink: FlutterEventSink?) {
        os_unfair_lock_lock(&eventSinkLock)
        _eventSink = sink
        os_unfair_lock_unlock(&eventSinkLock)
    }

    private var eventSink: FlutterEventSink? {
        os_unfair_lock_lock(&eventSinkLock)
        let sink = _eventSink
        os_unfair_lock_unlock(&eventSinkLock)
        return sink
    }

    func initialize() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.isInitialized {
                debugPrint("[TorrentManager] Already initialized, skipping")
                self.emitDebugLog("engine_status", ["status": "already_initialized"])
                return
            }
            let wrapper = TorrentCppWrapper()
            debugPrint("[TorrentManager] Calling initializeSession...")
            let ok = wrapper.initializeSession { [weak self] json in
                self?.handleNativeEvent(json)
            }
            if ok {
                self.cppWrapper = wrapper
                self.isInitialized = true
                debugPrint("[TorrentManager] libtorrent session initialized")
                self.emitDebugLog("engine_status", ["status": "initialized"])
            } else {
                let err = wrapper.lastError() ?? "unknown"
                debugPrint("[TorrentManager] Failed to initialize libtorrent session: \(err)")
                self.emitDebugLog("engine_error", ["error": err, "phase": "initialize"])
            }
        }
    }

    func shutdown() {
        queue.async { [weak self] in
            guard let self else { return }
            self.cppWrapper?.shutdownSession()
            self.cppWrapper = nil
            self.torrents.removeAll()
            self.isInitialized = false
            debugPrint("[TorrentManager] session shut down")
            self.emitDebugLog("engine_status", ["status": "shutdown"])
        }
    }

    @discardableResult
    func addMagnet(_ magnet: String, savePath: String) -> String {
        let id = UUID().uuidString
        debugPrint("[TorrentManager] addMagnet called: id=\(id), magnet=\(magnet.prefix(80))...")
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.cppWrapper?.addMagnet(magnet, savePath: savePath, jobId: id)
            if result == nil {
                debugPrint("[TorrentManager] addMagnet returned nil for \(id)")
                self.emitDebugLog("magnet_error", ["id": id, "error": "cpp_wrapper_returned_nil"])
            } else {
                debugPrint("[TorrentManager] addMagnet submitted: id=\(id)")
                self.emitDebugLog("magnet_added", ["id": id, "magnetPrefix": String(magnet.prefix(60))])
            }
            let info: [String: Any] = [
                "id": id, "name": "Fetching metadata...", "infoHash": "",
                "magnetUri": magnet, "savePath": savePath,
                "state": TorrentState.metadata.rawValue,
                "progress": 0.0, "downloadedBytes": 0, "totalBytes": 0,
                "downloadSpeed": 0.0, "uploadSpeed": 0.0,
                "averageDownloadSpeed": 0.0, "averageUploadSpeed": 0.0,
                "eta": 0, "peers": 0, "seeds": 0, "allPeers": 0,
                "piecesCompleted": 0, "totalPieces": 0,
                "trackers": [String](), "selectedFileIndices": [Int](),
                "isSequential": false, "errorMessage": NSNull(),
                "fileNames": [String](), "fileSizes": [Int](),
            ]
            self.torrents[id] = info
        }
        return id
    }

    @discardableResult
    func addTorrentFile(_ path: String, savePath: String) -> String {
        let id = UUID().uuidString
        debugPrint("[TorrentManager] addTorrentFile called: id=\(id), path=\(path)")
        queue.async { [weak self] in
            guard let self else { return }
            let name = URL(fileURLWithPath: path).lastPathComponent
            let result = self.cppWrapper?.addTorrentFile(path, savePath: savePath, jobId: id)
            if result == nil {
                debugPrint("[TorrentManager] addTorrentFile returned nil for \(id)")
                self.emitDebugLog("torrent_file_error", ["id": id, "path": path, "error": "cpp_wrapper_returned_nil"])
            } else {
                debugPrint("[TorrentManager] addTorrentFile submitted: id=\(id), file=\(name)")
                self.emitDebugLog("torrent_file_added", ["id": id, "fileName": name])
            }
            let info: [String: Any] = [
                "id": id, "name": name, "infoHash": "",
                "magnetUri": "", "savePath": savePath,
                "state": TorrentState.checking.rawValue,
                "progress": 0.0, "downloadedBytes": 0, "totalBytes": 0,
                "downloadSpeed": 0.0, "uploadSpeed": 0.0,
                "averageDownloadSpeed": 0.0, "averageUploadSpeed": 0.0,
                "eta": 0, "peers": 0, "seeds": 0, "allPeers": 0,
                "piecesCompleted": 0, "totalPieces": 0,
                "trackers": [String](), "selectedFileIndices": [Int](),
                "isSequential": false, "errorMessage": NSNull(),
                "fileNames": [String](), "fileSizes": [Int](),
            ]
            self.torrents[id] = info
        }
        return id
    }

    func pauseTorrent(by id: String) {
        debugPrint("[TorrentManager] pauseTorrent: id=\(id)")
        queue.async { [weak self] in
            guard let self else { return }
            self.cppWrapper?.pauseTorrent(id)
            if var info = self.torrents[id] {
                info["state"] = TorrentState.paused.rawValue
                self.torrents[id] = info
                self.emitUpdate(id, info)
            }
        }
    }

    func resumeTorrent(by id: String) {
        debugPrint("[TorrentManager] resumeTorrent: id=\(id)")
        queue.async { [weak self] in
            guard let self else { return }
            self.cppWrapper?.resumeTorrent(id)
            if var info = self.torrents[id] {
                info["state"] = TorrentState.downloading.rawValue
                self.torrents[id] = info
                self.emitUpdate(id, info)
            }
        }
    }

    func removeTorrent(by id: String, deleteFiles: Bool) {
        debugPrint("[TorrentManager] removeTorrent: id=\(id), deleteFiles=\(deleteFiles)")
        queue.async { [weak self] in
            guard let self else { return }
            self.cppWrapper?.removeTorrent(id, deleteFiles: deleteFiles)
            self.torrents.removeValue(forKey: id)
            debugPrint("[TorrentManager] torrent removed: id=\(id)")
            self.emitDebugLog("torrent_removed", ["id": id, "deleteFiles": deleteFiles])
        }
    }

    func getTorrentList() -> [[String: Any]] {
        return Array(torrents.values)
    }

    func getTorrentDetails(by id: String) -> [String: Any]? {
        return torrents[id]
    }

    // MARK: - Event Handling

    private func handleNativeEvent(_ json: String) {
        guard let data = json.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else {
            debugPrint("[TorrentManager] Failed to parse native event JSON")
            return
        }

        debugPrint("[TorrentManager] Native event: type=\(type)")

        switch type {
        case "progress", "completed":
            if let progress = event["progress"] as? [String: Any],
               let jobId = progress["jobId"] as? String {
                debugPrint("[TorrentManager] Progress event for jobId=\(jobId): \(progress["percentComplete"] ?? "?")%")
                updateFromProgress(jobId, progress)
            }
        case "stream_ready":
            if let readiness = event["readiness"] as? [String: Any],
               let jobId = readiness["jobId"] as? String {
                debugPrint("[TorrentManager] Stream ready for jobId=\(jobId)")
                emitDebugLog("stream_ready", ["id": jobId])
            }
        default:
            debugPrint("[TorrentManager] Unknown event type: \(type)")
            emitDebugLog("unknown_event", ["type": type, "payload": String(json.prefix(200))])
        }
    }

    private func updateFromProgress(_ jobId: String, _ progress: [String: Any]) {
        guard var info = torrents[jobId] else {
            debugPrint("[TorrentManager] progress event for unknown jobId: \(jobId)")
            return
        }

        let status = progress["status"] as? String ?? ""
        info["state"] = mapStatus(status)
        info["name"] = progress["name"] as? String ?? info["name"] ?? ""
        info["infoHash"] = progress["infoHash"] as? String ?? ""

        if let total = progress["totalBytes"] as? Int64 {
            info["totalBytes"] = total
        } else if let total = progress["totalBytes"] as? Int {
            info["totalBytes"] = total
        }

        if let completed = progress["bytesCompleted"] as? Int64 {
            info["downloadedBytes"] = completed
        } else if let completed = progress["bytesCompleted"] as? Int {
            info["downloadedBytes"] = completed
        }

        if let pct = progress["percentComplete"] as? Double {
            info["progress"] = pct / 100.0
        }

        info["downloadSpeed"] = progress["bytesPerSecond"] as? Double
            ?? info["downloadSpeed"] ?? 0
        info["peers"] = progress["peerCount"] as? Int
            ?? info["peers"] ?? 0

        torrents[jobId] = info

        debugPrint("[TorrentManager] Updated \(jobId): progress=\(info["progress"] ?? 0), state=\(info["state"] ?? 0), dlSpeed=\(info["downloadSpeed"] ?? 0)")

        if let sink = eventSink {
            sink([
                "event": "torrentUpdate",
                "torrent": info,
            ])
        }
    }

    private func mapStatus(_ status: String) -> Int {
        switch status.lowercased() {
        case "checking", "checking_resume_data": return TorrentState.checking.rawValue
        case "downloading", "downloading_metadata": return TorrentState.downloading.rawValue
        case "downloading_metadata": return TorrentState.metadata.rawValue
        case "finished", "seeding": return TorrentState.seeding.rawValue
        case "completed": return TorrentState.completed.rawValue
        case "paused": return TorrentState.paused.rawValue
        case "error": return TorrentState.error.rawValue
        default: return TorrentState.downloading.rawValue
        }
    }

    private func emitUpdate(_ id: String, _ info: [String: Any]) {
        guard let sink = eventSink else { return }
        sink([
            "event": "torrentUpdate",
            "torrent": info,
        ])
    }

    func emitError(_ message: String) {
        debugPrint("[TorrentManager] Error: \(message)")
        guard let sink = eventSink else { return }
        sink(["event": "error", "message": message])
    }

    private func emitDebugLog(_ logType: String, _ data: [String: Any]) {
#if DEBUG
        guard let sink = eventSink else { return }
        var payload = data
        payload["logType"] = logType
        sink(["event": "debugLog", "data": payload])
#endif
    }

    // MARK: - Debug Integration Test

#if DEBUG
    private static let testMagnet = "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp://tracker.opentrackr.org:1337/announce"

    func runIntegrationTest() {
        guard !isInitialized else {
            debugPrint("[TorrentManager] Integration test: engine already initialized, skipping init")
            runIntegrationTestAddMagnet()
            return
        }

        debugPrint("[TorrentManager] ===== Integration Test Start =====")
        debugPrint("[TorrentManager] Step 1: Initializing torrent engine...")
        emitDebugLog("diagnostic", ["step": "starting_integration_test"])

        let wrapper = TorrentCppWrapper()
        let ok = wrapper.initializeSession { [weak self] json in
            self?.handleIntegrationEvent(json)
        }

        if ok {
            self.cppWrapper = wrapper
            self.isInitialized = true
            debugPrint("[TorrentManager] Integration test: engine initialized successfully")
            emitDebugLog("diagnostic", ["step": "engine_initialized"])
            runIntegrationTestAddMagnet()
        } else {
            let err = wrapper.lastError() ?? "unknown"
            debugPrint("[TorrentManager] Integration test FAILED: engine init error: \(err)")
            emitDebugLog("diagnostic", ["step": "engine_init_failed", "error": err])
        }
    }

    private func runIntegrationTestAddMagnet() {
        let id = "integration-test-\(UUID().uuidString.prefix(8))"
        let savePath = NSTemporaryDirectory()
        debugPrint("[TorrentManager] Step 2: Adding test magnet \(id)...")
        debugPrint("[TorrentManager] Magnet: \(Self.testMagnet.prefix(80))...")
        emitDebugLog("diagnostic", ["step": "adding_magnet", "id": id])

        let result = cppWrapper?.addMagnet(Self.testMagnet, savePath: savePath, jobId: id)
        if result != nil {
            debugPrint("[TorrentManager] Integration test: magnet submitted, id=\(id)")
            debugPrint("[TorrentManager] Waiting for metadata (30s timeout)...")
            emitDebugLog("diagnostic", ["step": "magnet_submitted", "id": id])

            let info: [String: Any] = [
                "id": id, "name": "Integration Test", "infoHash": "",
                "magnetUri": Self.testMagnet, "savePath": savePath,
                "state": TorrentState.metadata.rawValue,
                "progress": 0.0, "downloadedBytes": 0, "totalBytes": 0,
                "downloadSpeed": 0.0, "uploadSpeed": 0.0,
                "averageDownloadSpeed": 0.0, "averageUploadSpeed": 0.0,
                "eta": 0, "peers": 0, "seeds": 0, "allPeers": 0,
                "piecesCompleted": 0, "totalPieces": 0,
                "trackers": [String](), "selectedFileIndices": [Int](),
                "isSequential": false, "errorMessage": NSNull(),
                "fileNames": [String](), "fileSizes": [Int](),
            ]
            torrents[id] = info

            integrationTestId = id
        } else {
            let err = cppWrapper?.lastError() ?? "unknown"
            debugPrint("[TorrentManager] Integration test FAILED: addMagnet error: \(err)")
            emitDebugLog("diagnostic", ["step": "add_magnet_failed", "error": err])
        }
    }

    private var integrationTestId: String?
    private var integrationTestTimer: Timer?

    private func handleIntegrationEvent(_ json: String) {
        guard let data = json.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else {
            return
        }

        debugPrint("[TorrentManager] Integration event: type=\(type)")

        switch type {
        case "progress":
            if let progress = event["progress"] as? [String: Any],
               let jobId = progress["jobId"] as? String {
                let pct = progress["percentComplete"] as? Double ?? 0
                let status = progress["status"] as? String ?? ""
                let name = progress["name"] as? String ?? ""
                debugPrint("[TorrentManager] Integration: jobId=\(jobId), status=\(status), pct=\(pct), name=\(name)")
                emitDebugLog("diagnostic", ["step": "progress_received", "jobId": jobId, "percent": pct, "status": status])

                if !name.isEmpty && name != "Integration Test" {
                    debugPrint("[TorrentManager] Integration test SUCCESS: metadata retrieved, name=\(name)")
                    emitDebugLog("diagnostic", ["step": "metadata_received", "name": name])
                    completeIntegrationTest(jobId, success: true)
                }
            }
        case "completed":
            if let progress = event["progress"] as? [String: Any],
               let jobId = progress["jobId"] as? String {
                debugPrint("[TorrentManager] Integration test: torrent completed for \(jobId)")
                emitDebugLog("diagnostic", ["step": "torrent_completed", "jobId": jobId])
            }
        case "stream_ready":
            if let readiness = event["readiness"] as? [String: Any],
               let jobId = readiness["jobId"] as? String {
                debugPrint("[TorrentManager] Integration test: stream ready for \(jobId)")
                emitDebugLog("diagnostic", ["step": "stream_ready", "jobId": jobId])
            }
        default:
            debugPrint("[TorrentManager] Integration event: unhandled type=\(type), payload=\(String(json.prefix(200)))")
        }
    }

    private func completeIntegrationTest(_ jobId: String, success: Bool) {
        integrationTestTimer?.invalidate()
        integrationTestTimer = nil

        if success {
            debugPrint("[TorrentManager] ===== Integration Test Passed =====")
            emitDebugLog("diagnostic", ["step": "test_passed", "id": jobId])
        } else {
            debugPrint("[TorrentManager] ===== Integration Test Failed =====")
            emitDebugLog("diagnostic", ["step": "test_failed", "id": jobId])
        }

        debugPrint("[TorrentManager] Cleanup: removing torrent \(jobId)")
        cppWrapper?.removeTorrent(jobId, deleteFiles: false)
        torrents.removeValue(forKey: jobId)
        integrationTestId = nil
        debugPrint("[TorrentManager] Integration test cleanup complete")
        emitDebugLog("diagnostic", ["step": "test_cleanup_complete", "id": jobId])
    }
#endif
}
