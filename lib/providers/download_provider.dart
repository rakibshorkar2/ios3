import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:disk_space_2/disk_space_2.dart';
import '../models/download_item.dart';
import '../services/dio_client.dart';
import '../services/html_parser.dart';
import '../services/database_helper.dart';
import '../services/torrent_download_service.dart';
import '../models/torrent_task_model.dart';
import '../models/directory_item.dart';

class DownloadProvider with ChangeNotifier {
  static const MethodChannel _channel =
      MethodChannel('com.example.dirBrowser/downloads');
  static const MethodChannel _iosChannel =
      MethodChannel('com.dirxplore/ios_download');
  static const EventChannel _iosEvents =
      EventChannel('com.dirxplore/ios_download_events');
  static const MethodChannel _liveActivityChannel =
      MethodChannel('com.dirxplore/live_activity');
  static const EventChannel _liveActivityErrorChannel =
      EventChannel('com.dirxplore/live_activity_errors');
  static const MethodChannel _iosNotificationChannel =
      MethodChannel('com.dirxplore/notifications');
  static const MethodChannel _backgroundServiceChannel =
      MethodChannel('com.dirxplore/background_services');
  StreamSubscription? _iosEventSub;
  StreamSubscription? _liveActivityErrorSub;

  final bool _isIOS = Platform.isIOS;

  final List<DownloadItem> _queue = [];
  final Map<String, CancelToken> _cancelTokens = {};
  int _maxConcurrent = 3;
  int _activeCount = 0;
  DateTime _lastNotifyTime = DateTime.now();
  DateTime _lastSaveTime = DateTime.now();
  double _totalStorage = 0;
  double _freeStorage = 0;
  bool _isProcessingQueue = false;
  void Function()? onAllDownloadsComplete;

  bool _backgroundServicesRunning = false;

  // Proxy settings for torrent downloads
  bool _torrentProxyEnabled = false;
  String? _torrentProxyHost;
  int? _torrentProxyPort;
  String? _torrentProxyUser;
  String? _torrentProxyPass;

  void setTorrentProxySettings(bool enabled, {String? host, int? port, String? username, String? password}) {
    _torrentProxyEnabled = enabled;
    _torrentProxyHost = host;
    _torrentProxyPort = port;
    _torrentProxyUser = username;
    _torrentProxyPass = password;
  }

  double get totalStorage => _totalStorage;
  double get freeStorage => _freeStorage;

  Future<void> updateStorageInfo() async {
    try {
      _totalStorage = await DiskSpace.getTotalDiskSpace ?? 0;
      _freeStorage = await DiskSpace.getFreeDiskSpace ?? 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Storage update error: $e');
    }
  }

  // Selection State
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  List<DownloadItem> get queue => _queue;
  Set<String> get selectedIds => _selectedIds;
  bool get isSelectionMode => _isSelectionMode;

  Future<void> init() async {
    await _loadQueue();
    await updateStorageInfo();
    _channel.setMethodCallHandler(_handleNotificationAction);

    if (_isIOS) {
      _iosEventSub = _iosEvents.receiveBroadcastStream().listen(_handleiOSEvent);
      _liveActivityErrorSub = _liveActivityErrorChannel.receiveBroadcastStream().listen((event) {
        debugPrint('Live Activity error: $event');
      });
      _iosChannel.invokeMethod('getSavePath').then((path) {
        if (path is String) {
          debugPrint('iOS save path: $path');
        }
      }).catchError((e) { debugPrint('Channel method error: $e'); });
      enableLiveActivity();
    }
  }

  void _handleiOSEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'] as String?;
    final downloadId = event['downloadId'] as String?;
    if (downloadId == null) return;

    final item = _queue.firstWhere(
      (i) => i.id == downloadId,
      orElse: () => DownloadItem(id: '', url: '', fileName: '', savePath: ''),
    );
    if (item.id.isEmpty) return;

    switch (type) {
      case 'started':
        item.status = DownloadStatus.downloading;
        notifyListeners();
        break;
      case 'restored':
        _activeCount++;
        item.status = DownloadStatus.downloading;
        notifyListeners();
        break;
      case 'progress':
        final received = event['received'] as int? ?? 0;
        final total = event['total'] as int? ?? 0;
        final dt = DateTime.now();
        if (item.downloadedBytes > 0) {
          final diff = received - item.downloadedBytes;
          final timeDiff = dt.difference(_lastNotifyTime).inMilliseconds;
          if (timeDiff > 0) {
            item.speedBytesPerSec = (item.speedBytesPerSec * 0.7) + ((diff / (timeDiff / 1000)) * 0.3);
          }
        }
        item.downloadedBytes = received;
        item.totalBytes = total;
        if (item.speedBytesPerSec > 0 && total > 0) {
          item.etaSeconds = ((total - received) / item.speedBytesPerSec).round();
        }
        if (dt.difference(_lastNotifyTime).inMilliseconds > 250) {
          _lastNotifyTime = dt;
          notifyListeners();
        }
        DatabaseHelper().updateDownload(item);
        break;
      case 'completed':
        item.status = DownloadStatus.done;
        item.speedBytesPerSec = 0;
        item.etaSeconds = 0;
        item.downloadedBytes = item.totalBytes;
        if (_activeCount > 0) _activeCount--;
        final savePath = event['savePath'] as String?;
        if (savePath != null) {
          item.savePath = savePath;
        }
        DatabaseHelper().updateDownload(item);
        updateStorageInfo();
        notifyListeners();
        _processQueue();
        break;
      case 'paused':
        item.status = DownloadStatus.paused;
        item.speedBytesPerSec = 0;
        if (_activeCount > 0) _activeCount--;
        DatabaseHelper().updateDownload(item);
        notifyListeners();
        _processQueue();
        break;
      case 'cancelled':
        _queue.removeWhere((i) => i.id == downloadId);
        DatabaseHelper().deleteDownload(downloadId);
        if (_activeCount > 0) _activeCount--;
        if (_activeCount == 0) _stopForegroundIfNoActive();
        notifyListeners();
        _processQueue();
        break;
      case 'error':
        item.status = DownloadStatus.error;
        item.errorMessage = event['message'] as String? ?? 'Download failed';
        if (_activeCount > 0) _activeCount--;
        DatabaseHelper().updateDownload(item);
        notifyListeners();
        _processQueue();
        break;
      case 'resumed':
        item.status = DownloadStatus.downloading;
        notifyListeners();
        break;
    }
    _syncLiveActivityState();
  }

  @override
  void dispose() {
    _iosEventSub?.cancel();
    super.dispose();
  }

  Future<void> _handleNotificationAction(MethodCall call) async {
    if (call.method == 'onNotificationAction') {
      final String action = call.arguments['action'];
      // final int notificationId = call.arguments['id']; // Unused for now as we use fixed ID 1001

      // For now, we assume 1001 is the active download.
      // In a multi-notification setup, we'd map notificationId to download ID.
      // Since currently startForegroundService uses a fixed ID 1001:
      final activeItem = _queue.firstWhere(
        (i) => i.status == DownloadStatus.downloading,
        orElse: () => DownloadItem(id: '', url: '', fileName: '', savePath: ''),
      );

      if (activeItem.id.isNotEmpty) {
        if (action == 'pause') {
          pause(activeItem.id);
        } else if (action == 'resume') {
          resume(activeItem.id);
        } else if (action == 'cancel') {
          stop(activeItem.id);
        }
      }
    }
  }

  Future<void> _loadQueue() async {
    _queue.clear();
    _activeCount = 0;
    _queue.addAll(await DatabaseHelper().getDownloads());
    final engine = TorrentEngineService();
    for (final item in _queue) {
      if (item.status == DownloadStatus.downloading) {
        if (item.isTorrent) {
          await engine.restoreTask(item.id);
          _activeCount++;
        } else {
          item.status = DownloadStatus.queued;
          await DatabaseHelper().updateDownload(item);
        }
      }
    }
    notifyListeners();
    _processQueue();
  }

  Future<void> _saveQueue() async {
    // With SQLite, we update items individually.
    // This method can remain as a legacy call or trigger bulk sync if needed.
  }

  void setMaxConcurrent(int max) {
    _maxConcurrent = max;
    _processQueue();
  }

  Future<void> addDownload(String url, String fileName, String saveDir,
      {String? batchId, String? batchName}) async {
    // Check if exactly identical item exists in queue
    if (_queue.any((i) => i.url == url)) {
      final existing = _queue.firstWhere((i) => i.url == url);
      if (existing.status == DownloadStatus.paused ||
          existing.status == DownloadStatus.error) {
        resume(existing.id);
      }
      return;
    }

    final id = '${DateTime.now().millisecondsSinceEpoch}_${url.hashCode}';

    // Route magnet links to torrent download path
    if (url.startsWith('magnet:')) {
      await addTorrentDownload(url, fileName, saveDir,
          batchId: batchId, batchName: batchName);
      return;
    }

    // Apply Smart Folder Routing if enabled
    String finalSaveDir = saveDir;
    final prefs = await SharedPreferences.getInstance();
    final bool smartRouting = prefs.getBool('smartFolderRouting') ?? false;

    if (smartRouting) {
      final ext = fileName.split('.').last.toLowerCase();
      if (['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext)) {
        finalSaveDir = p.join(saveDir, 'Movies');
      } else if (['iso', 'rar', 'zip', '7z'].contains(ext)) {
        finalSaveDir = p.join(saveDir, 'Games');
      } else if (['apk'].contains(ext)) {
        finalSaveDir = p.join(saveDir, 'Apps');
      } else if (['mp3', 'flac', 'wav'].contains(ext)) {
        finalSaveDir = p.join(saveDir, 'Music');
      } else {
        finalSaveDir = p.join(saveDir, 'Others');
      }
    }

    // NEW: Create subfolder if batchName is provided
    if (batchName != null && batchName.trim().isNotEmpty) {
      finalSaveDir = p.join(finalSaveDir, batchName.trim());
    }

    final savePath = p.join(finalSaveDir, fileName);

    // Resume logic: if file already exists on disk (even if not in queue),
    // we want to attempt resuming. Wait, addDownload just adds to queue.
    // We will handle existing bytes in `_startDownload` where we actually check the disk.

    _queue.add(DownloadItem(
      id: id,
      url: url,
      fileName: fileName,
      savePath: savePath,
      batchId: batchId,
      batchName: batchName,
    ));

    await DatabaseHelper().insertDownload(_queue.last);
    await updateStorageInfo();
    notifyListeners();
    _processQueue();
  }

  Future<void> addTorrentDownload(
    String url,
    String fileName,
    String saveDir, {
    String? batchId,
    String? batchName,
    String? torrentHash,
    String? torrentDisplayName,
    String? torrentTrackers,
    List<int>? selectedFileIndices,
    bool isSequential = false,
  }) async {
    if (_queue.any((i) => i.url == url)) {
      final existing = _queue.firstWhere((i) => i.url == url);
      if (existing.status == DownloadStatus.paused ||
          existing.status == DownloadStatus.error) {
        resume(existing.id);
      }
      return;
    }

    final id = '${DateTime.now().millisecondsSinceEpoch}_${url.hashCode}';
    final finalSaveDir = saveDir;
    final savePath = p.join(finalSaveDir, fileName);

    _queue.add(DownloadItem(
      id: id,
      url: url,
      fileName: fileName,
      savePath: savePath,
      batchId: batchId,
      batchName: batchName,
      downloadType: DownloadType.torrent,
      torrentHash: torrentHash,
      torrentDisplayName: torrentDisplayName,
      torrentTrackers: torrentTrackers,
      selectedFileIndices: selectedFileIndices ?? [],
      isSequential: isSequential,
    ));

    await DatabaseHelper().insertDownload(_queue.last);
    await updateStorageInfo();
    notifyListeners();
    _processQueue();
  }

  Future<List<DirectoryItem>> crawlFolder(
      String folderUrl, String folderName) async {
    final List<DirectoryItem> allItems = [];
    await _crawlRecursive(folderUrl, allItems);
    return allItems;
  }

  Future<void> _crawlRecursive(
      String folderUrl, List<DirectoryItem> results) async {
    try {
      final dio = DioClient().dio;
      final response = await dio.get(folderUrl);
      final htmlStr = response.data.toString();
      final items =
          await HtmlParserService.parseApacheDirectoryAsync(htmlStr, folderUrl);

      for (var item in items) {
        if (item.isDirectory) {
          await _crawlRecursive(item.url, results);
        } else {
          results.add(item);
        }
      }
    } catch (e) {
      debugPrint("Crawl error: $e");
    }
  }

  void addRecursiveDownload(
      String folderUrl, String folderName, String baseSaveDir) async {
    // Legacy support: auto-queueing movies/subs
    final items = await crawlFolder(folderUrl, folderName);
    final batchId = DateTime.now().millisecondsSinceEpoch.toString();

    for (var item in items) {
      final ext = item.name.split('.').last.toLowerCase();
      if (['mp4', 'mkv', 'avi', 'mov', 'webm', 'srt', 'vtt', 'sub']
          .contains(ext)) {
        addDownload(item.url, item.name, baseSaveDir,
            batchId: batchId, batchName: folderName);
      }
    }
  }

  void pause(String id) {
    if (!_queue.any((i) => i.id == id)) return;
    final item = _queue.firstWhere((i) => i.id == id);

    if (item.status == DownloadStatus.downloading) {
      if (item.isTorrent) {
        TorrentEngineService().pauseTask(id);
      } else {
        _cancelTokens[id]?.cancel('Paused by user');
        _cancelTokens.remove(id);
      }
      item.status = DownloadStatus.paused;
      item.speedBytesPerSec = 0;
      notifyListeners();
    } else {
      item.status = DownloadStatus.paused;
      item.speedBytesPerSec = 0;
      _saveQueue();
      updateStorageInfo();
      notifyListeners();
    }
    _syncLiveActivityState();
  }

  void _stopForegroundIfNoActive() {
    if (_activeCount <= 1) {
      // 1 because we are about to decrement
      _channel.invokeMethod(
          'stopForegroundService', {'id': 1001}).catchError((e) { debugPrint('Channel method error: $e'); });
    }
  }

  void resume(String id) {
    final item = _queue.firstWhere((i) => i.id == id);
    if (item.isTorrent && item.status == DownloadStatus.paused) {
      TorrentEngineService().resumeTask(id);
      item.status = DownloadStatus.downloading;
      item.speedBytesPerSec = 0;
      _saveQueue();
      notifyListeners();
      _syncLiveActivityState();
      return;
    }
    item.status = DownloadStatus.queued;
    item.errorMessage = null;
    _saveQueue();
    notifyListeners();
    _processQueue();
    _syncLiveActivityState();
  }

  void stop(String id) {
    if (!_queue.any((i) => i.id == id)) return;
    final item = _queue.firstWhere((i) => i.id == id);

    if (item.status == DownloadStatus.downloading) {
      if (item.isTorrent) {
        TorrentEngineService().stopTask(id);
      } else {
        _cancelTokens[id]?.cancel('Stopped by user');
        _cancelTokens.remove(id);
      }
    }

    _queue.removeWhere((i) => i.id == id);
    DatabaseHelper().deleteDownload(id);
    _saveQueue();
    updateStorageInfo();
    notifyListeners();
    _syncLiveActivityState();
  }

  void resumeBatch(String batchId) {
    bool hasResumed = false;
    for (var i in _queue) {
      if (i.batchId == batchId &&
          (i.status == DownloadStatus.paused ||
              i.status == DownloadStatus.error)) {
        i.status = DownloadStatus.queued;
        i.errorMessage = null;
        DatabaseHelper().updateDownload(i);
        hasResumed = true;
      }
    }
    if (hasResumed) {
      _saveQueue();
      notifyListeners();
      _processQueue();
      _syncLiveActivityState();
    }
  }

  void pauseBatch(String batchId) {
    bool hasPaused = false;
    for (var i in _queue) {
      if (i.batchId == batchId) {
        if (i.status == DownloadStatus.downloading) {
          _cancelTokens[i.id]?.cancel('Paused by user');
          _cancelTokens.remove(i.id);
          i.status = DownloadStatus.paused;
          i.speedBytesPerSec = 0;
          hasPaused = true;
        } else if (i.status == DownloadStatus.queued) {
          i.status = DownloadStatus.paused;
          hasPaused = true;
        }
        DatabaseHelper().updateDownload(i);
      }
    }
    if (hasPaused) {
      _saveQueue();
      notifyListeners();
      _syncLiveActivityState();
    }
  }

  void stopBatch(String batchId) {
    final batchItems = _queue.where((i) => i.batchId == batchId).toList();
    for (var i in batchItems) {
      if (i.status == DownloadStatus.downloading) {
        if (i.isTorrent) {
          TorrentEngineService().stopTask(i.id);
        } else {
          _cancelTokens[i.id]?.cancel('Stopped by user');
          _cancelTokens.remove(i.id);
        }
      }
      DatabaseHelper().deleteDownload(i.id);
    }
    _queue.removeWhere((i) => i.batchId == batchId);
    _saveQueue();
    updateStorageInfo();
    notifyListeners();
    _syncLiveActivityState();
  }

  void clearDone() {
    _queue.removeWhere((i) =>
        i.status == DownloadStatus.done || i.status == DownloadStatus.error);
    _saveQueue();
    updateStorageInfo();
    notifyListeners();
    _syncLiveActivityState();
  }

  void clearAll() {
    for (final token in _cancelTokens.values) {
      token.cancel('Cleared');
    }
    _cancelTokens.clear();
    _queue.clear();
    _activeCount = 0;
    _isSelectionMode = false;
    _selectedIds.clear();
    _saveQueue();
    updateStorageInfo();
    notifyListeners();
    _syncLiveActivityState();
  }

  // --- Selection Features ---

  void toggleSelectionMode() {
    _isSelectionMode = !_isSelectionMode;
    if (!_isSelectionMode) {
      _selectedIds.clear();
    }
    notifyListeners();
  }

  void toggleSelection(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _selectedIds.add(id);
      _isSelectionMode = true;
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedIds.clear();
    _selectedIds.addAll(_queue.map((e) => e.id));
    _isSelectionMode = true;
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    _isSelectionMode = false;
    notifyListeners();
  }

  void deleteSelected({bool deleteFiles = false}) {
    for (String id in _selectedIds) {
      final item = _queue.firstWhere((i) => i.id == id, orElse: () => DownloadItem(id: '', url: '', fileName: '', savePath: ''));
      if (item.id.isNotEmpty && item.isTorrent) {
        TorrentEngineService().stopTask(id);
      } else {
        _cancelTokens[id]?.cancel('Deleted by user');
        _cancelTokens.remove(id);
      }

      if (deleteFiles) {
        final itemIndex = _queue.indexWhere((i) => i.id == id);
        if (itemIndex != -1) {
          final f = File(_queue[itemIndex].savePath);
          if (f.existsSync()) {
            f.deleteSync();
          }
        }
      }

      _queue.removeWhere((i) => i.id == id);
    }

    // Recalculate active count if we deleted running items
    _activeCount =
        _queue.where((i) => i.status == DownloadStatus.downloading).length;
    if (_activeCount == 0) {
      _stopForegroundIfNoActive();
    }

    _selectedIds.clear();
    _isSelectionMode = false;
    _saveQueue();
    updateStorageInfo();
    notifyListeners();
    _processQueue();
  }

  void pauseAll() {
    // 1. Cancel all active HTTP transfers
    for (final id in _cancelTokens.keys.toList()) {
      _cancelTokens[id]?.cancel('Paused by user');
      _cancelTokens.remove(id);
    }
    // 2. Pause all active torrent transfers
    for (final item in _queue) {
      if (item.isTorrent && item.status == DownloadStatus.downloading) {
        TorrentEngineService().pauseTask(item.id);
      }
    }

    // 3. Set all queued/downloading items to paused
    for (final item in _queue) {
      if (item.status == DownloadStatus.queued ||
          item.status == DownloadStatus.downloading) {
        item.status = DownloadStatus.paused;
        item.speedBytesPerSec = 0;
      }
    }

    _activeCount = 0;
    _stopForegroundIfNoActive();
    _saveQueue();
    notifyListeners();
    _syncLiveActivityState();
  }

  void resumeAll() {
    for (final item in _queue) {
      if (item.status == DownloadStatus.paused ||
          item.status == DownloadStatus.error) {
        resume(item.id);
      }
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final wifiOnly = prefs.getBool('downloadOnWifiOnly') == true;
      final lowBatteryPause = prefs.getBool('pauseLowBattery') == true;
      _maxConcurrent = prefs.getInt('maxConcurrent') ?? 1;

      while (_activeCount < _maxConcurrent) {
        final nextItem = _queue.firstWhere(
          (i) => i.status == DownloadStatus.queued,
          orElse: () =>
              DownloadItem(id: '', url: '', fileName: '', savePath: ''),
        );

        if (nextItem.id.isEmpty) break; // Nothing to download

        // 1. Wi-Fi Check
        if (wifiOnly) {
          var connectivityResult = await (Connectivity().checkConnectivity());
          if (!connectivityResult.contains(ConnectivityResult.wifi)) {
            nextItem.status = DownloadStatus.paused;
            nextItem.errorMessage = 'Paused: Waiting for Wi-Fi';
            DatabaseHelper().updateDownload(nextItem);
            notifyListeners();
            continue;
          }
        }

        // 2. Battery Check
        if (lowBatteryPause) {
          final battery = Battery();
          final level = await battery.batteryLevel;
          if (level < 15) {
            nextItem.status = DownloadStatus.paused;
            nextItem.errorMessage = 'Paused: Battery below 15%';
            DatabaseHelper().updateDownload(nextItem);
            notifyListeners();
            continue;
          }
        }

        if (nextItem.isTorrent) {
          _startTorrentDownload(nextItem);
        } else {
          _startDownload(nextItem);
        }
      }
    } finally {
      _isProcessingQueue = false;
      _syncLiveActivityState();
    }
  }

  Future<void> _startTorrentDownload(DownloadItem item) async {
    _activeCount++;
    item.status = DownloadStatus.downloading;
    notifyListeners();
    await DatabaseHelper().updateDownload(item);

    final engine = TorrentEngineService();
    if (_torrentProxyEnabled && _torrentProxyHost != null) {
      engine.setProxySettings(
        host: _torrentProxyHost!,
        port: _torrentProxyPort ?? 1080,
      );
    }

    final stream = engine.startTask(item,
      isSequential: item.isSequential,
    );

    stream.listen(
      (tm) {
        item.downloadedBytes = tm.downloadedBytes;
        item.totalBytes = tm.totalBytes;
        item.speedBytesPerSec = tm.downloadSpeed;
        item.uploadSpeedBytesPerSec = tm.uploadSpeed;
        item.etaSeconds = tm.etaSeconds;
        item.torrentSeeders = tm.seeders;
        item.torrentPeers = tm.peers;
        item.torrentAllPeers = tm.allPeers;
        item.averageDownloadSpeed = tm.averageDownloadSpeed;
        item.errorMessage = tm.errorMessage;
        notifyListeners();
        DatabaseHelper().updateDownload(item);

        if (tm.state == TorrentTaskState.completed) {
          item.status = DownloadStatus.done;
          item.speedBytesPerSec = 0;
          item.uploadSpeedBytesPerSec = 0;
          item.etaSeconds = 0;
          if (_activeCount > 0) _activeCount--;
          DatabaseHelper().updateDownload(item);
          updateStorageInfo();
          notifyListeners();
          _processQueue();
        } else if (tm.state == TorrentTaskState.error) {
          item.status = DownloadStatus.error;
          item.errorMessage = tm.errorMessage ?? 'Torrent error';
          if (_activeCount > 0) _activeCount--;
          DatabaseHelper().updateDownload(item);
          notifyListeners();
          _processQueue();
        }
      },
      onError: (error) {
        item.status = DownloadStatus.error;
        item.errorMessage = error.toString();
        if (_activeCount > 0) _activeCount--;
        DatabaseHelper().updateDownload(item);
        notifyListeners();
        _processQueue();
      },
    );
  }

  bool _isSequentialForMedia(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['mp4', 'mkv', 'avi', 'mov', 'webm', 'ts', 'm4v'].contains(ext);
  }

  Future<void> _startDownload(DownloadItem item) async {
    _activeCount++;
    item.status = DownloadStatus.downloading;
    notifyListeners();
    await DatabaseHelper().updateDownload(item);
    _showiOSNotification("Download Started", item.fileName);

    // Start Foreground Service (Android only)
    if (!_isIOS) {
      _channel.invokeMethod('startForegroundService', {
        'url': item.url,
        'filename': item.fileName,
        'id': 1001,
      }).catchError((e) { debugPrint('Channel method error: $e'); });
    }

    final cancelToken = CancelToken();
    _cancelTokens[item.id] = cancelToken;

    final file = File(item.savePath);
    // Ensure parent directory exists for organized downloads
    final parentDir = file.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // TRUST PERSISTED PROGRESS: file.length() is unreliable due to pre-allocation
    // Actually, if file exists and we are starting, we can check its size to resume.
    if (!await file.exists()) {
      item.downloadedBytes = 0;
    } else {
      // If the file exists but downloadedBytes in queue is 0 (e.g., added a new link for an existing file),
      // we check the file size on disk and use it to resume.
      if (item.downloadedBytes == 0) {
        item.downloadedBytes = await file.length();
      }
    }
    int existingBytes = item.downloadedBytes;

    try {
      final dio = DioClient().dio;
      final headResponse = await dio.head(item.url);
      final totalHeader =
          headResponse.headers.value(HttpHeaders.contentLengthHeader) ?? '-1';
      final total = int.tryParse(totalHeader) ?? -1;
      item.totalBytes = total;

      // Check if already fully downloaded based on disk size
      if (existingBytes > 0 && total > 0 && existingBytes >= total) {
        item.status = DownloadStatus.done;
        item.speedBytesPerSec = 0;
        item.etaSeconds = 0;
        item.downloadedBytes = total;
        item.totalBytes = total;
        _cancelTokens.remove(item.id);
        await updateStorageInfo();
        _showiOSNotification("Download Complete", item.fileName);

        if (!_isIOS) {
          _channel.invokeMethod('stopForegroundService', {
            'id': 1001,
            'filename': item.fileName,
            'success': true,
          }).catchError((e) { debugPrint('Channel method error: $e'); });
        }

        // Finalize state
        if (_activeCount > 0) {
          _stopForegroundIfNoActive();
          _activeCount--;
        }
        await DatabaseHelper().updateDownload(item);
        notifyListeners();
        _processQueue();
        return; // Early return for completed file
      }

      await _downloadSingle(item, existingBytes, cancelToken);

      item.status = DownloadStatus.done;
      item.speedBytesPerSec = 0;
      item.etaSeconds = 0;
      item.downloadedBytes = item.totalBytes;
      _cancelTokens.remove(item.id);
      await updateStorageInfo();

      if (!_isIOS) {
        _channel.invokeMethod('stopForegroundService', {
          'id': 1001,
          'filename': item.fileName,
          'success': true,
        }).catchError((e) { debugPrint('Channel method error: $e'); });
      }
    } catch (e) {
      _handleDownloadError(item, e);
    } finally {
      if (!_isIOS) {
        _stopForegroundIfNoActive();
      }
      if (_activeCount > 0) {
        _activeCount--;
      }
      await DatabaseHelper().updateDownload(item);
      notifyListeners();
      _processQueue();
    }
  }

  Future<void> _downloadSingle(
      DownloadItem item, int existingBytes, CancelToken cancelToken) async {
    final dio = DioClient().dio;
    final file = File(item.savePath);
    item.downloadedBytes = existingBytes; // SYNC WITH DISK START

    final response = await dio.get<ResponseBody>(
      item.url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: existingBytes > 0 ? {'Range': 'bytes=$existingBytes-'} : null,
      ),
    );

    // CRITICAL: For pre-allocated files, FileMode.append is WRONG.
    // It will append to the END of the pre-allocated (full size) file.
    // We must use 'write' or 'r+' and set position manually.
    final raf = file.openSync(mode: FileMode.append);
    if (existingBytes > 0) {
      raf.setPositionSync(existingBytes);
    }
    final stream = response.data!.stream;

    DateTime lastUpdate = DateTime.now();
    int bytesSinceUpdate = 0;

    await for (final chunk in stream) {
      if (cancelToken.isCancelled) break;
      raf.writeFromSync(chunk);
      item.downloadedBytes += chunk.length;
      bytesSinceUpdate += chunk.length;

      final now = DateTime.now();
      if (now.difference(lastUpdate).inMilliseconds >= 500) {
        _updateProgress(
            item, bytesSinceUpdate, now.difference(lastUpdate).inMilliseconds);
        lastUpdate = now;
        bytesSinceUpdate = 0;
      }
    }
    raf.closeSync();
  }

  void _updateProgress(
      DownloadItem item, int bytesSinceLastUpdate, int diffMs) {
    if (diffMs == 0) return;

    // Smooth out speed calculation
    double currentSpeed = (bytesSinceLastUpdate / (diffMs / 1000)).toDouble();
    if (item.speedBytesPerSec == 0) {
      item.speedBytesPerSec = currentSpeed;
    } else {
      item.speedBytesPerSec =
          (item.speedBytesPerSec * 0.7) + (currentSpeed * 0.3);
    }

    if (item.speedBytesPerSec > 0 && item.totalBytes > 0) {
      final remaining = item.totalBytes - item.downloadedBytes;
      item.etaSeconds = (remaining / item.speedBytesPerSec).round();
    }

    int progressPercent = 0;
    if (item.totalBytes > 0) {
      progressPercent =
          ((item.downloadedBytes / item.totalBytes) * 100).toInt();
    }

    _channel.invokeMethod('updateProgress', {
      'id': 1001,
      'progress': progressPercent,
      'speed':
          '${(item.speedBytesPerSec / 1024 / 1024).toStringAsFixed(2)} MB/s',
      'filename': item.fileName,
      'eta': _formatDuration(item.etaSeconds),
      'size':
          '${_formatSize(item.downloadedBytes)} / ${_formatSize(item.totalBytes)}',
    }).catchError((e) { debugPrint('Channel method error: $e'); });
    _syncLiveActivityState();

    final now = DateTime.now();
    if (now.difference(_lastNotifyTime).inMilliseconds > 250) {
      _lastNotifyTime = now;
      notifyListeners();
      // Periodically persist to DB in case of crash (every 5 seconds)
      if (now.difference(_lastSaveTime).inSeconds > 5) {
        _lastSaveTime = now;
        DatabaseHelper().updateDownload(item);
      }
    }
  }

  void _handleDownloadError(DownloadItem item, dynamic e) {
    if (e is DioException && CancelToken.isCancel(e)) {
      return;
    }

    if (item.retryCount < 3) {
      item.retryCount++;
      item.status = DownloadStatus.queued;
    } else {
      item.status = DownloadStatus.error;
      item.errorMessage = e.toString();
      _showiOSNotification("Download Failed", item.fileName);
    }
    DatabaseHelper().updateDownload(item);
  }

  // --- Integrity Checker (Isolate) ---
  Future<bool> verifyFileHash(String filePath, String expectedHash) async {
    expectedHash = expectedHash.trim().toLowerCase();
    if (expectedHash.isEmpty) return false;

    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      // Use Isolate to prevent UI freezing on multi-GB files
      final String calculatedHash = await Isolate.run(() async {
        final f = File(filePath);
        // Determine algorithm by length
        // We use ProxySink because startChunkedConversion expects a Sink<Digest>, but we just want the final value.
        // Actually, crypto's cleaner way in an isolate:
        final stream = f.openRead();
        if (expectedHash.length == 32) {
          final digest = await md5.bind(stream).first;
          return digest.toString();
        } else {
          final digest = await sha256.bind(stream).first;
          return digest.toString();
        }
      });

      return calculatedHash.toLowerCase() == expectedHash;
    } catch (e) {
      debugPrint('Hash verification error: $e');
      return false;
    }
  }

  // --- Live Activities (iOS 16.1+) ---
  Future<bool> isLiveActivitySupported() async {
    if (!_isIOS) return false;
    try {
      return await _liveActivityChannel.invokeMethod('isSupported') ?? false;
    } catch (e) {
      debugPrint('Live Activity isSupported error: $e');
      return false;
    }
  }

  void _syncLiveActivityState() {
    if (!_isIOS) return;
    final active = _queue.where((d) => d.status == DownloadStatus.downloading).toList();

    if (active.isNotEmpty && !_backgroundServicesRunning) {
      _backgroundServicesRunning = true;
      _backgroundServiceChannel.invokeMethod('startBackgroundServices')
          .catchError((e) => debugPrint('startBackgroundServices error: $e'));
    } else if (active.isEmpty && _backgroundServicesRunning) {
      _backgroundServicesRunning = false;
      _backgroundServiceChannel.invokeMethod('stopBackgroundServices')
          .catchError((e) => debugPrint('stopBackgroundServices error: $e'));
    }

    if (active.isEmpty) {
      if (onAllDownloadsComplete != null) onAllDownloadsComplete!();
      _liveActivityChannel.invokeMethod('updateActiveDownloads', {
        'count': 0,
        'primary': null,
      }).catchError((e) => debugPrint('updateActiveDownloads error: $e'));
    } else {
      final primary = active.first;
      _liveActivityChannel.invokeMethod('updateActiveDownloads', {
        'count': active.length,
        'primary': {
          'fileName': primary.fileName,
          'progress': primary.progress,
          'speed': '${(primary.speedBytesPerSec / 1024 / 1024).toStringAsFixed(2)} MB/s',
          'eta': _formatDuration(primary.etaSeconds),
          'downloadedSize': _formatSize(primary.downloadedBytes),
          'totalSize': _formatSize(primary.totalBytes),
          'status': primary.statusLabel,
        },
      }).catchError((e) => debugPrint('updateActiveDownloads error: $e'));
    }
  }

  void _showiOSNotification(String title, String body) {
    if (!_isIOS) return;
    _iosNotificationChannel.invokeMethod('show', {
      'title': title,
      'body': body,
    }).catchError((e) => debugPrint('iOS notification error: $e'));
  }

  Future<void> enableLiveActivity() async {
    if (!_isIOS) return;
    try {
      await _liveActivityChannel.invokeMethod('enable');
      debugPrint('Live Activity enabled');
    } catch (e) {
      debugPrint('Live Activity enable error: $e');
    }
  }

  Future<void> disableLiveActivity() async {
    if (!_isIOS) return;
    try {
      await _liveActivityChannel.invokeMethod('disable');
    } catch (e) {
      debugPrint('Live Activity disable error: $e');
    }
  }

  Future<bool> isLiveActivityEnabled() async {
    if (!_isIOS) return false;
    try {
      return await _liveActivityChannel.invokeMethod('isEnabled') ?? true;
    } catch (e) {
      debugPrint('Live Activity isEnabled error: $e');
      return false;
    }
  }

  // --- Export / Import Queue ---
  Future<void> exportQueue() async {
    try {
      final jsonStr = jsonEncode(_queue.map((item) => item.toJson()).toList());
      // Create a temporary file
      final directory = Directory.systemTemp;
      final file = File(p.join(directory.path, 'dirxplore_queue_backup.json'));
      await file.writeAsString(jsonStr);

      // Share it
      await Share.shareXFiles([XFile(file.path)],
          text: 'DirXplore Download Queue Backup');
    } catch (e) {
      debugPrint('Export error: $e');
    }
  }

  Future<bool> importQueue() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonStr = await file.readAsString();
        final List<dynamic> list = jsonDecode(jsonStr);

        // Merge with existing queue or replace? Let's merge (avoiding duplicates by URL)
        int importedCount = 0;
        for (var itemJson in list) {
          final newItem = DownloadItem.fromJson(itemJson);
          if (!_queue.any((i) => i.url == newItem.url)) {
            // Reset status of imported items that were downloading/queued to paused
            // so they don't all start at once unexpectedly.
            if (newItem.status == DownloadStatus.downloading ||
                newItem.status == DownloadStatus.queued) {
              newItem.status = DownloadStatus.paused;
              newItem.speedBytesPerSec = 0;
            }
            _queue.add(newItem);
            importedCount++;
          }
        }

        if (importedCount > 0) {
          _saveQueue();
          notifyListeners();
          _processQueue();
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Import error: $e');
      return false;
    }
  }

  void revealFile(String path) {
    if (_isIOS) {
      _iosChannel.invokeMethod('openFileLocation', {'path': path})
          .catchError((e) { debugPrint('revealFile error: $e'); });
    }
  }

  void saveToFiles(String path) {
    if (_isIOS) {
      _iosChannel.invokeMethod('saveToFiles', {'path': path})
          .catchError((e) { debugPrint('saveToFiles error: $e'); });
    }
  }
}

// Helper for older dart runtimes if bind() isn't available, but bind() is standard.
class ProxySink implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}

String _formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
  return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
}

String _formatSize(int bytes) {
  if (bytes < 0) return "Unknown";
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
