import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import '../models/download_item.dart';
import '../models/torrent_task_model.dart';
import 'torrent_repository.dart';

class MagnetInfo {
  final String hash;
  final String? displayName;
  final List<String> trackers;

  MagnetInfo({required this.hash, this.displayName, this.trackers = const []});
}

class TorrentMetaResult {
  final String name;
  final int totalSize;
  final int fileCount;
  final List<String> fileNames;
  final List<int> fileSizes;
  final Uint8List metadata;

  TorrentMetaResult({
    required this.name,
    required this.totalSize,
    required this.fileCount,
    required this.fileNames,
    required this.fileSizes,
    required this.metadata,
  });
}

class TorrentEngineService {
  static final TorrentEngineService _instance = TorrentEngineService._internal();
  factory TorrentEngineService() => _instance;
  TorrentEngineService._internal();

  final Map<String, TorrentTask> _tasks = {};
  final Map<String, Timer> _pollers = {};
  final Map<String, StreamController<TorrentTaskModel>> _controllers = {};
  final Map<String, Uint8List> _metadataCache = {};
  final TorrentRepository _repo = TorrentRepository();

  // Proxy settings stored for future native engine integration
  // ignore: unused_field
  bool _proxyEnabled = false;
  // ignore: unused_field
  String? _proxyHost;
  // ignore: unused_field
  int? _proxyPort;

  void setProxySettings({required String host, required int port, String? username, String? password}) {
    _proxyEnabled = true;
    _proxyHost = host;
    _proxyPort = port;
  }

  MagnetInfo parseMagnet(String magnet) {
    final magnetData = MagnetParser.parse(magnet);
    if (magnetData == null) throw FormatException('Invalid magnet link');
    final xtMatch = RegExp(r'xt=urn:btih:([^&]+)').firstMatch(magnet);
    final hash = xtMatch?.group(1) ?? '';
    final dnMatch = RegExp(r'dn=([^&]+)').firstMatch(magnet);
    final displayName = dnMatch != null ? Uri.decodeComponent(dnMatch.group(1)!) : null;
    final trMatches = RegExp(r'tr=([^&]+)').allMatches(magnet);
    final trackers = trMatches.map((m) => Uri.decodeComponent(m.group(1)!)).toList();
    debugPrint('[TorrentEngine] Parsed: hash=$hash name=$displayName trackers=${trackers.length}');
    return MagnetInfo(hash: hash, displayName: displayName ?? magnetData.infoHashString, trackers: trackers);
  }

  Future<TorrentMetaResult> fetchMetadata(String magnet, {void Function(String)? onStatus}) async {
    const maxRetries = 3;
    const timeout = Duration(seconds: 120);
    String? lastError;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      debugPrint('[TorrentEngine] Metadata attempt $attempt/$maxRetries');
      onStatus?.call('Initializing torrent engine (attempt $attempt/$maxRetries)...');
      try {
        return await _fetchSingle(magnet, timeout: timeout, onStatus: onStatus);
      } catch (e) {
        lastError = e.toString();
        debugPrint('[TorrentEngine] Attempt $attempt failed: $e');
        if (attempt < maxRetries) {
          final wait = attempt * 3;
          onStatus?.call('Retrying in ${wait}s (attempt $attempt/$maxRetries)...');
          await Future.delayed(Duration(seconds: wait));
        }
      }
    }
    throw TorrentMetadataException(_friendlyError(lastError));
  }

  Future<TorrentMetaResult> _fetchSingle(String magnet,
      {required Duration timeout, void Function(String)? onStatus}) async {
    final downloader = MetadataDownloader.fromMagnet(magnet);
    final completer = Completer<Uint8List>();
    final statusTimer = _statusTimer(onStatus);

    downloader.events.on<MetaDataDownloadComplete>((event) {
      debugPrint('[TorrentEngine] Metadata received: ${event.data.length} bytes');
      if (!completer.isCompleted) completer.complete(Uint8List.fromList(event.data));
    });
    downloader.events.on<MetaDataDownloadFailed>((event) {
      debugPrint('[TorrentEngine] Metadata failed: ${event.error}');
      if (!completer.isCompleted) completer.completeError(event.error);
    });

    try {
      onStatus?.call('Connecting to DHT...');
      await downloader.startDownload();
      onStatus?.call('Contacting trackers...');
      final data = await completer.future.timeout(timeout, onTimeout: () {
        downloader.stop();
        throw TimeoutException('No peers found after ${timeout.inSeconds}s');
      });
      final model = TorrentParser.parseBytes(data);
      _metadataCache[magnet] = data;
      debugPrint('[TorrentEngine] Parsed: "${model.name}" ${model.files.length} files');
      return TorrentMetaResult(
        name: model.name,
        totalSize: model.files.fold<int>(0, (s, f) => s + f.length),
        fileCount: model.files.length,
        fileNames: model.files.map((f) => f.name).toList(),
        fileSizes: model.files.map((f) => f.length).toList(),
        metadata: data,
      );
    } finally {
      statusTimer.cancel();
    }
  }

  Timer _statusTimer(void Function(String)? cb) {
    const msgs = ['Connecting to DHT...', 'Contacting trackers...', 'Searching for peers...', 'Downloading metadata...'];
    int i = 0;
    cb?.call(msgs[0]);
    return Timer.periodic(const Duration(seconds: 5), (_) {
      i = (i + 1) % msgs.length;
      cb?.call(msgs[i]);
    });
  }

  String _friendlyError(String? raw) {
    if (raw == null) return 'Failed to fetch torrent metadata.';
    final lower = raw.toLowerCase();
    if (lower.contains('timeout')) return 'No peers found. Please try again later or use another magnet link.';
    if (lower.contains('dht') || lower.contains('tracker')) return 'Could not reach the torrent network.';
    if (lower.contains('invalid') || lower.contains('parse')) return 'The magnet link appears to be invalid.';
    return raw.length > 120 ? raw.substring(0, 120) : raw;
  }

  Uint8List? getCachedMetadata(String magnet) => _metadataCache[magnet];

  Stream<TorrentTaskModel> startTask(DownloadItem item, {bool isSequential = false, Uint8List? metadata}) {
    final controller = StreamController<TorrentTaskModel>.broadcast();
    _controllers[item.id] = controller;

    _startTaskInner(item, controller, isSequential: isSequential, metadata: metadata);

    return controller.stream;
  }

  Future<void> _startTaskInner(DownloadItem item, StreamController<TorrentTaskModel> controller,
      {bool isSequential = false, Uint8List? metadata}) async {
    try {
      final magnet = item.url;
      final Uint8List metaBytes = metadata ?? _metadataCache[magnet] ??
          (await fetchMetadata(magnet).then((r) => r.metadata));

      final model = TorrentParser.parseBytes(metaBytes);
      final task = TorrentTask.newTask(model, item.savePath, isSequential);
      _tasks[item.id] = task;

      final taskModel = TorrentTaskModel(
        id: item.id,
        magnetLink: magnet,
        savePath: item.savePath,
        name: model.name,
        infoHash: item.torrentHash ?? '',
        state: TorrentTaskState.downloading,
        totalBytes: model.files.fold<int>(0, (s, f) => s + f.length),
        trackers: item.torrentTrackers?.split(', ').where((t) => t.isNotEmpty).toList() ?? [],
        selectedFileIndices: item.selectedFileIndices,
        isSequential: isSequential,
        metadataBytes: metaBytes,
      );
      await _repo.insert(taskModel);

      task.events.on<TaskCompleted>((_) async {
        taskModel.state = TorrentTaskState.completed;
        taskModel.progress = 1.0;
        taskModel.downloadSpeed = 0;
        taskModel.uploadSpeed = 0;
        await _repo.update(taskModel);
        controller.add(taskModel);
        await Future.delayed(const Duration(milliseconds: 500));
        await controller.close();
        _controllers.remove(item.id);
      });

      await task.start();
      _startPolling(item.id, taskModel, controller);
    } catch (e) {
      debugPrint('[TorrentEngine] Task start error: $e');
      final tm = TorrentTaskModel(
        id: item.id, magnetLink: item.url, savePath: item.savePath,
        state: TorrentTaskState.error, errorMessage: e.toString(),
      );
      controller.add(tm);
      await controller.close();
      _controllers.remove(item.id);
    }
  }

  void _startPolling(String id, TorrentTaskModel tm, StreamController<TorrentTaskModel> c) {
    _pollers[id]?.cancel();
    _pollers[id] = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final task = _tasks[id];
      if (task == null) { timer.cancel(); return; }

      final progress = task.progress;
      final dlSpeed = task.currentDownloadSpeed;
      final ulSpeed = task.uploadSpeed;
      final total = task.metaInfo.files.fold<int>(0, (s, f) => s + f.length);
      final downloaded = (progress * total).toInt();
      final remaining = total - downloaded;
      final eta = dlSpeed > 0 ? (remaining / dlSpeed).round() : 0;

      int seeders = 0;
      try {
        final ap = task.activePeers;
        if (ap != null) seeders = ap.length;
      } catch (_) {}

      tm.progress = progress;
      tm.downloadedBytes = downloaded;
      tm.totalBytes = total;
      tm.downloadSpeed = dlSpeed.toDouble();
      tm.uploadSpeed = ulSpeed.toDouble();
      tm.etaSeconds = eta;
      tm.seeders = seeders;
      tm.state = progress >= 1.0 ? TorrentTaskState.completed : TorrentTaskState.downloading;

      if (progress >= 1.0) timer.cancel();
      c.add(tm);

      if ((progress * 100).toInt() % 10 == 0) {
        await _repo.update(tm);
      }
    });
  }

  Future<void> pauseTask(String id) async {
    _pollers[id]?.cancel();
    _tasks[id]?.pause();
    final models = await _repo.getAll();
    final idx = models.indexWhere((m) => m.id == id);
    if (idx != -1) {
      models[idx].state = TorrentTaskState.paused;
      await _repo.update(models[idx]);
    }
  }

  Future<void> resumeTask(String id) async {
    final task = _tasks[id];
    if (task != null) {
      task.resume();
      final models = await _repo.getAll();
      final idx = models.indexWhere((m) => m.id == id);
      if (idx != -1) {
        models[idx].state = TorrentTaskState.downloading;
        await _repo.update(models[idx]);
        _startPolling(id, models[idx], _controllers[id] ?? StreamController<TorrentTaskModel>.broadcast());
      }
    }
  }

  Future<void> stopTask(String id) async {
    _pollers[id]?.cancel();
    _pollers.remove(id);
    _tasks[id]?.stop();
    _tasks.remove(id);
    await _controllers[id]?.close();
    _controllers.remove(id);
    await _repo.delete(id);
  }

  Future<List<TorrentTaskModel>> getSavedTasks() => _repo.getAll();

  Future<void> restoreTask(String id) async {
    final models = await _repo.getAll();
    final task = models.where((m) => m.id == id).firstOrNull;
    if (task == null) return;
    if (task.metadataBytes != null) {
      try {
        final model = TorrentParser.parseBytes(task.metadataBytes!);
        final t = TorrentTask.newTask(model, task.savePath, task.isSequential);
        _tasks[id] = t;
        final controller = StreamController<TorrentTaskModel>.broadcast();
        _controllers[id] = controller;
        await t.start();
        _startPolling(id, task, controller);
      } catch (e) {
        debugPrint('[TorrentEngine] Restore failed: $e');
      }
    }
  }

  TorrentTask? getTask(String id) => _tasks[id];
  Stream<TorrentTaskModel>? streamFor(String id) => _controllers[id]?.stream;

  void dispose() {
    for (final t in _pollers.values) t.cancel();
    _pollers.clear();
    for (final t in _tasks.values) t.stop();
    _tasks.clear();
    for (final c in _controllers.values) c.close();
    _controllers.clear();
  }
}

class TorrentMetadataException implements Exception {
  final String message;
  TorrentMetadataException(this.message);
  @override
  String toString() => message;
}
