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

  // Proxy settings wired via ProxyConfig to TorrentTask.newTask()
  bool _proxyEnabled = false;
  String? _proxyHost;
  int? _proxyPort;
  String? _proxyUser;
  String? _proxyPass;

  void setProxySettings({required String host, required int port, String? username, String? password}) {
    _proxyEnabled = true;
    _proxyHost = host;
    _proxyPort = port;
    _proxyUser = username;
    _proxyPass = password;
  }

  void clearProxySettings() {
    _proxyEnabled = false;
    _proxyHost = null;
    _proxyPort = null;
    _proxyUser = null;
    _proxyPass = null;
  }

  ProxyConfig? _buildProxyConfig() {
    if (!_proxyEnabled || _proxyHost == null) return null;
    return ProxyConfig.socks5(
      host: _proxyHost!,
      port: _proxyPort ?? 1080,
      username: _proxyUser,
      password: _proxyPass,
    );
  }

  // Well-known DHT bootstrap nodes
  static final List<Uri> _defaultDHTNodes = [
    Uri.parse('udp://router.bittorrent.com:6881'),
    Uri.parse('udp://dht.transmissionbt.com:6881'),
    Uri.parse('udp://dht.aelitis.com:6881'),
    Uri.parse('udp://dht.iknow.com:6881'),
    Uri.parse('udp://opentor.org:2710'),
  ];

  // Public trackers used as fallback when magnet has none
  static final List<Uri> _fallbackTrackers = [
    Uri.parse('udp://tracker.opentrackr.org:1337/announce'),
    Uri.parse('udp://tracker.torrent.eu.org:451/announce'),
    Uri.parse('udp://open.tracker.cl:1337/announce'),
    Uri.parse('udp://tracker.moeking.me:6969/announce'),
    Uri.parse('https://tracker.tamersunion.org:443/announce'),
    Uri.parse('udp://explodie.org:6969/announce'),
    Uri.parse('udp://tracker.dler.org:6969/announce'),
    Uri.parse('udp://tracker.leechers-paradise.org:6969/announce'),
  ];

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
          final wait = 3 + attempt * 3;
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
    onStatus?.call('Connecting to peers and fetching metadata...');

    downloader.events.on<MetaDataDownloadComplete>((event) {
      debugPrint('[TorrentEngine] Metadata received: ${event.data.length} bytes');
      if (!completer.isCompleted) completer.complete(Uint8List.fromList(event.data));
    });
    downloader.events.on<MetaDataDownloadFailed>((event) {
      debugPrint('[TorrentEngine] Metadata failed: ${event.error}');
      if (!completer.isCompleted) completer.completeError(event.error);
    });

    try {
      await downloader.startDownload();
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
    }
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

      // Build SequentialConfig with proper buffer sizing
      final SequentialConfig? seqConfig = isSequential
          ? SequentialConfig.forVideoStreaming()
          : null;

      // Gather web seeds and acceptable sources from magnet
      final magnetData = MagnetParser.parse(magnet);
      final webSeeds = magnetData?.webSeeds;
      final acceptableSources = magnetData?.acceptableSources;

      // Build tracker list: magnet's announces + fallback publics
      final allTrackers = <Uri>{};
      allTrackers.addAll(model.announces);
      allTrackers.addAll(_fallbackTrackers);
      // Add any trackers from magnet that aren't in announces
      if (magnetData != null) {
        for (final tr in magnetData.trackers) {
          allTrackers.add(tr);
        }
      }

      // Build a mock TorrentModel with all trackers merged
      // (TorrentTask.newTask uses model.announces, so we need to re-create)
      final enrichedModel = TorrentModel(
        name: model.name,
        files: model.files,
        infoHashBuffer: model.infoHashBuffer,
        pieceLength: model.pieceLength,
        pieces: model.pieces,
        announces: allTrackers.toList(),
        nodes: [..._defaultDHTNodes, ...model.nodes],
        length: model.length,
        version: model.version,
        metaVersion: model.metaVersion,
        fileTree: model.fileTree,
        pieceLayers: model.pieceLayers,
        rootHash: model.rootHash,
        infoDictBytes: model.infoDictBytes,
        rawData: model.rawData,
      );

      final task = TorrentTask.newTask(
        enrichedModel,
        item.savePath,
        isSequential,
        webSeeds,
        acceptableSources,
        seqConfig,
        _buildProxyConfig(),
      );
      _tasks[item.id] = task;

      final total = enrichedModel.files.fold<int>(0, (s, f) => s + f.length);

      final taskModel = TorrentTaskModel(
        id: item.id,
        magnetLink: magnet,
        savePath: item.savePath,
        name: enrichedModel.name,
        infoHash: item.torrentHash ?? enrichedModel.infoHash,
        state: TorrentTaskState.downloading,
        totalBytes: total,
        trackers: allTrackers.map((u) => u.toString()).toList(),
        selectedFileIndices: item.selectedFileIndices,
        isSequential: isSequential,
        metadataBytes: metaBytes,
        totalPieces: enrichedModel.pieces?.length ?? 0,
      );
      await _repo.insert(taskModel);

      // -- Wire events --

      task.events.on<TaskFileCompleted>((event) {
        final fileName = event.file.originalFileName;
        debugPrint('[TorrentEngine] File completed: $fileName');
        taskModel.filesCompleted.add(fileName);
      });

      task.events.on<StateFileUpdated>((_) async {
        await _repo.update(taskModel);
      });

      task.events.on<TaskPaused>((_) async {
        taskModel.state = TorrentTaskState.paused;
        await _repo.update(taskModel);
        controller.add(taskModel);
      });

      task.events.on<TaskResumed>((_) async {
        taskModel.state = TorrentTaskState.downloading;
        controller.add(taskModel);
      });

      task.events.on<TaskStopped>((_) async {
        taskModel.state = TorrentTaskState.error;
        controller.add(taskModel);
      });

      task.events.on<TaskCompleted>((_) async {
        taskModel.state = TorrentTaskState.seeding;
        taskModel.progress = 1.0;
        taskModel.downloadSpeed = 0;
        taskModel.uploadSpeed = 0;
        taskModel.seeders = task.seederNumber;
        taskModel.peers = task.connectedPeersNumber;
        await _repo.update(taskModel);
        controller.add(taskModel);

        // Transition to completed after a brief seeding period
        taskModel.state = TorrentTaskState.completed;
        await _repo.update(taskModel);
        controller.add(taskModel);

        await Future.delayed(const Duration(milliseconds: 500));
        await controller.close();
        _controllers.remove(item.id);
      });

      // Apply file selection and auto-prioritize
      if (item.selectedFileIndices.isNotEmpty) {
        task.applySelectedFiles(item.selectedFileIndices);
      }
      task.autoPrioritizeFiles();

      // Add DHT bootstrap nodes
      for (final node in _defaultDHTNodes) {
        task.addDHTNode(node);
      }

      await task.start();
      task.requestPeersFromDHT();

      // Add DHT nodes again after start
      for (final node in _defaultDHTNodes) {
        task.addDHTNode(node);
      }

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
    double lastProgress = -1;

    _pollers[id] = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final task = _tasks[id];
      if (task == null) { timer.cancel(); return; }

      try {
        final progress = task.progress;
        final dlSpeed = task.currentDownloadSpeed;
        final ulSpeed = task.uploadSpeed;
        final avgDlSpeed = task.averageDownloadSpeed;
        final avgUlSpeed = task.averageUploadSpeed;
        final total = task.metaInfo.files.fold<int>(0, (s, f) => s + f.length);
        final downloaded = task.downloaded ?? (progress * total).toInt();
        final remaining = total - downloaded;
        final eta = dlSpeed > 0 ? (remaining / dlSpeed).round() : 0;

        final seeders = task.seederNumber;
        final connectedPeers = task.connectedPeersNumber;
        final allPeers = task.allPeersNumber;

        tm.progress = progress;
        tm.downloadedBytes = downloaded;
        tm.totalBytes = total;
        tm.downloadSpeed = dlSpeed.toDouble();
        tm.uploadSpeed = ulSpeed.toDouble();
        tm.averageDownloadSpeed = avgDlSpeed;
        tm.averageUploadSpeed = avgUlSpeed;
        tm.etaSeconds = eta;
        tm.seeders = seeders;
        tm.peers = connectedPeers;
        tm.allPeers = allPeers;

        if (progress >= 1.0) {
          tm.state = TorrentTaskState.seeding;
        } else if (tm.state != TorrentTaskState.paused) {
          tm.state = TorrentTaskState.downloading;
        }

        c.add(tm);

        // Auto-save at 5% intervals + 0.1s debounce after progress change
        final pct = (progress * 100).toInt();
        final lastPct = (lastProgress * 100).toInt();
        if (pct >= 0 && pct % 5 == 0 && pct != lastPct) {
          await _repo.update(tm);
        }
        lastProgress = progress;
      } catch (e) {
        debugPrint('[TorrentEngine] Poll error: $e');
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
        final seqConfig = task.isSequential
            ? SequentialConfig.forVideoStreaming()
            : null;

        // Rebuild tracker-enriched model for restore
        final enrichedModel = TorrentModel(
          name: model.name,
          files: model.files,
          infoHashBuffer: model.infoHashBuffer,
          pieceLength: model.pieceLength,
          pieces: model.pieces,
          announces: [...model.announces, ..._fallbackTrackers],
          nodes: [..._defaultDHTNodes, ...model.nodes],
          length: model.length,
          version: model.version,
          metaVersion: model.metaVersion,
          fileTree: model.fileTree,
          pieceLayers: model.pieceLayers,
          rootHash: model.rootHash,
          infoDictBytes: model.infoDictBytes,
          rawData: model.rawData,
        );

        final t = TorrentTask.newTask(
          enrichedModel,
          task.savePath,
          task.isSequential,
          null,
          null,
          seqConfig,
          _buildProxyConfig(),
        );
        _tasks[id] = t;

        // Apply file selections
        if (task.selectedFileIndices.isNotEmpty) {
          t.applySelectedFiles(task.selectedFileIndices);
        }
        t.autoPrioritizeFiles();

        // DHT nodes
        for (final node in _defaultDHTNodes) {
          t.addDHTNode(node);
        }

        final controller = StreamController<TorrentTaskModel>.broadcast();
        _controllers[id] = controller;
        await t.start();
        t.requestPeersFromDHT();
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

String _friendlyError(String? raw) {
  if (raw == null) return 'Failed to fetch torrent metadata.';
  final lower = raw.toLowerCase();
  if (lower.contains('timeout')) return 'No peers found. Please try again later or use another magnet link.';
  if (lower.contains('dht') || lower.contains('tracker')) return 'Could not reach the torrent network.';
  if (lower.contains('invalid') || lower.contains('parse')) return 'The magnet link appears to be invalid.';
  return raw.length > 120 ? raw.substring(0, 120) : raw;
}
